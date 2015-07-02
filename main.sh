#!/bin/bash

BASEDIR=$(dirname "$0")

INPUT_OUTPUT_PATH="$HOME/owncloud"
INPUT_COPY_PATH="$HOME/owncloudsync"
PASSFILE_PATH="$HOME/owncloud/_geosync/src/.pass"
APP_DIR="_geosync"
DATA_PATH="${INPUT_OUTPUT_PATH}/${APP_DIR}/data" #contient le fichier lastdate.txt avec la dernière date de changement de fichier traité
LOG_PATH="$DATA_PATH/publish.log"
ERROR_LOG_PATH="$DATA_PATH/error.log"


#synchronise les fichiers du montage webdav pour être plus performant
#rsync -avr --delete --exclude '_geosync' --exclude 'lost+found' '/home/georchestra-ouvert/owncloud/' '/home/georchestra-ouvert/owncloudsync/'
cmd="rsync -avr --delete --exclude '$APP_DIR' --exclude 'lost+found' '$INPUT_OUTPUT_PATH/' '$INPUT_COPY_PATH/'"
echo $cmd
eval $cmd

mkdir -p "$DATA_PATH"
date >> "$LOG_PATH"

cmd="bash '$BASEDIR/publish.sh' -i '$INPUT_COPY_PATH' -w geosync -d shpowncloud -g '$DATA_PATH' -p '$PASSFILE_PATH' 1>>'$LOG_PATH' 2>>'$ERROR_LOG_PATH'"
echo $cmd
eval $cmd