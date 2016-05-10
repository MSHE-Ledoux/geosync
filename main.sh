#!/bin/bash

# usage : "bash /chemin/complet/main.sh"  et non "bash main.sh"
# sinon ${BASH_SOURCE[0]} utilisé par certaines librairies renverra "." au lieu du répertoire attendu 

BASEDIR=$(dirname "$0")

# sans autofs
INPUT_OUTPUT_PATH="$HOME/owncloud"
# avec autofs
#INPUT_OUTPUT_PATH="$HOME/owncloud/owncloud"

INPUT_COPY_PATH="$HOME/owncloudsync"

# on a besoin ici uniquement des logs
PARAMFILE="$HOME/bin/.geosync.conf"
#local host login passwd workspace datastore pg_datastore db logs
source "$PARAMFILE"

# contient le fichier lastdate.txt avec la dernière date de changement de fichier traité
DATA_PATH="$HOME/data" 

# log dans un répertoire dédié à l'utilisateur
LOG_PATH="/var/log/$logs"
PUBLI_LOG="$LOG_PATH/publish.log"
ERROR_LOG="$LOG_PATH/publish_error.log"

# montage à la demande, sans autofs
if grep -qs "$LOGNAME/owncloud" /proc/mounts; then
    echo "déjà monté"
else
    echo "pas encore monté... donc on le monte."
    mount ~/owncloud
fi

# montage automatique avec autofs
# ne fonctionne pas avec deux montages
#if [ ! -d ~/owncloud/owncloud ]; then
#   cd ~/owncloud/owncloud
#fi

# synchronise les fichiers du montage webdav pour être plus performant
cmd="rsync -avr --delete --exclude 'lost+found' --exclude Photos '$INPUT_OUTPUT_PATH/' '$INPUT_COPY_PATH/'"
echo $cmd
eval $cmd

# démontage forcé, pour éviter les problèmes
if grep -qs "$LOGNAME/owncloud" /proc/mounts; then
    echo "on démonte"
    umount ~/owncloud
fi

if [ ! -d $LOG_PATH ]
    then mkdir -p "$LOG_PATH"
fi
date >> "$PUBLI_LOG"
date >> "$ERROR_LOG"

cmd="bash '$BASEDIR/publish.sh' -i '$INPUT_COPY_PATH' -d '$DATA_PATH' -p '$PARAMFILE' -v 1>>'$PUBLI_LOG' 2>>'$ERROR_LOG'"
echo $cmd
eval $cmd

