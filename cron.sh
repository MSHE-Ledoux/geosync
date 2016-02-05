#!/bin/bash

# si semble non monté alors monte le webdav
# attention : ne pas faire précédé ce code par le flock (ci-dessous) car sinon semble ne pas supprimer le verrou
if [ ! -d ~/owncloud/_geosync ]; then
  mount ~/owncloud
fi    

autoupdate() {

  mkdir -p ~/src/geosync/
  rsync -avr --delete ~/owncloud/_geosync/src/ ~/src/geosync/
  mkdir -p ~/bin/geosync/
  if [ -f ~/owncloud/_geosync/src/cron.sh ]; then 
    cat ~/owncloud/_geosync/src/cron.sh  > ~/bin/geosync/cron
  fi
  dos2unix --quiet ~/bin/geosync/cron
  #attention : dos2unix imprime sur la sortie d'erreurs standard même s'il n'y a pas d'erreur ("dos2unix: converting file ...")
  #donc pour éviter de polluer les logs d'erreur, on rend dos2unix silencieux (-q) mais cela peut conduire à une erreur muette difficilement détectable
  chmod u+x ~/bin/geosync/cron
} 

(
  # Wait for lock on /var/lock/.myscript.exclusivelock (fd 200) for 10 seconds
  flock -x -w 10 200 || exit 1
  
  autoupdate
  
  #~/owncloud/_geosync/data doit avoir été créé préalablement avec la procédure de setup : mkdir -p ~/owncloud/_geosync/data/
  bash ~/src/geosync/main.sh  2>>~/owncloud/_geosync/data/main_error.log
  #rajoute les logs d'erreur dans un fichier accessible sur owncloud par l'utilisateur geochestra-ouvert

) 200>/var/lock/.geosync.exclusivelock

#lire les logs du cron
#sudo grep CRON /var/log/syslog

#crontab -e
#toutes les minutes de 8h à 20h, du lundi au vendredi, importe les couches partagées via owncloud dans le geoserver
#*/1 08-20 * * 1-5  cd /home/georchestra-ouvert && ./bin/geosync/cron 2>>./owncloud/_geosync/data/cron_error.log

#on pourrait aussi imaginer rendre l'appel au script principal agnostique à son langage/environnement d'execution
#pour cela on le rendrait exécutable puis on l exécuterait (sans présumer qu'il s'agit de python ou autre)
#chmod u+x ~/src/main
#dos2unix ~/src/main #sinon gare a l'erreur ": Aucun fichier ou dossier de ce type" due a une edition sous windows avec fin de ligne (CR-LF)
#~/src/main
#ainsi le script courant, "boot" n'a pas à savoir comment appeler le script principal
#c'est le script principal qui sait comment se lancer lui-même
#cela créerait moins de dépendance et serait plus dans l'esprit *nix et boot
#en revanche le script est aussi edité dans un environnement windows et owncloud (avec logique windows)
#et son édition serait moins facile

#inspiration : http://blog.pryds.eu/2012/02/how-to-set-up-boxcom-autosync-on-ubuntu.html

#erreurs possibles:

#$'\r' : commande introuvable
#ceci est un caratère de "retour chariot" sous windows; le fichier a peut-être été modifié sous windows, owncloud, etc.; pour corriger ce problème enregistrer le fichier avec des sauts de ligne unix (la commande unix "dos2unix" le permet)
