# zfs-snapshot

## Why
I created this script to manage snapshot creation for ZFS on Linux. It has proven reliable over years, however it has not been battle tested under every possible scenario. Yes I know there are others out there but I prefer mine.

## Examples
You must provide an argument to run this script. Here is an example for automatic snapshots:
```
./zfs-auto-snapshot.sh -dataset=pool/dataset -snapname=Daily -retain=3 -grep=:05: -logging=1
```
 
Here is an example for local replication:
```
./zfs-auto-snapshot.sh -dataset=pool/dataset -replicatedest=pool2/dataset -snapname=Mirror -retain=1 -hold=replication -logging=1
```

Here is an example for remote replication:
```
./zfs-auto-snapshot.sh -dataset=pool -replicatehost=server -replicatedest=pool2 -snapname=Mirror -retain=1 -hold=replication -recursive -logging=1
```
 
## Arguments
| Argument | Optional | Description |
| -------- | -------- | ----------- |
| -dataset= | Required | Specifies the ZFS dataset to snapshot. |
| -snapname= | Required | Name to be appended to snapshot. |
| -retain= | Optional | Amount of snapshots to keep. No snapshots will be destroyed if this is not specified. |
| -grep= | Optional | This string will be grepped for retention instead of the snapshot name. |
| -replicatedest= | Optional | Specify the destination pool/dataset for replication. |
| -replicatehost= | Optional | For remote replication - will be used for SSH. Use of a .ssh/config file is recommended. |
| -validatehost= |  Optional | Use Netcat to check SSH before anything happens. Expects host:port. |
| -hold= | Optional | Lock snapshot with this hold string. Snapshot creation and destroy will use this string. |
| -skip-create | Optional | Skips snapshot creation. |
| -recursive | Optional | Snapshot create, hold, and destroy are used with the '-r' argument. |
| -kvm= | Optional | Specify the domain name and this will try to save a running VM (inside dataset previously specified) as root before performing the snapshot. |
| -rollback Optional | Attempt recursive rollback, used to fix broken destination if a recursive send failed mid-transfer. |
| -logging= | Optional | 0: No logs, no screen output. 1: No logs, output to screen. 2: Output sent to logger, no screen output. |
 
Defaults: snapshot name is used for retention, logging is set to '1'. Replication and retention are optional, but snapshot creation is default.
