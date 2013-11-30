#!/bin/sh

if [ -n "$1" ]; then
    path=$1
fi

instanceid=`wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`

freespace=`df --local --block-size=1M $path | grep $path | tr -s ' ' | cut -d ' ' -f 4`
usedpercent=`df --local $path | grep $path | tr -s ' ' | cut -d ' ' -f 5 | grep -o "[0-9]*"`

aws cloudwatch put-metric-data --namespace 'System/Linux' --metric-name 'FreeSpaceMBytes' --unit 'Megabytes' --value $freespace --dimensions "InstanceId=$instanceid,Path=$path"
aws cloudwatch put-metric-data --namespace 'System/Linux' --metric-name 'UsedSpacePercent' --unit 'Percent' --value $usedpercent --dimensions "InstanceId=$instanceid,Path=$path"