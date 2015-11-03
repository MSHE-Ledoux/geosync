#!/bin/bash

# si semble non monté alors on monte le webdav
# attention : ne pas faire précéder ce code par le flock (ci-dessous) car sinon semble ne pas supprimer le verrou

# sans autofs
#if [[ ! -d ~/owncloud ]]; then
#  mount ~/owncloud
#fi    

# avec autofs
if [[ ! -d ~/owncloud/owncloud ]]; then
   cd ~/owncloud/owncloud
fi

# utilisation d'un verrou pour éviter que le script main.sh ne se lance plusieurs fois en même temps
(
  # Wait for lock on /var/lock/.myscript.exclusivelock (fd 200) for 10 seconds
  flock -x -w 10 200 || exit 1

  # date dans les logs
  date >> /var/log/geosync/main.log
  date >> /var/log/geosync/main_error.log
  
  # appel de main.sh
  bash /home/georchestra-ouvert/bin/main.sh 1>>/var/log/geosync/main.log 2>>/var/log/geosync/main_error.log

) 200>/var/lock/.geosync.exclusivelock


# à inclure dans un crontab
# toutes les minutes de 8h à 20h, du lundi au vendredi, importe les couches partagées via owncloud dans le geoserver
# */1 08-20 * * 1-5 /home/georchestra-ouvert/bin/sync_data.sh 
