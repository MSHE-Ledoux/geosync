#!/bin/bash

# on a besoin ici uniquement des logs
PARAMFILE="$HOME/bin/.geosync.conf"
#local host login passwd workspace datastore pg_datastore db logs
source "$PARAMFILE"

PATH_LOG="/var/log/$logs"

# date dans les logs
date >> $PATH_LOG/clean.log
date >> $PATH_LOG/clean_error.log
  
# appel de init.sh
bash $HOME/bin/init.sh -t -v 1>>$PATH_LOG/init.log 2>>$PATH_LOG/init_error.log

