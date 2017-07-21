#!/bin/bash

# usage : "bash /chemin/complet/script.sh"  et non "bash script.sh"
# sinon ${BASH_SOURCE[0]} utilisé par certaines librairies renverra "." au lieu du répertoire attendu 

BASEDIR=$(dirname "$0")

# sans autofs
INPUT_OUTPUT_PATH="$HOME/owncloud"
# avec autofs
#INPUT_OUTPUT_PATH="$HOME/owncloud/owncloud"

#INPUT_COPY_PATH="$HOME/owncloudsync" # ceci n'est pas nécessairement le même que le répertoire de couches à publier publishing_directory dans .geosync.conf

# on a besoin ici uniquement des logs
PARAMFILE="$HOME/.geosync.conf"
#local host login passwd workspace datastore pg_datastore db logs
source "$PARAMFILE"

# vérifie que le chemin de l'arborescence à publier a bien été défini dans la conf
if [[ "${publishing_directory}" ]]; then 
    INPUT_COPY_PATH="${publishing_directory}"
else
    echo "WARNING aucun chemin d'arborescence à publier ('publishing_directory') défini dans .geosync.conf" >> $LOG_PATH/publish_error.log

    INPUT_COPY_PATH="$HOME/owncloudsync" # le chemin par défaut est conservé temporairement pour rétro-compatibilité # TODO ne pas prendre de valeur pas défaut et faire une vraie erreur
    echo "WARNING chemin d'arborescence par défaut : ${INPUT_COPY_PATH}"  >> $LOG_PATH/publish_error.log
fi

# verbose=1 # commenter pour diminuer les logs

#echo if verbose=1
echo_ifverbose() {
  if [[ $verbose ]]; then echo "$@"; fi
}

# montage à la demande, sans autofs
if grep -qs "$LOGNAME/owncloud" /proc/mounts; then
    echo_ifverbose "déjà monté"
else
    echo_ifverbose "pas encore monté... donc on le monte."
    mount ~/owncloud
fi

# montage automatique avec autofs
# ne fonctionne pas avec deux montages
#if [ ! -d ~/owncloud/owncloud ]; then
#   cd ~/owncloud/owncloud
#fi

# synchronise les fichiers du montage webdav pour être plus performant
# attention : si des photos sont présentes dans un répertoire Photos, elles pourraient être prises pour des rasters
# pour dépublier des couches, les déplacer dans le répertoire _unpublished
cmd="rsync --quiet -avr --delete --exclude 'lost+found' --exclude __*/ --exclude _unpublished '$INPUT_OUTPUT_PATH/' '$INPUT_COPY_PATH/'"
echo_ifverbose $cmd
eval $cmd

# démontage forcé, pour éviter les problèmes
if grep -qs "$LOGNAME/owncloud" /proc/mounts; then
    echo_ifverbose "on démonte"
    umount ~/owncloud
fi
