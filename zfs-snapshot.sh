#!/bin/bash
#zfs-snapshot.sh
#spmfox@foxwd.com
 
opt_Logging="1"
var_UUID=$(date +%N)
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
 echo "-hold=:............Optional, lock snapshot with this hold string. Snapshot creation and destroy will use this string."
 echo "-skip-create:......Optional, skips snapshot creation."
 echo "-recursive:........Optional, snapshot create, hold, and destroy are used with the '-r' argument."
 echo "-kvm=:.............Optional, using this will try to save a VM running as root before performing the snapshot. Domain name must be specified here."
 echo "-logging=:.........Optional, 0: No logs, no screen output. 1: No logs, output to screen. 2: Output sent to logger, no screen output."
 echo " "
 echo "Defaults: snapshot name is used for retention, logging is set to '1'. Replication and retention are optional, but snapshot creation is default."
 echo " "
 exit
fi
 
 
 
function fn_Output {
 if [ -n "$str_OutputText" ]; then
  if [ "$opt_Logging" -eq 0 ]; then
   return
  fi
  if [ "$opt_Logging" -eq 1 ]; then
   echo "zfs-snapshot: ($var_UUID) $str_OutputText"
  fi
  if [ "$opt_Logging" -eq 2 ]; then
   logger "zfs-snapshot: ($var_UUID) $str_OutputText"
  fi
  if [ "$opt_Logging" -ne 0 ] && [ "$opt_Logging" -ne 1 ] && [ "$opt_Logging" -ne 2 ]; then
   echo "zfs-snapshot: ERROR: Invalid logging argument."
  fi
 fi
 str_OutputText=""
}
 
 
 
function fn_ControlC {
 str_OutputText="FATAL: CTRL-C or other kill method detected, please check logs on how to clean up state."
 fn_Output
 rm -I "$dir_TemporaryDirectory"/"$var_UUID".replication 2> /dev/null
 exit
}
 
 
 
trap fn_ControlC SIGINT
 
 
 
function fn_CheckPermissions {
 strPermissionValidation=$(zfs list |grep "Permission")
  if [ -n "$strPermissionValidation" ]; then
   str_OutputText="FATAL: No permissions for zfs commands."
   fn_Output
   exit
  fi
}
 
 
 
