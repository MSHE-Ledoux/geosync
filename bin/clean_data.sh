#!/bin/bash

SCRIPT_FULL_PATH=`realpath "$0"` # /absolute/path/myscript.sh
SCRIPT_PATH=`dirname "$SCRIPT_FULL_PATH"`  # /absolute/path

# on a besoin ici uniquement des logs
PARAMFILE="$HOME/.geosync.conf"
#local host login passwd workspace datastore pg_datastore db logs
source "$PARAMFILE"

PATH_LOG="/var/log/$logs"

# date dans les logs
date >> $PATH_LOG/clean.log
  
# appel de clean.sh
bash "${SCRIPT_PATH}/clean.sh" -v -d 1>>$PATH_LOG/clean.log 2>>$PATH_LOG/clean_error.log

# à inclure dans un crontab
# tous les soirs de la semaine à 22h, nettoie le geoserver des couches qui ne sont plus partagées avec lui
# 0 22 * * 1-5   /path/clean_data.sh
