#!/usr/bin/env perl

use strict;
use warnings;

use AWS::CLIWrapper;
use Data::Dumper;
use Sys::Syslog qw(:DEFAULT setlogsock);
use Time::Piece;
use Time::Seconds;

use constant TIME_DIFFERENCE_JST => 9;

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

sub get_snapshot_id {
    my $image = shift;

    if ( $image->{RootDeviceType} eq 'ebs' ) {
        for my $dev ( @{ $image->{BlockDeviceMappings} } ) {
            if ( $dev->{Ebs} ) {
                return $dev->{Ebs}->{SnapshotId};
            }

        }
    }
}

sub is_image_for_purge {
    my $image     = shift;

    my $backup_days = get_tag_value($image, $ENV{'BACKUP_TAG'});

    if ( !($backup_days =~ /^[0-9]+$/) ) {
        syslog( 'warn',
            "NumberFormatError: Tag:$ENV{'BACKUP_TAG'} For input string. image_id=" . $image->{ImageId} . "Value = " . $backup_days );
        return;
    }

    # JST -> UTC
    my $t = localtime() - ( ONE_DAY * $backup_days ) - ( ONE_HOUR * TIME_DIFFERENCE_JST );
    my $purge_date = $t->strftime('%Y%m%d');

    # CreationDate > UTC
    if ( $image->{CreationDate} =~ m/(\d{4}+-\d{2}+-\d{2}+).+/) {
        my $backedup_date = $1;
        $backedup_date =~ s/-//g;

        if ( $purge_date < $backedup_date ) {
            return;
        }

        return 1;

    }
    else {
        return;
    }
}

sub get_backedup_images {
    my @images = ();

    my $res = $aws->ec2(
        'describe-images' => {
            owners  => 'self',
            filters => [{ name => "tag:$ENV{'BACKUP_TAG'}", values => ["1*","2*","3*","4*","5*","6*","7*","8*","9*"] }]
        },
        timeout => 18,    # optional. default is 30 seconds
    );

    if ($res) {
        for my $im ( @{ $res->{Images} } ) {
            if ( is_image_for_purge( $im ) ) {
                push( @images, $im );
            }
        }

    }
    else {
        syslog( 'err',
                "describe images failed, code= "
              . $AWS::CLIWrapper::Error->{Code}
              . ', message='
              . $AWS::CLIWrapper::Error->{Message} );
    }

    return @images;
}

sub purge_image {
    my $image = shift;

    my $snapshot_id = get_snapshot_id($image);

    my $res = $aws->ec2(
        'deregister-image' => {
            image_id => $image->{ImageId},
        },
        timeout => 18,    # optional. default is 30 seconds
    );

    if ($res) {
        syslog( 'info',
            "deregister image succeeded image_id=" . $image->{ImageId} );
    }
    else {
        syslog( 'err',
                "deregister image failed image_id="
              . $image->{ImageId}
              . ", code="
              . $AWS::CLIWrapper::Error->{Code}
              . ', message='
              . $AWS::CLIWrapper::Error->{Message} );
        return;
    }

    $res = $aws->ec2(
        'delete-snapshot' => {
            'snapshot-id' => $snapshot_id,
        },
        timeout => 18,    # optional. default is 30 seconds
    );

    if ($res) {
        syslog( 'info',
            "delete snasphot succeeded snapshot_id=" . $snapshot_id );
    }
    else {
        syslog( 'err',
                "delete snapshot failed snapshot_id=$snapshot_id, code="
              . $AWS::CLIWrapper::Error->{Code}
              . ', message='
              . $AWS::CLIWrapper::Error->{Message} );
    }

}

sub purge_images {
    my @images = get_backedup_images();

    for my $im (@images) {
        purge_image($im);
    }

}

sub main {

    # use unix domain socket for syslog
    setlogsock 'unix';

    openlog( __FILE__, 'pid', 'local6' );

    purge_images();

    closelog();
}

main();

1;

