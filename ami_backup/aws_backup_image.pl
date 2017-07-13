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

    return $is->{InstanceId};
}

sub get_instances {
    my @instances = ();

    my $res = $aws->ec2(
        'describe-instances' => {},
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

sub create_tags {
    my $is = shift;
    my $imageid = shift;

    if (!defined($ENV{'COST_ALLOCATION_TAG'})) {
        syslog( 'info', "ENV:COST_ALLOCATION_TAG does not defined. processing of create_tag skipped." );
        return;
    }
    my $tagname = $ENV{'COST_ALLOCATION_TAG'};
    my $tagvalue = get_tag_value($is, $tagname);

    if ($tagvalue ne '') {
        my $res  = $aws->ec2(
            'create-tags' => {
                'resources'   => $imageid,
                'tags'        => [{
                                     Key   => $tagname,
                                     Value => $tagvalue
                                 }],
            },
            timeout => 18,    # optional. default is 30 seconds
        );

        if ($res) {
            syslog( 'info', "create tags suceeded imageid=$imageid" );
        }
        else {
            syslog( 'err',
                "create tags failed imageid=$imageid, code="
                . $AWS::CLIWrapper::Error->{Code}
                . ', message='
                . $AWS::CLIWrapper::Error->{Message} );
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
            create_tags($is, $res->{ImageId});
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