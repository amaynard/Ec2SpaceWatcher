#!/bin/bash

. common.bash

function waitfordevice()
{
	DEVICE=$1
	echo -n "waiting for device to show up"	
	while [ "$( ls $DEVICE 2> /dev/null | wc -l )" == "0" ]; do
		echo -n "."
		sleep .1
	done
	echo
}

function attachvolume()
{
	DEVICE=$1
	VOLUME=$2
	
	if [[ -z "${DEVICE// }" || -z "${VOLUME// }" ]];
	then
		return 0
	fi

	XVDEVICE=$DEVICE
	if [[ $DEVICE = *"nvme"* ]];
	then
		let drive=97+${DEVICE:9}
		XVDEVICE=/dev/xvd$( chr $drive )
	fi  

	echo Adding device $DEVICE
	attachedtest=1
	until [[ $attachedtest -eq 0 ]]; do
		attachedtest=`aws ec2 --region $REGION attach-volume --volume-id $VOLUME --instance-id $INSTANCEID --device $XVDEVICE 2>&1 | grep -q VolumeInUse; echo $?`
		sleep $((SPACEWATCHER_POLLDELAY_S+RANDOM%SPACEWATCHER_POLLJITTER_S))
	done
	
	aws ec2 --region $REGION modify-instance-attribute --instance-id $INSTANCEID --block-device-mappings DeviceName=$XVDEVICE,Ebs={DeleteOnTermination=true}

	waitfordevice $DEVICE
}

DISKCOUNT=${2:-6}
TOTALSIZE=${1:-333}
DISKSIZE=$((TOTALSIZE/DISKCOUNT))

echo "adding $DISKCOUNT drives of size $DISKSIZE"

TMP=`mktemp -up /tmp`
mkdir -p $TMP

export REGION INSTANCEID AZ DISKSIZE TMP
export -f attachvolume waitfordevice

# create volumes
seq 1 $DISKCOUNT | xargs -I{} -P${SPACEWATCHER_PARALLELISM} bash -c "aws ec2 --region $REGION create-volume --volume-type gp2 --availability-zone $AZ --encrypted --size $DISKSIZE --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=\"Instance Drive\"},{Key=ManagedBy,Value=MissionControl},{Key=KeepUntil,Value=InstanceLifetime},{Key=InstanceId,Value='$INSTANCEID'}]'  | jq \".VolumeId\" | tr -d '\"' > $TMP/{}"

# f1 instances -> /dev/xvda + /dev/nvme0n1 -> adding /dev/xvdb results in adding /dev/xvdb
# c4 instances -> /dev/xvda                -> adding /dev/xvdb results in adding /dev/xvdb
# c5 instance  -> /dev/nvme0n1             -> adding /dev/xvdb results in adding /dev/nvme1n1
if [[ -e /dev/nvme0 && ! -e /dev/xvda ]];
then
	alldrives=`echo /dev/nvme{1..25}`
	actualdrives=`ls /dev/nvme* | tr " " "\n" | sort -k1.10 -n | egrep "nvme[[:digit:]]+$" | egrep -v "nvme0$" `
else
	alldrives=`echo /dev/xvd{b..z}`
	actualdrives=`ls /dev/xvd* | tr " " "\n" | grep -v "xvda"`
fi

NEWVOLUMECOUNT=`cat $TMP/* | wc -l`
NEXTDEVICES=`comm --nocheck-order -23 <( echo $alldrives | tr " " "\n") <( echo $actualdrives | tr " " "\n" ) | head -$NEWVOLUMECOUNT`

paste <( echo $NEXTDEVICES | tr "\n" " " | tr " " "\n" ) <( cat $TMP/* ) > $TMP/devicevol
cat $TMP/devicevol | xargs -d'\n' -P${SPACEWATCHER_PARALLELISM} -n2 -I{} bash -c "attachvolume {}"

rm -Rf $TMP

sleep 5
