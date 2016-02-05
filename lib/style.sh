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
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  #Redirection vers la sortie d'erreurs standard  (stderr)
  } 

  usage() {
    echoerror "vector::publish: -i input [-o output=input] -l login -p password -u url [-v]"
  }

  local DIR
  #chemin du script (sourcé ou non) pour pouvoir appeler d'autres scripts dans le même dossier
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
  while getopts "i:o:l:p:u:v" opt; do
    # le : signifie que l'option attend un argument
    case $opt in
      i) input=$OPTARG ;;
      o) output=$OPTARG ;;
      l) login=$OPTARG ;;
      p) password=$OPTARG ;;
      u) url=$OPTARG ;;
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

  #valeurs des paramètres par défaut

  if [ ! "$output" ]; then
    # filename correspondant à l'$input par défaut "prettyfied"
    # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp
    output=$(util::cleanName "$input")
  fi

  #test si le fichier shapefile en $input existe
  #si le fichier n'existe pas, alors quitter
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

  ###  publication du style dans le Geoserver 1- création du style vide 2- chargement du style

  ## Création du style vide - création du xml dans /var/www/geoserver/data/styles

  if [ $verbose ]; then
    var_v=$"-v"
    echo "curl $var_v -w %{http_code} \
                      -u ${login}:############# \
                      -XPOST -H 'Content-type: text/xml' \
                      -d '<style><name>$output</name><filename>$output.sld</filename></style>' \
               $url/geoserver/rest/styles 2>&1"
  else
    var_=$"--silent --output /dev/null"
  fi

  cmd="curl $var_v -w %{http_code} \
                   -u ${login}:${password} \
                   -XPOST -H 'Content-type: text/xml' \
                   -d '<style><name>$output</name><filename>$output.sld</filename></style>' \
            $url/geoserver/rest/styles 2>&1"

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
                   -d @/home/georchestra-ouvert/owncloudsync/$input \
            $url/geoserver/rest/styles/$output 2>&1"
  
  if  [ $verbose ]; then
    echo "curl $var_v -w %{http_code} \
                      -u ${login}:############### \
                      -XPUT -H 'Content-type: application/vnd.ogc.sld+xml' \
                      -d @/home/georchestra-ouvert/owncloudsync/$input \
               $url/geoserver/rest/styles/$output 2>&1"
  fi

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
    echo "style $output chargé à partir de $input"
  else
    echoerror "error http code : $statuscode for $output"
  fi

  ### Assignation du style à toutes les couches associées : nom_couche_sld_nom_style.shp  <= nom_style.sld 

  #crée un dossier temporaire et stocke son chemin dans une variable
  local tmpdir="~/tmp/geosync_publish_sld"

  #liste les vecteurs du datastore
  cmd="curl --silent \
             -u ${login}:${password} \
             -XGET $url/geoserver/rest/workspaces/geosync/datastores/shpowncloud/featuretypes.xml"

  if  [ $verbose ]; then
    echo "récupére la liste des vecteurs"
    echo $cmd
  fi
  
  xml=$(eval $cmd)

  itemsCount=$(xmllint --xpath "count(//featureTypes/featureType)" - <<<"$xml" 2>/dev/null)
  # redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
  # mais cela peut empêcher de détecter d'autres erreurs
  # TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
  echo "itemsCount :  $itemsCount"

  items=$(xmllint --xpath "//featureTypes/featureType/name/text()" - <<<"$xml" 2>/dev/null)
  echo $items

  touch "${tmpdir}/vectors_with_style"

  exit

  for (( i=1; i < $itemsCount + 1; i++ )); do
    echo "dans for"
    name=$(xpath '/featureTypes/featureType['$i']/name/text()') # '
    if [ "$name" =~ "-sld-$output" ]; then
      echo "dans if"
      cmd="echo \"$name\" >> $tmpdir/vectors_with_style"
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

#source d'inpiration pour le style du code bash https://google-styleguide.googlecode.com/svn/trunk/shell.xml
#outil pour vérifier la qualité du code : http://www.shellcheck.net/
