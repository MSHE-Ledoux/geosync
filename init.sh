#!/bin/bash
# permet d'initialiser les workspaces de geoserver 

usage() { 
  echo "Usage : init.sh [OPTION]"
  echo ""
  echo "Options"
  echo " -c     (create) crée les différents workspaces"
  echo " -t     (test) teste la disponibilité du geoserver"
  echo " -v     verbeux"  
  echo " (-h)   affiche cette aide"
  echo ""
} 

echoerror() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  #Redirection vers la sortie d'erreurs standard  (stderr)
} 

main() {
  # chemin du script pour pouvoir appeler d'autres scripts dans le même dossier
  BASEDIR=$(dirname "$0")
  #echo "BASEDIR:$BASEDIR"
  
  local OPTIND opt
  while getopts "ctvh" opt; do
    # le : signifie que l'option attend un argument
    case $opt in
      c) create=1 ;;
      t) test=1 ;;
      v) verbose=1 ;;
      h) help=1 ;;
  # si argument faux renvoie la sortie    
      \?) error "Option invalide : -$OPTARG" ;;
  # si option sans argument renvoie la sortie   
      :) error "L'option -$OPTARG requiert un argument." ;;
    esac
  done
  shift $((OPTIND-1))
 
  # le mode verbeux pour tout afficher
  verbose=1
 
  # vérification des paramètres
  
  # si rien n'est demandé, alors affiche l'aide
  if  [ ! "$test" ] && [ ! "$create" ]; then
    usage
    exit
  fi
  
  if  [ $test ]; then
      echo "test du geoserver !"
  fi
  
  # récupère les paramètres de connexion dans le fichier .geosync situé dans le même dossier que ce script
  paramfilepath="$BASEDIR/.geosync.conf"
  local host login passwd workspace datastore pg_datastore db logs
  source "$paramfilepath"

  # attention les fichiers .geosync est interprété et fait donc confiance au code
  # pour une solution plus sûre, envisager quelque chose comme : #while read -r line; do declare $line; done < "$BASEDIR/.pass"

  # vérification du host/login/mot de passe
  if [ ! "$login" ] || [ ! "$passwd" ] || [ ! "$host" ]; then
    error "url du georserver, login ou mot de passe non définit; le fichier spécifié avec l'option -p [paramfilepath] doit contenir la définition des variables suivantes sur 3 lignes : login=[login] passwd=[password] host=[geoserver's url]"
  fi

  # récupère les paramètres d'authentification dans le fichier .pgpass
  # on utilise awk mais il faudrait faire quelque chose de plus propre !!
  authfilepath="$HOME/.ggpass"
  cmd="cat $HOME/.pgpass | grep $db"
  result=($(eval $cmd))
  echo $result
  cmd="echo $result | awk -F':' '{print \$4}'"
  echo $cmd
  db_login=($(eval $cmd))
  echo $db_login
  cmd="echo $result | awk -F':' '{print \$5}'"
  echo $cmd
  db_passwd=($(eval $cmd))
  echo $db_passwd
  cmd="echo $result | awk -F':' '{print \$1}'"
  echo $cmd
  db_host=($(eval $cmd))
  echo $db_host

  url=$host
  password=$passwd

  # boucle d'attente d'une réponse de geoserver
  statuscode=0
  until [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; do
      cmd="curl --silent --output /dev/null -w %{http_code} -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces"
      if  [ $verbose ]; then
        echo "récupére le code http de réponse du geoserver"
        echo $cmd
      fi
      statuscode=$(eval $cmd)

      # si le code de la réponse http est dans l'intervalle [200,300[
      if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
        if  [ $verbose ]; then
          echo "ok $statuscode"
        fi
        echo "connexion aux workspaces réussie"
      else
        echoerror "geoserver not ready ? ... error http code : $statuscode"
        sleep 1
      fi  
  done

  # recherche du workspace
  cmd="curl --silent -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces/$workspace | grep $workspace | grep Workspace"
  if [ $verbose ]; then
    echo "est-ce que le workspace $workspace existe ?"
    echo $cmd
  fi
  IFS=$'\n'
  result=($(eval $cmd))
  echo $result
  if [ ! $result ]; then
     # création du workspace
     cmd="curl -v -u '${login}:${password}' -XPOST -H 'Content-type: text/xml' 
               -d '<workspace><name>$workspace</name></workspace>'
          $url/geoserver/rest/workspaces"
     if [ $verbose ]; then
       echo "création du workspace $workspace"
       echo $cmd
     fi
     IFS=$'\n'
     result=($(eval $cmd))
     echo $result
  fi

  case $datastore in
    geosync_shp_open) 
       auths="${login}.*.r"
       roles="ROLE_ANONYMOUS,ROLE_AUTHENTICATED,GROUP_ADMIN,ADMIN"
       ;;
    geosync_shp_rsct)
       auths="${login}.*.r"
       roles="ROLE_AUTHENTICATED,GROUP_ADMIN,ADMIN"
       ;;
    :) error 
       ;;
  esac

  cmd="curl -v -u '${login}:${password}' -XPOST -H 'Content-type: text/xml' \
            -d '<?xml version=\"1.0\" encoding=\"UTF-8\"?> \
                <rules> \
                  <rule resource=\"$auths\">$roles</rule> \
               </rules>' \
       $url/geoserver/rest/security/acl/layers.xml"
  echo $cmd
  eval $cmd

  # si la réponse était un tableau, on pourrait le parcourir, élément par élément
  #IFS=$'\n'
  #tab=($(eval $cmd))
  #i=0
  #while [ "$i" -lt "${#tab[*]}" ]
  #do
  #  echo "Element $((i+1)) du tableau : ${tab[$i]}"
  #  ((i++))
  #done
  #echo "le workspace $workspace contient $i-10 datastores"

  # recherche du datastore
  cmd="curl --silent -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces/$workspace/datastores/$datastore | grep $datastore"
  if  [ $verbose ]; then
    echo "est-ce que le datastore $datastore existe ?"
    echo $cmd
  fi
  IFS=$'\n'
  result=($(eval $cmd))
  echo $result
  if [ ! $result ]; then
     cmd="curl -v -u '${login}:${password}' -XPOST -H 'Content-type: text/xml' \
               -d '<dataStore> \
                     <name>$datastore</name> \
                     <description>shp dans owncloud</description> \
                     <type>Directory of spatial files (shapefiles)</type> \
                     <enabled>true</enabled> \
                     <connectionParameters> \
                       <entry key=\"charset\">UTF-8</entry> \
                       <entry key=\"url\">file:data/$login/$datastore</entry> \
                       <entry key=\"enable spatial index\">true</entry> \
                       <entry key=\"cache and reuse memory maps\">true</entry> \
                     </connectionParameters> \
                   </dataStore>' \
               $url/geoserver/rest/workspaces/$workspace/datastores"
    echo $cmd
    eval $cmd
  fi
  
  # recherche du pg_datastore
  result=''
  cmd="curl --silent -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces/$workspace/datastores/$pg_datastore | grep $pg_datastore"
  if  [ $verbose ]; then
    echo "est-ce que le pg_datastore $pg_datastore existe ?"
    echo $cmd
  fi
  IFS=$'\n'
  result=($(eval $cmd))
  echo $result
  if [ ! $result ]; then
     cmd="curl -v -u '${login}:${password}' -XPOST -H 'Content-type: text/xml' \
               -d '<dataStore> \
                     <name>$pg_datastore</name> \
                     <connectionParameters> \
                       <host>$db_host</host> \
                       <port>5432</port> \
                       <database>$db</database> \
                       <user>$db_login</user> \
                       <passwd>$db_passwd</passwd> \
                       <dbtype>postgis</dbtype> \
                     </connectionParameters> \
                   </dataStore>' \
               $url/geoserver/rest/workspaces/$workspace/datastores"
    echo $cmd
    eval $cmd
  fi

} #end of main

# if this script is a directly call as a subshell (versus being sourced), then call main()
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi

