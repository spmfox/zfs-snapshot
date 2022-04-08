#!/bin/bash
#zfs-snapshot.sh
#spmfox@foxwd.com
 
opt_Logging="1"
var_UUID=$(date +%s%3N)
dir_TemporaryDirectory="/dev/shm"
 
var_ArgumentCounter=1
if [ "$#" -gt 0 ]; then
 while [ $var_ArgumentCounter -le $# ]; do
  str_CurrentArgument="'$'$var_ArgumentCounter"
  str_CurrentArgument=$(eval eval echo "$str_CurrentArgument")
 
  if echo "$str_CurrentArgument" |grep -q "dataset"; then
   str_SelectedDataset=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi
 
  if echo "$str_CurrentArgument" |grep -q "retain"; then
   var_RetentionPeriod=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi
 
  if echo "$str_CurrentArgument" |grep -q "grep"; then
   str_RetainGrep=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi
 
  if echo "$str_CurrentArgument" |grep -q "snapname"; then
   str_SnapshotName=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi 
 
  if echo "$str_CurrentArgument" |grep -q "replicatedest"; then
   str_ReplicateDestination=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi
 
  if echo "$str_CurrentArgument" |grep -q "replicatehost"; then
   str_ReplicateHost=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi

  if echo "$str_CurrentArgument" |grep -q "validatehost"; then
   str_ValidateHost=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi
 
  if echo "$str_CurrentArgument" |grep -q "hold"; then
   str_SnapshotHold=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi
 
  if echo "$str_CurrentArgument" |grep -q "skip-create"; then
   str_SkipSnapshotCreation="YES"
  fi
 
  if echo "$str_CurrentArgument" |grep -q "recursive"; then
   str_RecursiveSnapshot="YES"
  fi

  if echo "$str_CurrentArgument" |grep -q "kvm"; then
   str_KVM=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi

  if echo "$str_CurrentArgument" |grep -q "rollback"; then
   str_RecursiveRollback="YES"
  fi
 
  if echo "$str_CurrentArgument" |grep -q "logging"; then
   opt_Logging=$(echo "$str_CurrentArgument" |awk -F"=" '{print $2}')
  fi
 
  let var_ArgumentCounter+=1
 done
else
 echo " "
 echo "You must provide an argument to run this script. Here is an example for automatic snapshots:"
 echo "./zfs-auto-snapshot.sh -dataset=pool/dataset -snapname=Daily -retain=3 -grep=:05: -logging=1"
 echo " "
 echo "Here is an example for local replication:"
 echo "./zfs-auto-snapshot.sh -dataset=pool/dataset -replicatedest=pool2/dataset -snapname=Mirror -retain=1 -hold=replication -logging=1"
 echo " "
 echo "Here is an example for remote replication:"
 echo "./zfs-auto-snapshot.sh -dataset=pool -replicatehost=server -replicatedest=pool2 -snapname=Mirror -retain=1 -hold=replication -recursive -logging=1"
 echo " "
 echo "-dataset=:.........Required, specifies the ZFS dataset to snapshot."
 echo "-snapname=:........Required, name to be appended to snapshot."
 echo "-retain=:..........Optional, amount of snapshots to keep. No snapshots will be destroyed if this is not specified."
 echo "-grep=:............Optional, this string will be grepped for retention instead of the snapshot name."
 echo "-replicatedest=:...Optional, specify the destination pool/dataset for replication."
 echo "-replicatehost=:...Optional, for remote replication - will be used for SSH. Use of a .ssh/config file is recommended."
 echo "-validatehost=.....Optional, use Netcat to check SSH before anything happens. Expects host:port."
 echo "-hold=:............Optional, lock snapshot with this hold string. Snapshot creation and destroy will use this string."
 echo "-skip-create:......Optional, skips snapshot creation."
 echo "-recursive:........Optional, snapshot create, hold, and destroy are used with the '-r' argument."
 echo "-kvm=:.............Optional, specify the domain name and this will try to save a running VM (inside dataset previously specified) as root before performing the snapshot."
 echo "-rollback......... Optional, Attempt recursive rollback, used to fix broken destination if a recursive send failed mid-transfer."
 echo "-logging=:.........Optional, 0: No logs, no screen output. 1: No logs, output to screen. 2: Output sent to logger, no screen output."
 echo " "
 echo "Defaults: snapshot name is used for retention, logging is set to '1'. Replication and retention are optional, but snapshot creation is default."
 echo " "
 exit
fi
 
 

#Function for all output, to the console or logger. We expect the message to be used as the first argument for the function.
#Example: fn_Log "Message text"
function fn_Log {
 if [ -n "$1" ]; then
  if [ "$opt_Logging" -eq 0 ]; then
   return
  fi
  if [ "$opt_Logging" -eq 1 ]; then
   echo "zfs-snapshot: ($var_UUID) $1"
  fi
  if [ "$opt_Logging" -eq 2 ]; then
   logger "zfs-snapshot: ($var_UUID) $1"
  fi
  if [ "$opt_Logging" -ne 0 ] && [ "$opt_Logging" -ne 1 ] && [ "$opt_Logging" -ne 2 ]; then
   echo "zfs-snapshot: ERROR: Invalid logging argument."
  fi
 fi
}
 
 
 
function fn_ControlC {
 fn_Log "FATAL: CTRL-C or other kill method detected, please check logs on how to clean up state."
 rm -I "$dir_TemporaryDirectory"/"$var_UUID".replication 2> /dev/null
 exit 1
}
 
 
 
trap fn_ControlC SIGINT
 
 
 
function fn_CheckReplicationDuplicate {
 if [ -n "$str_ReplicateDestination" ]; then
  str_CheckOngoingMirror=$(cat $dir_TemporaryDirectory/*.replication 2> /dev/null |grep -w "$str_ReplicateDestination")
 fi
 if [ -n "$str_CheckOngoingMirror" ]; then
  fn_Log "FATAL: Another replication job is running for this destination: ($str_CheckOngoingMirror)."
  exit 1
 fi
}
 
 
 
function fn_ValidateHost {
 if [ -n "$str_ValidateHost" ]; then
  fn_Log "INFO: Attempting to validate SSH connection to $str_ValidateHost..."
  if which nc >/dev/null 2>&1 ; then
   str_ValidateHost1=$(echo $str_ValidateHost |awk -F ":" '{print $1}')
   str_ValidateHost2=$(echo $str_ValidateHost |awk -F ":" '{print $2}')
   if [ -n "$str_ValidateHost1" ] && [ -n "$str_ValidateHost2" ]; then
    str_ValidateHostCheck=$(timeout 5 nc -w 5 "$str_ValidateHost1" "$str_ValidateHost2" 2>&1 |grep -i SSH)
    if [ -n "$str_ValidateHostCheck" ]; then
     fn_Log "INFO: SSH is available at $str_ValidateHost1:$str_ValidateHost2."
    else
     fn_Log "FATAL: SSH does not seem available at $str_ValidateHost1:$str_ValidateHost2."
     exit 1
    fi
   else
    fn_Log "FATAL: Could not parse validatehost=$str_ValidateHost."
    exit 1
   fi
  else
   fn_Log "FATAL: nc (netcat) command not available on this system."
   exit 1
  fi
 fi
}



function fn_CreateSnapshot {
 var_DateTime=$(date +%Y-%m-%d_%T)
 if [ -z "$str_SkipSnapshotCreation" ]; then
  if [ -n "$str_SelectedDataset" ] && [ -n "$str_SnapshotName" ]; then
   str_CreateSnapshotVerifyDataset=$(zfs list $str_SelectedDataset 2>&1 |grep NAME)
   if [ -n "$str_CreateSnapshotVerifyDataset" ]; then
    if [ -n "$str_RecursiveSnapshot" ]; then
     fn_Log "INFO: Attempting recursive snapshot creation: 'zfs snapshot -r $str_SelectedDataset@$var_DateTime-$str_SnapshotName'."
     str_CreateSnapshotVerification=$(zfs snapshot -r "$str_SelectedDataset"@"$var_DateTime"-"$str_SnapshotName" 2>&1)
     if [ -n "$str_SnapshotHold" ]; then
      fn_Log "INFO: Attempting recursive snapshot hold: 'zfs hold -r $str_SnapshotHold $str_SelectedDataset@$var_DateTime-$str_SnapshotName'."
      str_LockSnapshotVerification=$(zfs hold -r "$str_SnapshotHold" "$str_SelectedDataset"@"$var_DateTime"-"$str_SnapshotName" 2>&1)
     fi
    else
     if [ -n "$str_KVM" ]; then
      fn_Log "INFO: KVM option used, attempting to save VM: 'virsh save $str_KVM /$str_SelectedDataset/zfs-auto-snapshot.sav'."
      str_KVMsaveVerification=$(virsh save $str_KVM /$str_SelectedDataset/zfs-auto-snapshot.sav 2>&1 |grep "error" |tr '\n' ' ')
      if [ -n "$str_KVMsaveVerification" ]; then
       fn_Log "FATAL: KVM reported an error: $str_KVMsaveVerification."
       exit 1
      fi
     fi
     fn_Log "INFO: Attempting snapshot creation: 'zfs snapshot $str_SelectedDataset@$var_DateTime-$str_SnapshotName'."
     str_CreateSnapshotVerification=$(zfs snapshot "$str_SelectedDataset"@"$var_DateTime"-"$str_SnapshotName" 2>&1)
     if [ -n "$str_SnapshotHold" ]; then
      fn_Log "INFO: Attempting snapshot hold: 'zfs hold $str_SnapshotHold $str_SelectedDataset@$var_DateTime-$str_SnapshotName'."
      str_LockSnapshotVerification=$(zfs hold "$str_SnapshotHold" "$str_SelectedDataset"@"$var_DateTime"-"$str_SnapshotName" 2>&1)
     fi
    fi
    if [ -z "$str_CreateSnapshotVerification" ]; then
     fn_Log "INFO: Snapshot creation successful."
    else
     fn_Log "ERROR: Snapshot creation failed, reason: $str_CreateSnapshotVerification."
    fi
    if [ -n "$str_SnapshotHold" ]; then
     if [ -z "$str_LockSnapshotVerification" ]; then
      fn_Log "INFO: Snapshot hold successful."
     fi
    fi
    if [ -n "$str_KVM" ]; then
     fn_Log "INFO: KVM option used, attempting to restore VM: 'virsh restore /$str_SelectedDataset/zfs-auto-snapshot.sav'."
     str_KVMrestoreVerification=$(virsh restore /$str_SelectedDataset/zfs-auto-snapshot.sav 2>&1 |grep "error" |tr '\n' ' ')
     if [ -n "$str_KVMrestoreVerification" ]; then
      fn_Log "FATAL: KVM reported an error: $str_KVMrestreVerification."
      exit 1
     else
      fn_Log "INFO: KVM restore successful, attempting to remove the save file: '/$str_SelectedDataset/zfs-auto-snapshot.sav'."
      str_KVMrestoreDeleteVerification=$(rm -fI /$str_SelectedDataset/zfs-auto-snapshot.sav 2>&1)
      if [ -e "/$str_SelectedDataset/zfs-auto-snapshot.sav" ]; then
       fn_Log "ERROR: KVM save file deletion failed: $str_KVMrestoreDeleteVerification."
      else
       fn_Log "INFO: KVM operations successful."
      fi
     fi
    fi
   else
    fn_Log "FATAL: Dataset is not valid: $str_SelectedDataset."
    exit 1
   fi
  else
   fn_Log "FATAL: dataset and snapname are required for snapshot creation."
   exit 1
  fi
 else
  fn_Log "INFO: Creation snapshot skipped per user argument."
 fi
}
 
 
 
function fn_Replication {
 if [ -n "$str_ReplicateDestination" ]; then
  echo "$var_UUID - $str_ReplicateDestination" > "$dir_TemporaryDirectory"/"$var_UUID".replication
  str_ReplicateCheckEncryption=$(zfs get encryption "$str_SelectedDataset" -H -o value 2>&1 |grep -v -i off)
  str_FirstSnapshot=$(zfs list -t snapshot "$str_SelectedDataset" 2>&1 |grep -w "$str_SnapshotName" |head -n 1 |awk '{print $1}')
  str_LastSnapshot=$(zfs list -t snapshot "$str_SelectedDataset" 2>&1 |grep -w "$str_SnapshotName" |tail -n 1 |awk '{print $1}')

  str_ReplicationDescriptionBuilder=" "
  str_ReplicationArgumentsBuilder=" "

  if [ "$str_FirstSnapshot" = "$str_LastSnapshot" ]; then
   # First & last snapshots are the same, so this is the first replication
   str_ReplicateSnapshots="$str_FirstSnapshot"
   str_ReplicationDescriptionBuilder="$str_ReplicationDescriptionBuilder initial"
  else
   # First & last snapshots are not the same, so this is an incremental snapshot
   str_ReplicateSnapshots="$str_FirstSnapshot $str_LastSnapshot"
   str_ReplicationDescriptionBuilder="$str_ReplicationDescriptionBuilder incremental"
   str_ReplicationArgumentsBuilder="$str_ReplicationArgumentsBuilder -I"
  fi

  if [ -n "$str_ReplicateCheckEncryption" ]; then
   # Dataset is encrypted, will attempt to send raw
   str_ReplicationDescriptionBuilder="$str_ReplicationDescriptionBuilder encrypted"
   str_ReplicationArgumentsBuilder="$str_ReplicationArgumentsBuilder -w"
  fi



   if [ -n "$str_ReplicateHost" ]; then
    if [ -n "$str_ReplicateCheckEncryption" ]; then
     str_ReplicateTransferSize=$(zfs send -w -nv -R "$str_FirstSnapshot" 2>&1 |grep "total" |awk -F"is" '{print $2}')
     fn_Log "INFO: Attempting encrypted ssh replication: 'zfs send -w -R $str_FirstSnapshot |ssh $str_ReplicateHost zfs receive -F $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
     str_ReplicateTransferVerify=$(zfs send -w -R "$str_FirstSnapshot" 2>&1 |ssh "$str_ReplicateHost" zfs receive -F "$str_ReplicateDestination" 2>&1)
    else
     str_ReplicateTransferSize=$(zfs send -nv -R "$str_FirstSnapshot" 2>&1 |grep "total" |awk -F"is" '{print $2}')
     fn_Log "INFO: Attempting ssh replication: 'zfs send -R $str_FirstSnapshot |ssh $str_ReplicateHost zfs receive -F $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
     str_ReplicateTransferVerify=$(zfs send -R "$str_FirstSnapshot" 2>&1 |ssh "$str_ReplicateHost" zfs receive -F "$str_ReplicateDestination" 2>&1)
    fi
   else
    if [ -n "$str_ReplicateCheckEncryption" ]; then
     str_ReplicateTransferSize=$(zfs send -w -nv -R "$str_FirstSnapshot" 2>&1 |grep "total" |awk -F"is" '{print $2}')
     fn_Log "INFO: Attempting encrypted local replication: 'zfs send -w -R $str_FirstSnapshot |zfs receive -Fu $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
     str_ReplicateTransferVerify=$(zfs send -w -R "$str_FirstSnapshot" 2>&1 |zfs receive -Fu "$str_ReplicateDestination" 2>&1)
    else
     str_ReplicateTransferSize=$(zfs send -nv -R "$str_FirstSnapshot" 2>&1 |grep "total" |awk -F"is" '{print $2}')
     fn_Log "INFO: Attempting local replication: 'zfs send -R $str_FirstSnapshot |zfs receive -Fu $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
     str_ReplicateTransferVerify=$(zfs send -R "$str_FirstSnapshot" 2>&1 |zfs receive -Fu "$str_ReplicateDestination" 2>&1)
    fi
   fi
  else
   if [ -n "$str_ReplicateHost" ]; then
    if [ -n "$str_ReplicateCheckEncryption" ]; then
     str_ReplicateTransferSize=$(zfs send -w -nv -R -I "$str_FirstSnapshot" "$str_LastSnapshot" 2>&1 |grep "total" |awk -F"is" '{print $2}')
     fn_Log "INFO: Attempting encrypted ssh incremental replication: 'zfs send -w -R -I $str_FirstSnapshot $str_LastSnapshot | ssh $str_ReplicateHost zfs receive -F $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
     str_ReplicateTransferVerify=$(zfs send -w -R -I "$str_FirstSnapshot" "$str_LastSnapshot" 2>&1 | ssh "$str_ReplicateHost" zfs receive -F "$str_ReplicateDestination" 2>&1)
    else
     str_ReplicateTransferSize=$(zfs send -nv -R -I "$str_FirstSnapshot" "$str_LastSnapshot" 2>&1 |grep "total" |awk -F"is" '{print $2}')
     fn_Log "INFO: Attempting ssh incremental replication: 'zfs send -R -I $str_FirstSnapshot $str_LastSnapshot | ssh $str_ReplicateHost zfs receive -F $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
     str_ReplicateTransferVerify=$(zfs send -R -I "$str_FirstSnapshot" "$str_LastSnapshot" 2>&1 | ssh "$str_ReplicateHost" zfs receive -F "$str_ReplicateDestination" 2>&1)
    fi
   else
    if [ -n "$str_ReplicateCheckEncryption" ]; then
     str_ReplicateTransferSize=$(zfs send -w -nv -R -I "$str_FirstSnapshot" "$str_LastSnapshot" 2>&1 |grep "total" |awk -F"is" '{print $2}')
     fn_Log "INFO: Attempting encrypted local incremental replication: 'zfs send -w -R -I $str_FirstSnapshot $str_LastSnapshot |zfs receive -Fu $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
     str_ReplicateTransferVerify=$(zfs send -w -R -I "$str_FirstSnapshot" "$str_LastSnapshot" 2>&1 |zfs receive -Fu "$str_ReplicateDestination" 2>&1)
    else
     str_ReplicateTransferSize=$(zfs send -nv -R -I "$str_FirstSnapshot" "$str_LastSnapshot" 2>&1 |grep "total" |awk -F"is" '{print $2}')
     fn_Log "INFO: Attempting local incremental replication: 'zfs send -R -I $str_FirstSnapshot $str_LastSnapshot |zfs receive -Fu $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
     str_ReplicateTransferVerify=$(zfs send -R -I "$str_FirstSnapshot" "$str_LastSnapshot" 2>&1 |zfs receive -Fu "$str_ReplicateDestination" 2>&1)
    fi
   fi
  fi
  if [ -n "$str_ReplicateTransferVerify" ]; then
   rm -I "$dir_TemporaryDirectory"/"$var_UUID".replication 2> /dev/null
   fn_Log "FATAL: Replication failed, reason: $str_ReplicateTransferVerify."
   exit 1
  else
   rm -I "$dir_TemporaryDirectory"/"$var_UUID".replication 2> /dev/null
   fn_Log "INFO: Replication successful."
  fi
 fi
}
 
 
 
function fn_DeleteSnapshots {
 var_SnapshotDeleteCounter="1"
 if [ -n "$var_RetentionPeriod" ]; then
  str_DeleteSnapshotVerifyDataset=$(zfs list $str_SelectedDataset 2>&1 |grep NAME)
  if [ -n "$str_DeleteSnapshotVerifyDataset" ]; then
   if [ -n "$str_RetainGrep" ]; then
    str_SnapshotsPendingDeletion=$(diff <(zfs list -t snapshot "$str_SelectedDataset" 2>&1 |grep "$str_RetainGrep" |tail -n "$var_RetentionPeriod") <(zfs list -t snapshot "$str_SelectedDataset" 2>&1 |grep "$str_RetainGrep") |grep ">" |awk '{print $2}' |paste -sd " " -)
   else
    str_SnapshotsPendingDeletion=$(diff <(zfs list -t snapshot "$str_SelectedDataset" 2>&1 |grep -w "$str_SnapshotName" |tail -n "$var_RetentionPeriod") <(zfs list -t snapshot  "$str_SelectedDataset" 2>&1 |grep -w "$str_SnapshotName") |grep ">" |awk '{print $2}' |paste -sd " " -)
   fi
   var_SnapshotsPendingDeletionCount=$(echo "$str_SnapshotsPendingDeletion" |awk '{print NF}' | sort -nu | tail -n 1)
   fn_Log "INFO: Number of snapshots found to destroy: $var_SnapshotsPendingDeletionCount."
   while [ "$var_SnapshotDeleteCounter" -le "$var_SnapshotsPendingDeletionCount" ]; do
    str_CurrentSnapshotPendingDeletion=$(echo "$str_SnapshotsPendingDeletion" |awk -v c="$var_SnapshotDeleteCounter" '{print $c}')
    fn_Log "INFO: Attempting destroy of snapshot# $var_SnapshotDeleteCounter: $str_CurrentSnapshotPendingDeletion."
    if [ -n "$str_SnapshotHold" ]; then
     if [ -n "$str_RecursiveSnapshot" ]; then
      fn_Log "INFO: Attempting recursive snapshot release: 'zfs release -r $str_SnapshotHold $str_CurrentSnapshotPendingDeletion'."
      str_ReleaseSnapshotVerification=$(zfs release -r "$str_SnapshotHold" "$str_CurrentSnapshotPendingDeletion" 2>&1)
     else
      fn_Log "INFO: Attempting snapshot release: 'zfs release $str_SnapshotHold $str_CurrentSnapshotPendingDeletion'."
      str_ReleaseSnapshotVerification=$(zfs release "$str_SnapshotHold" "$str_CurrentSnapshotPendingDeletion" 2>&1)
     fi
     if [ -z "$str_ReleaseSnapshotVerification" ]; then
      fn_Log "INFO: Snapshot release successful."
     else
      fn_Log "ERROR: Snapshot release may have failed, reason: $str_ReleaseSnapshotVerification."
     fi
    fi
    if [ -n "$str_RecursiveSnapshot" ]; then
     fn_Log "INFO: Attempting recursive snapshot destroy: 'zfs destroy -r $str_CurrentSnapshotPendingDeletion'."
     str_SnapshotDeleteVerification=$(zfs destroy -r "$str_CurrentSnapshotPendingDeletion" 2>&1)
    else
     fn_Log "INFO: Attempting snapshot destroy: 'zfs destroy $str_CurrentSnapshotPendingDeletion'."
     str_SnapshotDeleteVerification=$(zfs destroy "$str_CurrentSnapshotPendingDeletion" 2>&1)
    fi
    if [ -z "$str_SnapshotDeleteVerification" ]; then
     fn_Log "INFO: Snapshot destroy successful."
    else
     fn_Log "ERROR: Snapshot destroy failed, reason: $str_SnapshotDeleteVerification."
    fi
    let var_SnapshotDeleteCounter+=1
   done
  else
   fn_Log "FATAL: Dataset is not valid: $str_SelectedDataset."
   exit 1
  fi
 fi
}


 
function fn_RecursiveRollback {
 var_SnapshotRollbackCounter="1"
 if [ -n "$str_SelectedDataset" ] && [ -n "$str_SnapshotName" ]; then
  str_RecursiveRollbackVerifyDataset=$(zfs list $str_SelectedDataset 2>&1 |grep NAME)
  if [ -n "$str_RecursiveRollbackVerifyDataset" ]; then
   str_SnapshotsPendingRollback=$(zfs list -t snapshot -r "$str_SelectedDataset" 2>&1 |grep -w "$str_SnapshotName" |awk '{print $1}' |paste -sd " " -)
   var_SnapshotsPendingRollbackVerification=$(zfs list -t snapshot -r "$str_SelectedDataset" 2>&1 |grep -w "$str_SnapshotName" |awk '{print $1}' |awk '{print $1}' |awk -F "@" '{print $2}' |sort |uniq |wc -l)
   if [ "$var_SnapshotsPendingRollbackVerification" -gt "1" ]; then
    fn_Log "FATAL: Found more than one snapshot for recursive rollback, check -snapname=."
    exit 1
   fi
   var_SnapshotsPendingRollbackCount=$(echo "$str_SnapshotsPendingRollback" |awk '{print NF}' | sort -nu | tail -n 1)
   fn_Log "INFO: Number of snapshots found to rollback: $var_SnapshotsPendingRollbackCount."
   while [ "$var_SnapshotRollbackCounter" -le "$var_SnapshotsPendingRollbackCount" ]; do
    str_CurrentSnapshotPendingRollback=$(echo "$str_SnapshotsPendingRollback" |awk -v c="$var_SnapshotRollbackCounter" '{print $c}')
    fn_Log "INFO: Attempting semi-forced snapshot rollback: 'zfs rollback -r $str_CurrentSnapshotPendingRollback'."
    str_SnapshotRollbackVerification=$(zfs rollback -r "$str_CurrentSnapshotPendingRollback" 2>&1)
    if [ -z "$str_SnapshotRollbackVerification" ]; then
     fn_Log "INFO: Snapshot rollback successful."
    else
     fn_Log "FATAL: Snapshot rollback failed, reason: $str_SnapshotRollbackVerification."
     exit 1
    fi
    let var_SnapshotRollbackCounter+=1
   done
  else
   fn_Log "FATAL: Dataset is not valid: $str_SelectedDataset."
   exit 1
  fi
 else
  fn_Log "FATAL: -dataset= and -snapname= are required for recursive rollback."
  exit 1
 fi
}

if [ -n "$str_RecursiveRollback" ]; then
 fn_RecursiveRollback
else
 fn_CheckReplicationDuplicate
 fn_ValidateHost
 fn_CreateSnapshot
 fn_Replication
 fn_DeleteSnapshots
fi

