#!/bin/bash

# usage : "bash /chemin/complet/main.sh"  et non "bash main.sh"
# sinon ${BASH_SOURCE[0]} utilisé par certaines librairies renverra "." au lieu du répertoire attendu 

BASEDIR=$(dirname "$0")

INPUT_OUTPUT_PATH="$HOME/owncloud"
INPUT_COPY_PATH="$HOME/owncloudsync"

# login + passwd + URL du serveur georchestra
PASSFILE="$HOME/bin/.geosync.conf"

# contient le fichier lastdate.txt avec la dernière date de changement de fichier traité
DATA_PATH="$HOME/data" 

# répertoire provisoire des sources
APP_DIR="_geosync"

# log dans un répertoire dédié
# ls -ld /var/log/geosync
# drwxrwxr-x 2 georchestra       georchestra     4096 juil.  3 15:05 geosync
LOG_PATH="/var/log/geosync"
PUBLI_LOG="$LOG_PATH/publish.log"
ERROR_LOG="$LOG_PATH/error.log"

#synchronise les fichiers du montage webdav pour être plus performant
#rsync -avr --delete --exclude '_geosync' --exclude 'lost+found' '/home/georchestra-ouvert/owncloud/' '/home/georchestra-ouvert/owncloudsync/'
cmd="rsync -avr --delete --exclude '$APP_DIR' --exclude 'lost+found' '$INPUT_OUTPUT_PATH/' '$INPUT_COPY_PATH/'"
echo $cmd
eval $cmd

if [ ! -d $LOG_PATH ]
    then mkdir -p "$LOG_PATH"
fi
date >> "$PUBLI_LOG"
date >> "$ERROR_LOG"

cmd="bash '$BASEDIR/publish.sh' -i '$INPUT_COPY_PATH' -w geosync -d shpowncloud -g '$DATA_PATH' -p '$PASSFILE' 1>>'$PUBLI_LOG' 2>>'$ERROR_LOG'"
echo $cmd
eval $cmd

