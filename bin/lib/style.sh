#!/bin/bash
#
# Importe une couche .shp dans un geoserver

usage() { 
  echo "==> usage : "
  echo "source /lib/style.sh"
  echo "style::publish -i input [-o output=input] -l login -p password -u url [-v]"
  echo ""
  echo "1. Publie un nouveau style à partir du fichier sld "
  echo "2. Affecte ce nouveau style aux couches qui lui sont associées"
  echo "   (dont le nom contient le préfixe sld_nom_couche"
} 

style::publish() {
  echoerror() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  # Redirection vers la sortie d'erreurs standard  (stderr)
  } 

  usage() {
    echoerror "vector::publish: -i input [-o output=input] -l login -p password -u url [-v]"
  }

  local DIR
  # chemin du script (sourcé ou non) pour pouvoir appeler d'autres scripts dans le même dossier
  DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  #echo "BASH_SOURCE:${BASH_SOURCE[0]}"
  #echo "DIR:$DIR"
  # http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
  #readonly DIR

  # pour générer un nom lisible et simplifier
  # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp #takes a filepath and returns a pretty name
  source "$DIR/util.sh"

  local input output epsg login password url workspace datastore verbose
  local OPTIND opt
  while getopts "i:o:l:p:u:w:s:g:v" opt; do
    # le : signifie que l'option attend un argument
    case $opt in
      i) input=$OPTARG ;;
      o) output=$OPTARG ;;
      l) login=$OPTARG ;;
      p) password=$OPTARG ;;
      u) url=$OPTARG ;;
      w) workspace=$OPTARG ;;
      s) datastore=$OPTARG ;;
      g) pg_datastore=$OPTARG ;;
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
if [ ! "$pg_datastore" ]; then
    echoerror "pg_datastore missing"
    usage
    return 1 # erreur
  fi

  #valeurs des paramètres par défaut

  if [ ! "$output" ]; then
    # filename correspondant à l'$input par défaut "prettyfied"
    # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp
    output=$(util::cleanName "$input")
  fi

  # teste si le fichier shapefile en $input existe
  # si le fichier n'existe pas, alors quitter
  if [ ! -f "$input" ]; then 
    echoerror "le fichier n'existe pas : $input"
    return 1 # erreur
  fi

  # Suppression du .sld à la fin du nom du fichier
  output=${output:0:-4}

  if  [ $verbose ]; then
    echo "sld en entrée : $input"
    echo "sld en sortie : $output"
    echo "url du Geoserver : $url"
  fi

  local statuscode=0

  ### publication du style dans le Geoserver 1- création du style vide 2- chargement du style

  ## Création du style vide - création du xml dans /var/www/geoserver/data/styles

  if [ $verbose ]; then
    var_v=$"-v"
    echo "curl $var_v -w %{http_code} \
                      -u ${login}:############# \
                      -XPOST -H 'Content-type: text/xml' \
                      -d '<style><name>$output</name><filename>${output}.sld</filename></style>' \
               $url/geoserver/rest/workspaces/${workspace}/styles 2>&1"
  else
    var_=$"--silent --output /dev/null"
  fi

  cmd="curl $var_v -w %{http_code} \
                   -u ${login}:${password} \
                   -XPOST -H 'Content-type: text/xml' \
                   -d '<style><name>$output</name><filename>${output}.sld</filename></style>' \
            $url/geoserver/rest/workspaces/${workspace}/styles 2>&1"

  echo $cmd
  statuscode=$(eval $cmd)
  
  #-w %{http_code} pour récupérer le status code de la requête
  
  if  [ $verbose ]; then
    echo "" #saut de ligne
    echo "valeur du statuscode $statuscode"
  fi

  # si le code de la réponse http est compris entre [200,300[
  if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
    if  [ $verbose ]; then
      echo "ok $statuscode"
    fi
    echo "style $output créé vide à partir de $input"
  else
    echoerror "error http code : $statuscode for $output"
  fi  

  ## Chargement des caractéristiques du style - création du sld dans /var/www/geoserver/data/styles
  
  cmd="curl $var_v -w %{http_code} \
                   -u ${login}:${password} \
                   -XPUT -H 'Content-type: application/vnd.ogc.sld+xml' \
                   -d @/home/$login/owncloudsync/$input \
            $url/geoserver/rest/workspaces/${workspace}/styles/$output 2>&1"
  
  if [ $verbose ]; then
    echo "curl $var_v -w %{http_code} \
                      -u ${login}:############### \
                      -XPUT -H 'Content-type: application/vnd.ogc.sld+xml' \
                      -d @/home/$login/owncloudsync/$input \
               $url/geoserver/rest/workspaces/${workspace}/styles/$output 2>&1"
  fi

  statuscode=$(eval $cmd)
  
  #-w %{http_code} pour récupérer le status code de la requête

  if [ $verbose ]; then
    echo "" #saut de ligne
    echo "valeur du statuscode $statuscode"
  fi

  # si le code de la réponse http est compris entre [200,300[
  if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
    if  [ $verbose ]; then
      echo "ok $statuscode"
    fi
    echo "style $output chargé à partir de $input"
  else
    echoerror "error http code : $statuscode for $output"
  fi

  ### Assignation du style à toutes les couches associées : nom_couche_sld_nom_style_sld.shp  <= nom_style.sld 

  # liste les vecteurs du datastore postgis_data et assigne le style à ceux concernés
  cmd="curl --silent \
             -u ${login}:${password} \
             -XGET $url/geoserver/rest/workspaces/$workspace/datastores/$pg_datastore/featuretypes.xml"

  echo "récupére la liste des vecteurs de $pg_datastore"
  echo $cmd
  xml=$(eval $cmd)

  if  [ $verbose ]; then
    echo $xml
  fi

  itemsCount=$(xmllint --xpath "count(//featureTypes/featureType)" - <<<"$xml" 2>/dev/null)
  # redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
  # mais cela peut empêcher de détecter d'autres erreurs
  # TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
  echo "itemsCount :  $itemsCount"

  for (( i=1; i < $itemsCount + 1; i++ )); do
    name=$(xmllint --xpath "/featureTypes/featureType[$i]/name/text()" - <<<"$xml")
    if [[ "$output" == "$name" ]] ; then
      cmd="curl --silent \
                 -u ${login}:${password} \
                 -XPUT -H \"Content-type: text/xml\" \
                 -d \"<layer><defaultStyle><name>${output}</name></defaultStyle></layer>\" \
                 $url/geoserver/rest/layers/$workspace:${name}"
      echo $cmd
      eval $cmd
    fi
  done
  
  # liste les vecteurs du datastore shpowncloud et assigne le style à ceux concernés
  cmd="curl --silent \
             -u ${login}:${password} \
             -XGET $url/geoserver/rest/workspaces/$workspace/datastores/$datastore/featuretypes.xml"

  echo "récupére la liste des vecteurs de $datastore"
  echo $cmd
  xml=$(eval $cmd)

  if  [ $verbose ]; then
    echo $xml
  fi

  itemsCount=$(xmllint --xpath "count(//featureTypes/featureType)" - <<<"$xml" 2>/dev/null)
  # redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
  # mais cela peut empêcher de détecter d'autres erreurs
  # TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
  echo "itemsCount :  $itemsCount"

  for (( i=1; i < $itemsCount + 1; i++ )); do
    name=$(xmllint --xpath "/featureTypes/featureType[$i]/name/text()" - <<<"$xml") 
    if [[ "${output}" == "${name}" ]] ; then 
      cmd="curl --silent \
                 -u ${login}:${password} \
                 -XPUT -H \"Content-type: text/xml\" \
                 -d \"<layer><defaultStyle><name>${output}</name></defaultStyle></layer>\" \
                 $url/geoserver/rest/layers/$workspace:${name}"
      echo $cmd
      eval $cmd
    fi
  done

  # liste les coveragestores
  cmd="curl --silent \
	     -u '${login}:${password}' \
             -XGET $url/geoserver/rest/workspaces/$workspace/coveragestores.xml"

  echo "récupére la liste des rasters"
  echo $cmd
  xml=$(eval $cmd)

  if  [ $verbose ]; then
    echo $xml
  fi

  itemsCount=$(xmllint --xpath "count(//coverageStores/coverageStore)" - <<<"$xml" 2>/dev/null)
  # redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
  # mais cela peut empêcher de détecter d'autres erreurs
  # TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
  echo "itemsCount :  $itemsCount"

  for (( i=1; i < $itemsCount + 1; i++ )); do
    name=$(xmllint --xpath "/coverageStores/coverageStore[$i]/name/text()" - <<<"$xml")
    if [[ "${output}" == "${name}" ]] ; then
      cmd="curl --silent \
                 -u ${login}:${password} \
                 -XPUT -H \"Content-type: text/xml\" \
                 -d \"<layer><defaultStyle><name>${output}</name></defaultStyle></layer>\" \
                 $url/geoserver/rest/layers/$workspace:${name}"
      echo $cmd
      eval $cmd
    fi
  done

}


main() {
  usage
  exit
} #end of main

# if this script is a directly call as a subshell (versus being sourced), then call main()
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi

# source d'inpiration pour le style du code bash https://google-styleguide.googlecode.com/svn/trunk/shell.xml
# outil pour vérifier la qualité du code : http://www.shellcheck.net/

