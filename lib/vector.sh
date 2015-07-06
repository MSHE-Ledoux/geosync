#!/bin/bash
#
# Importe une couche .shp dans un geoserver

usage() { 
  echo "==> usage : "
  echo "source /lib/vector.sh"
  echo "vector::publish -i input [-o output=input] [-e epsg=2154] -l login -p password -u url -w workspace -d datadtore [-v]"
  echo ""
  echo "1. convertit (une copie du) shapefile (-i input) dans le système de coordonnées désiré (-e epsg)"
  echo "2. publie le shapefile converti sous le nom (-o output=input)"
  echo "   dans l'entrepôt (-d datastore) de l'espace de travail (-w workspace)"
  echo "   dans le geoserver accéssible à l'adresse donnée (-u url)"
} 

vector::publish() {

  echoerror() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  #Redirection vers la sortie d'erreurs standard  (stderr)
  } 

  usage() {
    echoerror "vector::publish: -i input [-o output=input] [-e epsg=2154] -l login -p password -u url -w workspace -d datadtore [-v]"
  }

  local DIR
  #chemin du script (sourcé ou non) pour pouvoir appeler d'autres scripts dans le même dossier
  DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  echo -e "DIR:$DIR"
  # http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
  #readonly DIR

  # pour générer un nom lisible et simplifier
  # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp #takes a filepath and returns a pretty name
  source "$DIR/util.sh"

  local input output epsg login password url workspace datastore verbose
  local OPTIND opt
  while getopts "i:o:e:l:p:u:w:d:v" opt; do
    # le : signifie que l'option attend un argument
    case $opt in
      i) input=$OPTARG ;;
      o) output=$OPTARG ;;
      e) epsg=$OPTARG ;;
      l) login=$OPTARG ;;
      p) password=$OPTARG ;;
      u) url=$OPTARG ;;
      w) workspace=$OPTARG ;;
      d) datastore=$OPTARG ;;
      v) verbose=1 ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND-1))

  # vérification des paramètres
  if  [ ! "$input" ]; then
    echoerror "input missing"
    usage
    return 1 # erreur
  fi
  if [ ! "$login" ]; then
    echoerror "login missing"
    usage
    return 1 # erreur
  fi
  if [ ! "$password" ]; then
    echoerror "password missing"
    usage
    return 1 # erreur
  fi
  if [ ! "$url" ]; then
    echoerror "url missing"
    usage
    return 1 # erreur
  fi
  if [ ! "$workspace" ]; then
    echoerror "workspace missing"
    usage
    return 1 # erreur
  fi
  if [ ! "$datastore" ]; then
    echoerror "datastore missing"
    usage
    return 1 # erreur
  fi

  #valeurs des paramètres par défaut

  if [ ! "$output" ]; then
    # filename correspondant à l'$input par défaut "prettyfied"
    # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp
    output=$(util::cleanName "$input")
  fi

  if [ ! "$epsg" ]; then
    # Lambert 93 par défaut
    epsg="2154"
  fi

  #test si le fichier shapefile en $input existe
  #si le fichier n'existe pas, alors quitter
  if [ ! -f "$input" ]; then 
    echoerror "le fichier n'existe pas : $input"
    return 1 # erreur
  fi

  if  [ $verbose ]; then
    echo "shapefile en entrée : $input"
    echo "shapefile en sortie : $output"
    echo "système de coordonnées en sortie : $epsg"
    echo "url du Geoserver : $url"
    echo "workspace du Geoserver : $workspace"
    echo "datastore du Geoserver : $datastore"
  fi

  local statuscode=0

  #créer un dossier temporaire et stocke son chemin dans une variable
  local tmpdir=/tmp/geosync_vector

  #suprime le dossier temporaire et le recrée
  rm -R "$tmpdir"
  mkdir "$tmpdir"
  #tmpdir=$(mktemp --directory /tmp/geoscript_vector_XXXXXXX) # !!! does NOT work as file://$tmpdir becomes file:/tmp instead of file:///tmp

  # converti le système de coordonnées du shapefile (+ encodage en UTF-8)
  # attention : ne pas mettre le résultat directement dans le répertoire du datastore (data_dir) du Geoserver (l'appel à l'API rest s'en charge)
  if  [ $verbose ]; then
    echo "ogr2ogr -t_srs EPSG:$epsg -lco ENCODING=UTF-8 -overwrite $tmpdir/$output $input"
  fi
  ogr2ogr -t_srs "EPSG:$epsg" -lco ENCODING=UTF-8 -overwrite "$tmpdir/$output" "$input"
  #-lco ENCODING=ISO-8859-1  # correspond à LATIN1
  # attention : le datastore doit être en UTF-8

  # publication du shapefile dans le Geoserver
  # doc : http://docs.geoserver.org/2.6.x/en/user/rest/api/datastores.html#workspaces-ws-datastores-ds-file-url-external-extension
  if  [ $verbose ]; then
    echo "curl --silent --output /dev/null -w %{http_code} -u ${login}:######## -XPUT -H 'Content-type: text/plain' \
    -d \"file://$tmpdir/$output\" \
    $url/geoserver/rest/workspaces/$workspace/datastores/$datastore/external.shp?update=overwrite"
    
    curl -v -u "${login}:${password}" -XPUT -H 'Content-type: text/plain' \
    -d "file://$tmpdir/$output" \
    "$url/geoserver/rest/workspaces/$workspace/datastores/$datastore/external.shp?update=overwrite"
  fi

  statuscode=$(curl --silent --output /dev/null -w %{http_code} -u "${login}:${password}" -XPUT -H 'Content-type: text/plain' \
    -d "file://$tmpdir/$output" \
    "$url/geoserver/rest/workspaces/$workspace/datastores/$datastore/external.shp?update=overwrite" 2>&1)
  #--silent Silent or quiet mode. Don't show progress meter or error messages
  #-w %{http_code} pour récupérer le status code de la requête

  if  [ $verbose ]; then
    echo "" #saut de ligne
  fi

  # si le code de la réponse http est compris entre [200,300[
  if [[ "$statuscode" -ge "200" ]] && [[ "$statuscode" -lt "300" ]]; then
    if  [ $verbose ]; then
      echo "ok $statuscode"
    fi
    echo "vecteur publié : $output ($input)"
  else
    echoerror "error http code : $statuscode for $output"
  fi  

  # NB: le dossier temporaire n'est pas supprimé : rm -R "$tmpdir"
}

main() {
  usage
  exit
} #end of main

# if this script is a directly call as a subshell (versus being sourced), then call main()
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

#source d'inpiration pour le style du code bash https://google-styleguide.googlecode.com/svn/trunk/shell.xml
#outil pour vérifier la qualité du code : http://www.shellcheck.net/
