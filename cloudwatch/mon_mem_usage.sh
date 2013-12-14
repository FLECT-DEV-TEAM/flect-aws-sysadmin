#!/bin/sh

instanceid=`wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`

freemem=`free -m | awk "NR==2 {print}" | awk '{ print $4 }'`
usedmem=`free -m | awk "NR==2 {print}" | awk '{ print $3 }'`
cachedmem=`free -m | awk "NR==2 {print}" | awk '{ print $7 }'`
usedmempercent=`free -m | awk "NR==2 {print}" | awk '{ print ($3/$2)*100 }'`

aws cloudwatch put-metric-data --namespace 'System/Linux' --metric-name 'UsedMemoryMBytes' --unit 'Megabytes' --value $usedmem --dimensions "InstanceId=$instanceid"
aws cloudwatch put-metric-data --namespace 'System/Linux' --metric-name 'FreeMemoryMBytes' --unit 'Megabytes' --value $freemem --dimensions "InstanceId=$instanceid"
aws cloudwatch put-metric-data --namespace 'System/Linux' --metric-name 'UsedMemoryPercent' --unit 'Percent' --value $usedmempercent --dimensions "InstanceId=$instanceid"