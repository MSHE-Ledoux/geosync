#!/bin/bash
# permet d'initialiser le workspace et ses datastores d'un geoserver 

usage() { 
  echo "Usage : init.sh [OPTION]"
  echo ""
  echo "Options"
  echo " -c     (create) crée le workspace et les datastores dès que le geoserver est disponible"
  echo " -t     (test) teste la disponibilité du geoserver"
  echo " -v     verbeux"  
  echo " (-h)   affiche cette aide"
  echo ""
} 

echoerror() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  #Redirection vers la sortie d'erreurs standard  (stderr)
} 

#echo if verbose=1
echo_ifverbose() {
  if [ $verbose ]; then echo "$@"; fi
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

  # vérification des paramètres
  
  # si rien n'est demandé, alors affiche l'aide
  if  [ ! "$test" ] && [ ! "$create" ]; then
    usage
    exit
  fi
  
  # teste la disponibilité du geoserver
  echo_ifverbose "teste la disponibilité du geoserver"

  # récupère les paramètres de connexion dans le fichier .geosync situé dans le même dossier utilisateur
  paramfilepath="$HOME/.geosync.conf"
  local host login passwd workspace datastore pg_datastore db logs
  source "$paramfilepath"

  # attention les fichiers .geosync est interprété et fait donc confiance au code
  # pour une solution plus sûre, envisager quelque chose comme : #while read -r line; do declare $line; done < "$HOME/.pass"

  # vérification du host/login/mot de passe
  if [ ! "$login" ] || [ ! "$passwd" ] || [ ! "$host" ]; then
    error "url du georserver, login ou mot de passe non définit; le fichier spécifié avec l'option -p [paramfilepath] doit contenir la définition des variables suivantes sur 3 lignes : login=[login] passwd=[password] host=[geoserver's url]"
  fi

  # récupère les paramètres d'authentification dans le fichier .pgpass (attendu dans le $HOME)
  # on utilise awk mais il faudrait faire quelque chose de plus propre !!
  cmd="cat $HOME/.pgpass | grep $db"
  result=($(eval $cmd)) # nom_hote:port:database:nom_utilisateur:mot_de_passe 
  cmd="echo $result | awk -F':' '{print \$4}'"
  db_login=($(eval $cmd))
  cmd="echo $result | awk -F':' '{print \$5}'"
  db_passwd=($(eval $cmd))
  cmd="echo $result | awk -F':' '{print \$1}'"
  db_host=($(eval $cmd))
  echo_ifverbose "login : ${db_login}; password : ${db_passwd}; host : ${db_host}"

  url=$host
  password=$passwd

  # boucle d'attente d'une réponse de geoserver
  statuscode=0
  until [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; do
      echo_ifverbose "#est-ce que le geoserver répond positivement ?"
      cmd="curl --silent --output /dev/null -w %{http_code} -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces"
      echo_ifverbose $cmd

      statuscode=$(eval $cmd)
	  echo_ifverbose "statuscode $statuscode"

      # si le code de la réponse http est dans l'intervalle [200,300[
      if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
        echo "OK connexion au geoserver réussie"
      else
        echoerror "geoserver not ready ? ... error http code : $statuscode"
        sleep 1
      fi  
  done

  # si la création des workspace/datastore n'a pas été demandée, alors quitte le script là
  if [ ! "$create" ]; then exit; fi
  
  
  # recherche du workspace
  echo_ifverbose "#est-ce que le workspace $workspace existe ?"
  cmd="curl --silent --output /dev/null -w %{http_code} -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces/$workspace"
  echo_ifverbose $cmd

  statuscode=$(eval $cmd)
  echo_ifverbose "statuscode $statuscode"
  
  if [ "$statuscode" -eq "404" ]; then # not found
     echo_ifverbose "le workspace n'existe pas"
	 
     echo_ifverbose "création du workspace $workspace"
     cmd="curl --silent --output /dev/null -w %{http_code} -u '${login}:${password}' -XPOST -H 'Content-type: text/xml' 
               -d '<workspace><name>$workspace</name></workspace>'
          $url/geoserver/rest/workspaces"
     echo_ifverbose $cmd

     statuscode=$(eval $cmd)
	 echo_ifverbose "statuscode $statuscode"
     if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
        echo "OK création du workspace $workspace réussie"
     else
        echoerror "ERROR création du workspace $workspace ... error http code : $statuscode"
     fi
  elif [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
	  echo "YES le workspace $workspace existe déjà"
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

  echo_ifverbose "tentative de création des régles d'accés"
  cmd="curl --silent --output /dev/null -w %{http_code} -u '${login}:${password}' -XPOST -H 'Content-type: text/xml' \
            -d '<?xml version=\"1.0\" encoding=\"UTF-8\"?> \
                <rules> \
                  <rule resource=\"$auths\">$roles</rule> \
               </rules>' \
       $url/geoserver/rest/security/acl/layers.xml"
  echo_ifverbose $cmd

  statuscode=$(eval $cmd)
  echo_ifverbose "statuscode $statuscode"
  
  if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
     echo "OK création des régles d'accés réussie"
  else
    echoerror "ERROR lors de la création des régles d'accés ... error http code : $statuscode"
  fi 

  
  # recherche du datastore
  echo_ifverbose "#est-ce que le datastore $datastore existe ?"
  cmd="curl -silent --output /dev/null -w %{http_code} -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces/$workspace/datastores/$datastore"
  echo_ifverbose $cmd
 
  statuscode=$(eval $cmd)
  echo_ifverbose "statuscode $statuscode"
  
  if [ "$statuscode" -eq "404" ]; then # not found
    echo_ifverbose "le datastore n'existe pas"
	
	echo_ifverbose "tentative de création du datastore"
    cmd="curl --silent --output /dev/null -w %{http_code} -u '${login}:${password}' -XPOST -H 'Content-type: text/xml' \
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
	echo_ifverbose $cmd

  statuscode=$(eval $cmd)
	echo_ifverbose "statuscode $statuscode"
	  
	if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
		echo "OK création du datastore $datastore réussie"
	else
		echoerror "ERROR lors de création du datastore $datastore... error http code : $statuscode"
	fi 
  elif [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
	  echo "YES le datastore $datastore existe déjà"
  fi
  
  # recherche du pg_datastore
  echo_ifverbose "#est-ce que le pg_datastore $pg_datastore existe ?"
  cmd="curl --silent --output /dev/null -w %{http_code} -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces/$workspace/datastores/$pg_datastore"
  echo_ifverbose $cmd

  statuscode=$(eval $cmd)
  echo_ifverbose "statuscode $statuscode"
  
  if [ "$statuscode" -eq "404" ]; then # not found
 	echo_ifverbose "le datastore n'existe pas"
	
	echo_ifverbose "tentative de création du datastore"
    cmd="curl --silent --output /dev/null -w %{http_code} -u '${login}:${password}' -XPOST -H 'Content-type: text/xml' \
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
	echo_ifverbose $cmd
	
  statuscode=$(eval $cmd)
	echo_ifverbose "statuscode $statuscode"
	
	if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
		echo "OK création du datastore $datastore réussie"
	else
		echoerror "ERROR lors de la création du datastore $datastore... error http code : $statuscode"
	fi 
  elif [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
	  echo "YES le datastore $datastore existe déjà"
  fi

} #end of main

# if this script is a directly call as a subshell (versus being sourced), then call main()
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi

