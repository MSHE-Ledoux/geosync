#!/bin/bash

SCRIPT_FULL_PATH=`realpath "$0"` # /absolute/path/myscript.sh
SCRIPT_PATH=`dirname "$SCRIPT_FULL_PATH"`  # /absolute/path

# si semble non monté alors on monte le webdav
# attention : ne pas faire précéder ce code par le flock (ci-dessous) car sinon semble ne pas supprimer le verrou

# on a besoin ici uniquement des logs
PARAMFILE="$HOME/.geosync.conf"
#local host login passwd workspace datastore pg_datastore db logs
source "$PARAMFILE"

PATH_LOG="/var/log/$logs"

# utilisation d'un verrou pour éviter que le script main.sh ne se lance plusieurs fois en même temps
(
  # Wait for lock on /var/lock/.myscript.exclusivelock (fd 201) for 10 seconds
  flock -x -w 10 201 || exit 1

  # date dans les logs
  date >> $PATH_LOG/main.log
  date >> $PATH_LOG/main_error.log
  
  # appel de main.sh
  bash "${SCRIPT_PATH}/main.sh" 1>>$PATH_LOG/main.log 2>>$PATH_LOG/main_error.log

) 201>/var/lock/${logs}.exclusivelock


# à inclure dans un crontab
# toutes les minutes de 8h à 20h, du lundi au vendredi, importe les couches partagées via owncloud dans le geoserver
# */1 08-20 * * 1-5 /path/sync_data.sh 