function fn_CheckReplicationDuplicate {
 if [ -n "$str_ReplicateDestination" ]; then
  str_CheckOngoingMirror=$(cat $dir_TemporaryDirectory/*.replication 2> /dev/null |grep -w "$str_ReplicateDestination")
 fi
 if [ -n "$str_CheckOngoingMirror" ]; then
  str_OutputText="FATAL: Another replication job is running for this destination: ($str_CheckOngoingMirror)."
  fn_Output
  exit
 fi
}
 
 
 
function fn_CheckReplicationConnection {
 if [ -n "$str_ReplicateHost" ]; then
  if ssh -q -o "BatchMode=yes" -o "ConnectTimeout=5" "$str_ReplicateHost" "echo 2>&1"; then
   str_OutputText="INFO: SSH connection to $str_ReplicateHost has been verified."
   fn_Output
  else
   str_OutputText="FATAL: SSH connection to $str_ReplicateHost has FAILED. Script will exit without making any changes."
   fn_Output
   exit
  fi
 fi
}
 
 
 
function fn_CreateSnapshot {
 var_DateTime=$(date +%Y-%m-%d_%T)
 if [ -z "$str_SkipSnapshotCreation" ]; then
  if [ -n "$str_SelectedDataset" ] && [ -n "$str_SnapshotName" ]; then
   str_CreateSnapshotVerifyDataset=$(zfs list |grep "$str_SelectedDataset")
   if [ -n "$str_CreateSnapshotVerifyDataset" ]; then
    if [ -n "$str_RecursiveSnapshot" ]; then
     str_OutputText="INFO: Attempting recursive snapshot creation: 'zfs snapshot -r $str_SelectedDataset@$var_DateTime-$str_SnapshotName'."
     fn_Output
     str_CreateSnapshotVerification=$(zfs snapshot -r "$str_SelectedDataset"@"$var_DateTime"-"$str_SnapshotName" 2>&1)
     if [ -n "$str_SnapshotHold" ]; then
      str_OutputText="INFO: Attempting recursive snapshot hold: 'zfs hold -r $str_SnapshotHold $str_SelectedDataset@$var_DateTime-$str_SnapshotName'."
      fn_Output
      str_LockSnapshotVerification=$(zfs hold -r "$str_SnapshotHold" "$str_SelectedDataset"@"$var_DateTime"-"$str_SnapshotName" 2>&1)
     fi
    else
     if [ -n "$str_KVM" ]; then
      str_OutputText="INFO: KVM option used, attempting to save VM: 'virsh save $str_KVM /$str_SelectedDataset/zfs-auto-snapshot.sav'."
      fn_Output
      str_KVMsaveVerification=$(virsh save $str_KVM /$str_SelectedDataset/zfs-auto-snapshot.sav 2>&1 |grep "error" |tr '\n' ' ')
      if [ -n "$str_KVMsaveVerification" ]; then
       str_OutputText="FATAL: KVM reported an error: $str_KVMsaveVerification."
       fn_Output
       exit
      fi
     fi
     str_OutputText="INFO: Attempting snapshot creation: 'zfs snapshot $str_SelectedDataset@$var_DateTime-$str_SnapshotName'."
     fn_Output
     str_CreateSnapshotVerification=$(zfs snapshot "$str_SelectedDataset"@"$var_DateTime"-"$str_SnapshotName" 2>&1)
     if [ -n "$str_SnapshotHold" ]; then
      str_OutputText="INFO: Attempting snapshot hold: 'zfs hold $str_SnapshotHold $str_SelectedDataset@$var_DateTime-$str_SnapshotName'."
      fn_Output
      str_LockSnapshotVerification=$(zfs hold "$str_SnapshotHold" "$str_SelectedDataset"@"$var_DateTime"-"$str_SnapshotName" 2>&1)
     fi
    fi
    if [ -z "$str_CreateSnapshotVerification" ]; then
     str_OutputText="INFO: Snapshot creation successful."
     fn_Output
    else
     str_OutputText="ERROR: Snapshot creation failed, reason: $str_CreateSnapshotVerification."
     fn_Output
    fi
    if [ -n "$str_SnapshotHold" ]; then
     if [ -z "$str_LockSnapshotVerification" ]; then
      str_OutputText="INFO: Snapshot hold successful."
      fn_Output
     fi
    fi
    if [ -n "$str_KVM" ]; then
     str_OutputText="INFO: KVM option used, attempting to restore VM: 'virsh restore /$str_SelectedDataset/zfs-auto-snapshot.sav'."
     fn_Output
     str_KVMrestoreVerification=$(virsh restore /$str_SelectedDataset/zfs-auto-snapshot.sav 2>&1 |grep "error" |tr '\n' ' ')
     if [ -n "$str_KVMrestoreVerification" ]; then
      str_OutputText="FATAL: KVM reported an error: $str_KVMrestreVerification."
      fn_Output
      exit
     else
      str_OutputText="INFO: KVM restore successful, attempting to remove the save file: '/$str_SelectedDataset/zfs-auto-snapshot.sav'."
      fn_Output
      str_KVMrestoreDeleteVerification=$(rm -fI /$str_SelectedDataset/zfs-auto-snapshot.sav 2>&1)
      if [ -e "/$str_SelectedDataset/zfs-auto-snapshot.sav" ]; then
       str_OutputText="ERROR: KVM save file deletion failed: $str_KVMrestoreDeleteVerification."
       fn_Output
      else
       str_OutputText="INFO: KVM operations successful."
       fn_Output
      fi
     fi
    fi
   else
    str_OutputText="FATAL: Dataset is not valid: $str_SelectedDataset."
    fn_Output
    exit
   fi
  else
   str_OutputText="FATAL: dataset and snapname are required for snapshot creation."
   fn_Output
   exit
  fi
 else
  str_OutputText="INFO: Creation snapshot skipped per user argument."
  fn_Output
 fi
}
 
 
 
function fn_Replication {
 if [ -n "$str_ReplicateDestination" ]; then
  echo "$var_UUID - $str_ReplicateDestination" > "$dir_TemporaryDirectory"/"$var_UUID".replication
  str_FirstSnapshot=$(zfs list -t all |grep "$str_SelectedDataset"@ |grep -w "$str_SnapshotName" |head -n 1 |awk '{print $1}')
  str_LastSnapshot=$(zfs list -t all |grep "$str_SelectedDataset"@ |grep -w "$str_SnapshotName" |tail -n 1 |awk '{print $1}')
  if [ "$str_FirstSnapshot" = "$str_SelectedDataset"@"$var_DateTime"-"$str_SnapshotName" ]; then
   if [ -n "$str_ReplicateHost" ]; then
    str_ReplicateTransferSize=$(zfs send -nv -R "$str_FirstSnapshot" |grep "total" |awk -F"is" '{print $2}')
    str_OutputText="INFO: Attempting ssh replication: 'zfs send -R $str_FirstSnapshot |ssh $str_ReplicateHost sudo zfs receive -F $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
    fn_Output
    str_ReplicateTransferVerify=$(zfs send -R "$str_FirstSnapshot" |ssh "$str_ReplicateHost" sudo zfs receive -F "$str_ReplicateDestination" 2>&1)
   else
    str_ReplicateTransferSize=$(zfs send -nv -R "$str_FirstSnapshot" |grep "total" |awk -F"is" '{print $2}')
    str_OutputText="INFO: Attempting local replication: 'zfs send -R $str_FirstSnapshot |zfs receive -Fu $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
    fn_Output
    str_ReplicateTransferVerify=$(zfs send -R "$str_FirstSnapshot" |zfs receive -Fu "$str_ReplicateDestination" 2>&1)
   fi
  else
   if [ -n "$str_ReplicateHost" ]; then
    str_ReplicateTransferSize=$(zfs send -nv -R -I "$str_FirstSnapshot" "$str_LastSnapshot" |grep "total" |awk -F"is" '{print $2}')
    str_OutputText="INFO: Attempting ssh incremental replication: 'zfs send -R -I $str_FirstSnapshot $str_LastSnapshot | ssh $str_ReplicateHost sudo zfs receive -F $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
    fn_Output
    str_ReplicateTransferVerify=$(zfs send -R -I "$str_FirstSnapshot" "$str_LastSnapshot" | ssh "$str_ReplicateHost" sudo zfs receive -F "$str_ReplicateDestination" 2>&1)
   else
    str_ReplicateTransferSize=$(zfs send -nv -R -I "$str_FirstSnapshot" "$str_LastSnapshot" |grep "total" |awk -F"is" '{print $2}')
    str_OutputText="INFO: Attempting local incremental replication: 'zfs send -R -I $str_FirstSnapshot $str_LastSnapshot |zfs receive -Fu $str_ReplicateDestination', estimated total size:$str_ReplicateTransferSize."
    fn_Output
    str_ReplicateTransferVerify=$(zfs send -R -I "$str_FirstSnapshot" "$str_LastSnapshot" |zfs receive -Fu "$str_ReplicateDestination" 2>&1)
   fi
  fi
  if [ -n "$str_ReplicateTransferVerify" ]; then
   rm -I "$dir_TemporaryDirectory"/"$var_UUID".replication 2> /dev/null
   str_OutputText="FATAL: Replication failed, reason: $str_ReplicateTransferVerify."
   fn_Output
   exit
  else
   rm -I "$dir_TemporaryDirectory"/"$var_UUID".replication 2> /dev/null
   str_OutputText="INFO: Replication successful."
   fn_Output
  fi
 fi
}
 
 
 
function fn_DeleteSnapshots {
 var_SnapshotDeleteCounter="1"
 if [ -n "$var_RetentionPeriod" ]; then
  str_DeleteSnapshotVerifyDataset=$(zfs list |grep "$str_SelectedDataset")
  if [ -n "$str_DeleteSnapshotVerifyDataset" ]; then
   if [ -n "$str_RetainGrep" ]; then
    str_SnapshotsPendingDeletion=$(diff <(zfs list -t all |grep "$str_SelectedDataset"@ |grep "$str_RetainGrep" |tail -n "$var_RetentionPeriod") <(zfs list -t all |grep "$str_SelectedDataset"@ |grep "$str_RetainGrep") |grep ">" |awk '{print $2}' |paste -sd " " -)
   else
    str_SnapshotsPendingDeletion=$(diff <(zfs list -t all |grep "$str_SelectedDataset"@ |grep -w "$str_SnapshotName" |tail -n "$var_RetentionPeriod") <(zfs list -t all |grep "$str_SelectedDataset"@ |grep -w "$str_SnapshotName") |grep ">" |awk '{print $2}' |paste -sd " " -)
   fi
   var_SnapshotsPendingDeletionCount=$(echo "$str_SnapshotsPendingDeletion" |awk '{print NF}' | sort -nu | tail -n 1)
   str_OutputText="INFO: Number of snapshots found to destroy: $var_SnapshotsPendingDeletionCount."
   fn_Output
   while [ "$var_SnapshotDeleteCounter" -le "$var_SnapshotsPendingDeletionCount" ]; do
    str_CurrentSnapshotPendingDeletion=$(echo "$str_SnapshotsPendingDeletion" |awk -v c="$var_SnapshotDeleteCounter" '{print $c}')
    str_OutputText="INFO: Attempting destroy of snapshot# $var_SnapshotDeleteCounter: $str_CurrentSnapshotPendingDeletion."
    fn_Output
    if [ -n "$str_SnapshotHold" ]; then
     if [ -n "$str_RecursiveSnapshot" ]; then
      str_OutputText="INFO: Attempting recursive snapshot release: 'zfs release -r $str_SnapshotHold $str_CurrentSnapshotPendingDeletion'."
      fn_Output
      str_ReleaseSnapshotVerification=$(zfs release -r "$str_SnapshotHold" "$str_CurrentSnapshotPendingDeletion" 2>&1)
     else
      str_OutputText="INFO: Attempting snapshot release: 'zfs release $str_SnapshotHold $str_CurrentSnapshotPendingDeletion'."
      fn_Output
      str_ReleaseSnapshotVerification=$(zfs release "$str_SnapshotHold" "$str_CurrentSnapshotPendingDeletion" 2>&1)
     fi
     if [ -z "$str_ReleaseSnapshotVerification" ]; then
      str_OutputText="INFO: Snapshot release successful."
      fn_Output
     else
      str_OutputText="ERROR: Snapshot release may have failed, reason: $str_ReleaseSnapshotVerification."
      fn_Output
     fi
    fi
    if [ -n "$str_RecursiveSnapshot" ]; then
     str_OutputText="INFO: Attempting recursive snapshot destroy: 'zfs destroy -r $str_CurrentSnapshotPendingDeletion'."
     fn_Output
     str_SnapshotDeleteVerification=$(zfs destroy -r "$str_CurrentSnapshotPendingDeletion" 2>&1)
    else
     str_OutputText="INFO: Attempting snapshot destroy: 'zfs destroy $str_CurrentSnapshotPendingDeletion'."
     fn_Output
     str_SnapshotDeleteVerification=$(zfs destroy "$str_CurrentSnapshotPendingDeletion" 2>&1)
    fi
    if [ -z "$str_SnapshotDeleteVerification" ]; then
     str_OutputText="INFO: Snapshot destroy successful."
     fn_Output
    else
     str_OutputText="ERROR: Snapshot destroy failed, reason: $str_SnapshotDeleteVerification."
     fn_Output
    fi
    let var_SnapshotDeleteCounter+=1
   done
  else
   str_OutputText="FATAL: Dataset is not valid: $str_SelectedDataset."
   fn_Output
   exit
  fi
 fi
}
 
 
 
fn_CheckPermissions
fn_CheckReplicationDuplicate
fn_CheckReplicationConnection
fn_CreateSnapshot
fn_Replication
fn_DeleteSnapshots

