#!/bin/bash
#HOT STANDBY FOR NEXUS

#CONFIG
NEXUS_CREDS=admin:****
NEXUS_PORT=8081
LNK_DIR=_data
CUR_DIR=_data_cur
BACKUP_DIR=_data_backup
USER=root
RSYNC_SPEED_LIMIT=30000 #KBytes per second
NEXUS_CONTAINER_NAME=cadvisor

#ACTIVE HOST
ACTIVE_HOSTNAME=h-w7uqf822.rg-fcsice01.uu-os8-core.eu-c-1.cloud.plus4u.net
ACTIVE_DATA=/var/lib/docker/volumes/docker_nexus-data
ACTIVE_BLOBS=/var/lib/docker/volumes/docker_nexus-blobs

#STANDBY HOST
STANDBY_HOSTNAME=h-ln2mdfac.rg-fcsice01.uu-os8-core.eu-c-1.cloud.plus4u.net
STANDBY_DATA=/var/lib/docker/volumes/docker_nexus-data
STANDBY_BLOBS=/var/lib/docker/volumes/docker_nexus-blobs


#INIT SUBVOLUMES ON STANDBY HOST (FIRST RUN)
if [ ! -d $STANDBY_DATA ] ; then
  echo "Creating new subvolume for Nexus data"
  mkdir -p $STANDBY_DATA
  btrfs subvolume create "$STANDBY_DATA"/"$BACKUP_DIR"
  btrfs subvolume create "$STANDBY_DATA"/"$CUR_DIR"
  ln -s "$STANDBY_DATA"/"$CUR_DIR" "$STANDBY_DATA"/"$LNK_DIR"
fi
if [ ! -d $STANDBY_BLOBS ] ; then
  echo "Creating new subvolume for Nexus repo blobs"
  mkdir -p $STANDBY_BLOBS
  btrfs subvolume create "$STANDBY_BLOBS"/"$BACKUP_DIR"
  btrfs subvolume create "$STANDBY_BLOBS"/"$CUR_DIR"
  ln -s "$STANDBY_BLOBS"/"$CUR_DIR" "$STANDBY_BLOBS"/"$LNK_DIR"
fi

#SET ACTIVE NEXUS TO READ-ONLY
echo "Setting active Nexus to read-only"
curl -s -u "$NEXUS_CREDS" -X POST http://"$ACTIVE_HOSTNAME":"$NEXUS_PORT"/service/rest/beta/read-only/freeze
RCODE_STATE=$?

#CHECK ACTIVE NEXUS HEALTH
RCODE_HEALTH=$(curl -s -u "$NEXUS_CREDS" -X GET http://"$ACTIVE_HOSTNAME":"$NEXUS_PORT"/service/metrics/healthcheck | grep true | wc -l)

#IF ACTIVE NEXUS HEALTHY
if [ "$RCODE_STATE" == "0" ] && [ "$RCODE_HEALTH" == "1" ]; then
  echo "Sleeping 10 sec"
  sleep 10
  #DELETE OLD BACKUP OF NEXUS DATA ON ACTIVE NODE
  echo "Deleting old backup of Nexus data on active node"
  ssh $ACTIVE_HOSTNAME btrfs subvolume delete "$ACTIVE_DATA"/"$BACKUP_DIR"
  #DELETE OLD BACKUP OF NEXUS REPO BLOBS ON ACTIVE NODE
  echo "Deleting old backup of Nexus repo blobs on active node"
  ssh $ACTIVE_HOSTNAME btrfs subvolume delete "$ACTIVE_BLOBS"/"$BACKUP_DIR"
  #CREATE BACKUP OF Nexus data ON ACTIVE NODE
  echo "Creating new backup of Nexus data on active node"
  ssh $ACTIVE_HOSTNAME btrfs subvolume snapshot "$ACTIVE_DATA"/"$CUR_DIR" "$ACTIVE_DATA"/"$BACKUP_DIR"
  #CREATE BACKUP OF NEXUS REPO BLOBS ON ACTIVE NODE
  echo "Creating new backup of nexus repo blobs on active node"
  ssh $ACTIVE_HOSTNAME btrfs subvolume snapshot "$ACTIVE_BLOBS"/"$CUR_DIR" "$ACTIVE_BLOBS"/"$BACKUP_DIR"
  #SET ACTIVE NEXUS TO WRITE
  echo "Setting active Nexus to write"
  curl -u "$NEXUS_CREDS" -X POST http://"$ACTIVE_HOSTNAME":"$NEXUS_PORT"/service/rest/beta/read-only/release
  #SYNC NEXUS DATA FROM ACTIVE TO STANDBY
  echo "Syncing Nexus data from active to standby node"
  rsync --bwlimit="$RSYNC_SPEED_LIMIT" -a "$USER"@"$ACTIVE_HOSTNAME":"$ACTIVE_DATA"/"$BACKUP_DIR"/ "$STANDBY_DATA"/"$BACKUP_DIR"
  RCODE_DATA=$?
  #SYNC NEXUS REPO BLOBS FROM ACTIVE TO STANDBY
  echo "Syncing Nexus repo blobs from active to standby node"
  rsync --bwlimit="$RSYNC_SPEED_LIMIT" -a "$USER"@"$ACTIVE_HOSTNAME":"$ACTIVE_BLOBS"/"$BACKUP_DIR"/ "$STANDBY_BLOBS"/"$BACKUP_DIR"
  RCODE_BLOBS=$?
  #IF SYNC STATUS OK SWITCH BACKUP TO CURRENT
  if [ "$RCODE_DATA" == "0" ] && [ "$RCODE_BLOBS" == "0" ]; then
    #STOP STANDBY CONTAINER
    echo "Stopping standby Nexus container"
    docker stop $NEXUS_CONTAINER_NAME
    #REMOVE CURRENT NEXUS DATA
    echo "Removing current Nexus data on standby node"
    btrfs subvolume delete "$STANDBY_DATA"/"$CUR_DIR"
    #REMOVE CURRENT NEXUS REPO BLOBS
    echo "Removing current Nexus repo blobs on standby node"
    btrfs subvolume delete "$STANDBY_BLOBS"/"$CUR_DIR"
    #CREATE NEW CURRENT FROM BACKUP NEXUS DATA
    echo "Creating new current Nexus data from backup on standby node"
    btrfs subvolume snapshot "$STANDBY_DATA"/"$BACKUP_DIR" "$STANDBY_DATA"/"$CUR_DIR"
    #CREATE NEW CURRENT FROM BACKUP NEXUS REPO BLOBS
    echo "Creating new current Nexus repo blobs from backup on standby node"
    btrfs subvolume snapshot "$STANDBY_BLOBS"/"$BACKUP_DIR" "$STANDBY_BLOBS"/"$CUR_DIR"
    #START STANDBY NEXUS CONTAINER
    echo "Starting standby Nexus container"
    docker start $NEXUS_CONTAINER_NAME
    echo "Sleeping 60 sec"
    sleep 60
    #SET STANDBY NEXUS TO WRITE
    echo "Setting standby Nexus to write"
    curl -s -u "$NEXUS_CREDS" -X POST http://"$STANDBY_HOSTNAME":"$NEXUS_PORT"/service/rest/beta/read-only/release
  else
    echo "Error syncing Nexus"
  fi
else
  echo "active Nexus node not running or it is in unknown state"
fi