#!/usr/bin/env perl

use strict;
use warnings;

use AWS::CLIWrapper;
use Data::Dumper;
use Sys::Syslog qw(:DEFAULT setlogsock);
use Time::Piece;

our $aws = AWS::CLIWrapper->new();

sub get_tag_value {
    my $is = shift;
    my $tagname = shift;

    for my $tag ( @{ $is->{Tags} } ) {
        if ( $tag->{Key} eq $tagname ) {
            return $tag->{Value};
        }
    }

    if ( $tagname eq 'Name' ) {
        return $is->{InstanceId};
    }

    return '';
}

sub get_instances {
    my @instances = ();

    my $res = $aws->ec2(
        'describe-instances' => {'filters' => [{ name => "tag:$ENV{'BACKUP_TAG'}", values => ["1*","2*","3*","4*","5*","6*","7*","8*","9*"] }],},
        timeout              => 18,    # optional. default is 30 seconds
    );

    if ($res) {
        for my $rs ( @{ $res->{Reservations} } ) {
            for my $is ( @{ $rs->{Instances} } ) {
                push( @instances, $is );
            }
        }
    }
    else {
        syslog( 'err',
                'describe instances failed code='
              . $AWS::CLIWrapper::Error->{Code}
              . ', message='
              . $AWS::CLIWrapper::Error->{Message} );
    }

    return @instances;
}

sub get_tags {
    my $is = shift;

    my @tags = ();

    # COST_ALLOCATION_TAG
    if (!defined($ENV{'COST_ALLOCATION_TAG'})) {
        syslog( 'info', "ENV:COST_ALLOCATION_TAG does not defined. processing of create_tag skipped." );
    } else {
        push( @tags, {
                    Key => $ENV{'COST_ALLOCATION_TAG'},
                    Value => get_tag_value($is, $ENV{'COST_ALLOCATION_TAG'})
                }
        );
    }

    # BACKUP_DAYS_TAG
    push( @tags, {
                Key => $ENV{'BACKUP_TAG'},
                Value => get_tag_value($is, $ENV{'BACKUP_TAG'})
            }
    );

    return @tags;
}


sub create_tags {
    my $imageid = shift;
    my @tags = @_;

    for my $tag (@tags) {
        if ($tag->{Value} ne '') {
            my $res  = $aws->ec2(
                'create-tags' => {
                    'resources'   => $imageid,
                    'tags'        => [{
                                         Key   => $tag->{Key},
                                         Value => $tag->{Value}
                                    }],
                },
                timeout => 18,    # optional. default is 30 seconds
            );

            if ($res) {
                syslog( 'info', "create tags suceeded imageid=$imageid, tag=$tag->{Key}" );
            }
            else {
                syslog( 'err',
                    "create tags failed imageid=$imageid, tag=$tag->{Key} code="
                    . $AWS::CLIWrapper::Error->{Code}
                    . ', message='
                    . $AWS::CLIWrapper::Error->{Message} );
            }
        }
    }
}

sub create_images {
    my @instances = @_;

    my $t        = localtime;
    my $yyyymmdd = $t->strftime('%Y-%m-%d');

    for my $is (@instances) {
        my $name = get_tag_value($is, 'Name');
        my $res  = $aws->ec2(
            'create-image' => {
                'instance_id' => $is->{InstanceId},
                'name'        => 'autobackup-' . $yyyymmdd . '-' . $name,
                'no-reboot'   => '',
            },
            timeout => 18,    # optional. default is 30 seconds
        );
        if ($res) {
            syslog( 'info', "create image suceeded name=$name" );
            create_tags($res->{ImageId}, get_tags($is));
        }
        else {
            syslog( 'err',
                    "create image failed name=$name, code="
                  . $AWS::CLIWrapper::Error->{Code}
                  . ', message='
                  . $AWS::CLIWrapper::Error->{Message} );
        }
    }
}

sub main {

    # use unix domain socket for syslog
    setlogsock 'unix';

    openlog( __FILE__, 'pid', 'local6' );

    create_images( get_instances() );

    closelog();
}

main();

1;