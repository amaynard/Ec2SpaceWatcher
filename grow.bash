#!/bin/bash

. common.bash

# pause all io on mount
./freeze.bash $MOUNTPATH

# find out the next size to use
DISKSIZES=${SPACEWATCHER_GROWTHSEQUENCE_GB}
DISKCOUNT=${SPACEWATCHER_RAID_DRIVES}

echo $DISKSIZES
# find out the next size by which to extend the drives based 
# on current number of md drives
MDDRIVES=$( cat /proc/mdstat | grep md | wc -l )
LVDISPLAY=$( lvdisplay | grep /dev/vg_data/lv_data | wc -l )

let COL=1+$MDDRIVES
DISKSIZE=`echo $DISKSIZES | cut -d" " -f$COL`

# if no md drive and at least 1 local drive, then raid those, else add more disks
if [[ (($LVDISPLAY -eq 0) && ((-e /dev/xvdb ) || (-e /dev/nvme1n1))) ]]; then
    echo "skip adding EBS drives this first time around, gonna use instance store"
else
    ./attachdrives.bash $DISKSIZE $DISKCOUNT
fi

if [ -f ./pause.bash ];
then
 ./pause.bash
fi

./unfreeze.bash $MOUNTPATH
./createraid.bash

if [ -f ./unpause.bash ];
then
 ./unpause.bash
fi

