#!/bin/bash
#CONFIG
NEXUS_CREDS=admin:****
NEXUS_PORT=8081
LNK_DIR=_data
CUR_DIR=_data_cur
BACKUP_DIR=_data_backup
SNAP_DIR=_data_snap
USER=root
RSYNC_SPEED_LIMIT=30000 #KBytes per second
NEXUS_CONTAINER_NAME=nexus

#ACTIVE HOST
ACTIVE_HOSTNAME=
ACTIVE_DATA=/var/lib/docker/volumes/docker_nexus-data
ACTIVE_BLOBS=/var/lib/docker/volumes/docker_nexus-blobs

#STANDBYINATION HOST
STANDBY_HOSTNAME=
STANDBY_DATA=/var/lib/docker/volumes/docker_nexus-data
STANDBY_BLOBS=/var/lib/docker/volumes/docker_nexus-blobs


#INIT FOR FIRTS RUN
#btrfs subvolume create "$ACTIVE_DATA"/"$CUR_DIR"
#btrfs subvolume create "$ACTIVE_BLOBS"/"$CUR_DIR"
#ln -s "$ACTIVE_DATA"/"$CUR_DIR" "$ACTIVE_DATA"/"$LNK_DIR"
#ln -s "$ACTIVE_BLOBS"/"$CUR_DIR" "$ACTIVE_BLOBS"/"$LNK_DIR"
#btrfs sub snap -r "$ACTIVE_DATA"/"$CUR_DIR" "$ACTIVE_DATA"/"$BACKUP_DIR"
#btrfs sub snap -r "$ACTIVE_BLOBS"/"$CUR_DIR" "$ACTIVE_BLOBS"/"$BACKUP_DIR"
#btrfs send "$ACTIVE_BLOBS"/"$BACKUP_DIR" | ssh root@"$STANDBY_HOSTNAME" "btrfs receive "$STANDBY_BLOBS""
#btrfs send "$ACTIVE_DATA"/"$BACKUP_DIR" | ssh root@"$STANDBY_HOSTNAME" "btrfs receive "$STANDBY_DATA""
#ssh root@"$STANDBY_HOSTNAME" btrfs subvolume create "$STANDBY_DATA"/"$CUR_DIR"
#ssh root@"$STANDBY_HOSTNAME" btrfs subvolume create "$STANDBY_BLOBS"/"$CUR_DIR"
#ssh root@"$STANDBY_HOSTNAME" ln -s "$STANDBY_DATA"/"$CUR_DIR" "$STANDBY_DATA"/"$LNK_DIR"
#ssh root@"$STANDBY_HOSTNAME" ln -s "$STANDBY_BLOBS"/"$CUR_DIR" "$STANDBY_BLOBS"/"$LNK_DIR"


#INCREMENTAL SNAPSHOT SYNC - USING BTRFS SEND | RECEIVE OVER SSH
curl -s -u "$NEXUS_CREDS" -X POST http://"$ACTIVE_HOSTNAME":"$NEXUS_PORT"/service/rest/beta/read-only/freeze
btrfs sub snap -r "$ACTIVE_DATA"/"$CUR_DIR" "$ACTIVE_DATA"/"$SNAP_DIR"
btrfs sub snap -r "$ACTIVE_BLOBS"/"$CUR_DIR" "$ACTIVE_BLOBS"/"$SNAP_DIR"
curl -u "$NEXUS_CREDS" -X POST http://"$ACTIVE_HOSTNAME":"$NEXUS_PORT"/service/rest/beta/read-only/release
btrfs send -p "$ACTIVE_DATA"/"$BACKUP_DIR" "$ACTIVE_DATA"/"$SNAP_DIR" | ssh "$USER"@"$STANDBY_HOSTNAME" "btrfs receive "$STANDBY_DATA""
btrfs send -p "$ACTIVE_BLOBS"/"$BACKUP_DIR" "$ACTIVE_BLOBS"/"$SNAP_DIR" | ssh "$USER"@"$STANDBY_HOSTNAME" "btrfs receive "$STANDBY_BLOBS""
btrfs sub del "$ACTIVE_DATA"/"$BACKUP_DIR"
btrfs sub del "$ACTIVE_BLOBS"/"$BACKUP_DIR"
mv "$ACTIVE_DATA"/"$SNAP_DIR" "$ACTIVE_DATA"/"$BACKUP_DIR"
mv "$ACTIVE_BLOBS"/"$SNAP_DIR" "$ACTIVE_BLOBS"/"$BACKUP_DIR"
ssh "$USER"@"$STANDBY_HOSTNAME" btrfs sub del "$STANDBY_DATA"/"$BACKUP_DIR"
ssh "$USER"@"$STANDBY_HOSTNAME" btrfs sub del "$STANDBY_BLOBS"/"$BACKUP_DIR"
ssh "$USER"@"$STANDBY_HOSTNAME" mv "$STANDBY_DATA"/"$SNAP_DIR" "$STANDBY_DATA"/"$BACKUP_DIR"
ssh "$USER"@"$STANDBY_HOSTNAME" mv "$STANDBY_BLOBS"/"$SNAP_DIR" "$STANDBY_BLOBS"/"$BACKUP_DIR"
ssh "$USER"@"$STANDBY_HOSTNAME" docker stop $NEXUS_CONTAINER_NAME
ssh "$USER"@"$STANDBY_HOSTNAME" btrfs sub del "$STANDBY_DATA"/"$CUR_DIR"
ssh "$USER"@"$STANDBY_HOSTNAME" btrfs sub del "$STANDBY_BLOBS"/"$CUR_DIR"
ssh "$USER"@"$STANDBY_HOSTNAME" btrfs sub snap "$STANDBY_DATA"/"$BACKUP_DIR" "$STANDBY_DATA"/"$CUR_DIR"
ssh "$USER"@"$STANDBY_HOSTNAME" btrfs sub snap "$STANDBY_BLOBS"/"$BACKUP_DIR" "$STANDBY_BLOBS"/"$CUR_DIR"
ssh "$USER"@"$STANDBY_HOSTNAME" docker start $NEXUS_CONTAINER_NAME
curl -s -u "$NEXUS_CREDS" -X POST http://"$STANDBY_HOSTNAME":"$NEXUS_PORT"/service/rest/beta/read-only/release
