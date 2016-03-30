#!/bin/bash

# on a besoin ici uniquement des logs
PARAMFILE="$HOME/bin/.geosync.conf"
#local host login passwd workspace datastore pg_datastore db logs
source "$PARAMFILE"

PATH_LOG="/var/log/$logs"

# date dans les logs
date >> $PATH_LOG/clean.log
date >> $PATH_LOG/clean_error.log
  
# appel de clean.sh
bash $HOME/bin/clean.sh -v -d 1>>$PATH_LOG/clean.log 2>>$PATH_LOG/clean_error.log

# à inclure dans un crontab
# tous les soirs de la semaine à 22h, nettoie le geoserver des couches qui ne sont plus partagées avec lui
# 0 22 * * 1-5   /home/$HOME/bin/clean_data.sh

