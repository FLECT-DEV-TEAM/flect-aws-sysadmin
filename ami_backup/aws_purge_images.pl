#!/usr/bin/env perl

use strict;
use warnings;

use AWS::CLIWrapper;
use Data::Dumper;
use Sys::Syslog qw(:DEFAULT setlogsock);
use Time::Piece;
use Time::Seconds;

use constant BACKUP_DAYS => 5;

our $aws = AWS::CLIWrapper->new();

sub get_instance_name {
    my $is = shift;

    for my $tag ( @{ $is->{Tags} } ) {
        if ( $tag->{Key} eq 'Name' ) {
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
                "describe instances failed, code="
              . $AWS::CLIWrapper::Error->{Code}
              . ', message='
              . $AWS::CLIWrapper::Error->{Message} );
    }

    return @instances;
}

sub get_shnapshot_id {
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
    my @instances = @_;

    my $t = localtime() - ( ONE_DAY * BACKUP_DAYS );
    my $purge_date = $t->strftime('%Y%m%d');

    if ( $image->{Name} =~ m/autobackup-(\d{4}+-\d{2}+-\d{2}+).+/ ) {
        my $backedup_date = $1;
        $backedup_date =~ s/-//g;

        if ( $purge_date < $backedup_date ) {
            return;
        }

        for my $is (@instances) {
            my $name = get_instance_name($is);
            if ( index( $image->{Name}, $name ) != -1 ) {
                return 1;
            }
        }

    }
    else {
        return;
    }
}

sub get_backedup_images {
    my @instances = @_;

    my @images = ();

    my $res = $aws->ec2(
        'describe-images' => {
            owners  => 'self',
            filters => 'Name=name,Values=*',
        },
        timeout => 18,    # optional. default is 30 seconds
    );

    if ($res) {
        for my $im ( @{ $res->{Images} } ) {
            if ( is_image_for_purge( $im, @instances ) ) {
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

    my $snapshot_id = get_shnapshot_id($image);

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
    my @instances = @_;

    my @images = get_backedup_images(@instances);

    my $t        = localtime;
    my $yyyymmdd = $t->strftime('%Y-%m-%d');

    for my $im (@images) {
        purge_image($im);
    }

}

sub main {

    # use unix domain socket for syslog
    setlogsock 'unix';

    openlog( __FILE__, 'pid', 'local6' );

    purge_images( get_instances() );

    closelog();
}

main();

1;
