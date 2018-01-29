#!/bin/bash

SCRIPT_FULL_PATH=`realpath "$0"` # /absolute/path/myscript.sh
SCRIPT_PATH=`dirname "$SCRIPT_FULL_PATH"`  # /absolute/path

# si semble non monté alors on monte le webdav
# attention : ne pas faire précéder ce code par le flock (ci-dessous) car sinon semble ne pas supprimer le verrou

# on a besoin ici uniquement des logs
PARAMFILE="$HOME/.geosync.conf"
#local host login passwd workspace datastore pg_datastore db logs publishing_directory
source "$PARAMFILE"

DATA_PATH="$HOME/data"  # contient le fichier lastdate.txt avec la dernière date de changement de fichier traité
LOG_PATH="/var/log/$logs"

if [ ! -d $LOG_PATH ]; then
	mkdir -p "$LOG_PATH"
fi

# utilisation d'un verrou pour éviter que les scripts appelés ne se lancent plusieurs fois en même temps
(
  # Wait for lock on /var/lock/.myscript.exclusivelock (fd 201) for 10 seconds
  flock -x -w 10 201 || exit 1

  # date dans les logs
  date >> $LOG_PATH/sync.log
  date >> $LOG_PATH/sync_error.log
  
  cmd="bash '${SCRIPT_PATH}/sync_owncloud_data.sh' 1>>$LOG_PATH/sync.log 2>>$LOG_PATH/sync_error.log"
  echo $cmd
  eval $cmd

  date >> $LOG_PATH/publish.log
  date >> $LOG_PATH/publish_error.log

  # vérifie que le chemin de l'arborescence à publier a bien été défini dans la conf
  if [[ "${publishing_directory}" ]]; then 
    INPUT_COPY_PATH="${publishing_directory}"
  else
    echo "WARNING aucun chemin d'arborescence à publier ('publishing_directory') défini dans .geosync.conf" >> $LOG_PATH/publish_error.log

    INPUT_COPY_PATH="$HOME/owncloudsync" # le chemin par défaut est conservé temporairement pour rétro-compatibilité # TODO ne pas prendre de valeur pas défaut et faire une vraie erreur
    echo "WARNING chemin d'arborescence par défaut : ${INPUT_COPY_PATH}"  >> $LOG_PATH/publish_error.log
  fi

  cmd="bash '${SCRIPT_PATH}/publish.sh' -v -i '$INPUT_COPY_PATH' -d '$DATA_PATH' -p '$PARAMFILE' 1>>'$LOG_PATH/publish.log' 2>>'$LOG_PATH/publish_error.log'"
  echo $cmd
  eval $cmd


) 201>/var/lock/${logs}.exclusivelock


# à inclure dans un crontab
# toutes les minutes de 8h à 20h, du lundi au vendredi, importe les couches partagées via owncloud dans le geoserver
# */1 08-20 * * 1-5 /path/sync_data.sh 
