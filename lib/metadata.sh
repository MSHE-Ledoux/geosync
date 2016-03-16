#!/bin/bash
#
# Ajoute les metadata d'un .shp à une couche dans un geoserver

usage() { 
  echo "==> usage : "
  echo "source /lib/metadata.sh"
  echo "metadata::publish -i path/shapefile.shp.xml [-o output=shapefile] -l login -p password -u url -w workspace -d datastore [-v]"
  } 
  
metadata::publish() {

  echo "dans metadata::publish"

  echoerror() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  #Redirection vers la sortie d'erreurs standard  (stderr)
  } 

  usage() {
    echoerror "metadata::publish: -i path/shapefile.shp.xml [-o output=shapefile] -l login -p password -u url -w workspace -d datastore [-v]"
  }

  local DIR
  #chemin du script pour pouvoir appeler d'autres scripts dans le même dossier
  DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  #readonly DIR

  # pour générer un nom lisible et simplifier
  # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp #takes a filepath and returns a pretty name
  source "$DIR/util.sh"

  local input output login password url workspace datastore verbose
  local OPTIND opt
  while getopts "i:o:l:p:u:w:d:v" opt; do
    # le : signifie que l'option attend un argument
    case $opt in
      i) input=$OPTARG ;;
      o) output=$OPTARG ;;
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

  # par défault output prend la valeur du nom du fichier source sans son extension
  # tic/tac/toe.shp.xml -> toe
  if  [ ! "$output" ]; then
    #filenameext=$(basename "$input")
    #filename=${filenameext%%.*}
    #output=$filename
    output=$(util::cleanName "$input" -p)
  fi

  #test si le fichier (xml) existe
  #si le fichier n'existe pas, alors quitter
  if [ ! -f "$input" ] ; then 
    echoerror "le fichier n'existe pas : $input"
    #continue quand même pour publier les données par défaut  #return 1 # erreur 
  fi

  #retourne la valeur de l'expression xpath évalue sur le fichier $input
  #ex: $(xpath "/metadata/dataIdInfo/idCitation/date/pubDate/text()") -> 2015-01-29T00:00:00
  xpath() { 
    local xp=$1 
    echo $(xmllint --xpath "$xp" "$input" 2>/dev/null )
    # redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
    # mais cela peut empêcher de détecter d'autres erreurs
    # TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
  } 

  #récupére (avec xpath) les métadonnées au format INSPIRE d'ArcGIS depuis le .shp.xml
  metadata=$(xpath "//text()")
  echo $metadata
  title=$(xpath "/metadata/dataIdInfo/idCitation/resTitle/text()") 
  abstract=$(xpath "/metadata/dataIdInfo/idAbs/text()")
  origin=$(xpath "/metadata/dataIdInfo/rpIndname/text()")
  pubdate=$(xpath "/metadata/dataIdInfo/idCitation/date/pubDate/text()")


  get_xml_value() {
    filexml=$1
    pathx='xpath string('$2')'
    setns1='setns gmd=http://www.isotc211.org/2005/gmd'
    setns2='setns gco=http://www.isotc211.org/2005/gco'
    xmllint --xinclude --shell $filexml <<CMD
$setns1
$setns2
$pathx
CMD
  }

  #si le titre, le résumé, l'auteur ou la date de publication n'est pas trouvé avec leurs balises au format INSPIRE 
  #ils sont recherchés avec leurs balises au format ISO 19139
  #ils sont alors recherchés avec leurs balises ISO19139 de QSphere
  #s'ils ne sont pas du tout renseignés dans le xml alors ils sont remplacés par une variante
  if [ ! "$title" ]; then
    title=$(xpath "/metadata/idinfo/citation/citeinfo/title/text()")
    if [ ! "$title"]; then
      path_filexml=$input
      path_title='/gmd:MD_Metadata/gmd:identificationInfo/gmd:MD_DataIdentification/gmd:citation/gmd:CI_Citation/gmd:title/gco:CharacterString'
      title=$(get_xml_value $path_filexml $path_title)
      title=`echo $title | grep -o -P '(?<=: ).*(?= / )'`
      echo '  '
      echo $LANG
      echo '  '
      echo $title
      if [ ! "$title" ]; then          
        title=$(basename "$output" .shp)
      fi
    fi
  fi

  if [ ! "$abstract" ]; then
    abstract=$(xpath "/metadata/idinfo/descript/abstract/text()")
    if [ ! "$abstract" ]; then
      path_filexml=$input
      path_abstract='/gmd:MD_Metadata/gmd:identificationInfo/gmd:MD_DataIdentification/gmd:abstract/gco:CharacterString'
      abstract=$(get_xml_value $path_filexml $path_abstract)       
      abstract=`echo $abstract | grep -o -P '(?<=: ).*(?= / )'`
      echo $abstract
      if [ ! "$abstract" ]; then
        abstract="A compléter!"
      fi
    fi
  fi

  if [ ! "$origin" ]; then
    origin=$(xpath "/metadata/idinfo/citation/citeinfo/origin/text()")
    if [ ! "$origin" ]; then
      path_filexml=$input
      path_origin='/gmd:MD_Metadata/gmd:contact/gmd:CI_ResponsibleParty/gmd:organisationName/gco:CharacterString'
      origin=$(get_xml_value $path_filexml $path_origin)
      origin=`echo $origin | grep -o -P '(?<=: ).*(?= / )'`
      echo $origin
      if [ ! "$origin" ]; then
        origin="A compléter!"
      fi
    fi
  fi

  if [ ! "$pubdate" ]; then
    pubdate=$(xpath "/metadata/idinfo/citation/citeinfo/pubdate/text()")
    if [ ! "$pubdate" ]; then
      path_filexml=$input
      path_pubdate='/gmd:MD_Metadata/gmd:identificationInfo/gmd:MD_DataIdentification/gmd:citation/gmd:CI_Citation/gmd:date/gmd:CI_Date/gmd:date/gco:Date'
      pubdate=$(get_xml_value $path_filexml $path_pubdate)
      pubdate=`echo $pubdate | grep -o -P '(?<=: ).*(?= / )'`
      echo $pubdate
      if [ ! "$pubdate" ]; then
        pubdate="A compléter!"
      fi
    fi
  fi


  echo $url
  echo $workspace
  echo $datastore
  echo $output


  local shppath=${input%.*}  # /GPS/Point_ge.shp.xml -> /GPS/Point_ge.shp

  ## --------- Vecteurs issus de postgis  --------------

  #attention : spécifier le shp concerné en fin d'url
  #http://docs.geoserver.org/2.6.x/en/user/rest/api/datastores.html#workspaces-ws-datastores-ds-file-url-external-extension
  local statuscode
  statuscode=$(curl --verbose --output /dev/null -w %{http_code} -u "$login:$password" -XPUT -H "Content-type: text/xml" \
    -d "<featureType><title>$title</title>
<abstract>$abstract
Auteur : $origin
Date de production de la donnée : $pubdate
Chemin : $shppath</abstract>
<enabled>true</enabled>
<description>
  metadata: $metadata </description></featureType>" \
     "$url/geoserver/rest/workspaces/$workspace/datastores/postgis_data/featuretypes/$output"   2>&1)
  #--output /dev/null
  #<enabled>true</enabled><advertised>true</advertised> est nécessaire pour éviter que la couche ne soit dépubliée (car par défaut "enabled" est mis à false lors d'un update
  # pour rajouter des mots clés
  # ...</description><keywords><string>my_keyword1</string><string>my_keyword2</string></keywords></featureType>


  # si le code de la réponse http est compris entre [200,300[ alors OK
  if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
    if  [ $verbose ]; then
      echo "ok $statuscode"
    fi
    echo "metadata publiées : $output "
  else
    echoerror "http code : $statuscode for metadata of $output"
  fi

  # ---------- Vecteurs issus de shpowncloud --------------

  local statuscode
  statuscode=$(curl --verbose --output /dev/null -w %{http_code} -u "$login:$password" -XPUT -H "Content-type: text/xml" \
    -d "<featureType><title>$title</title>
<abstract>$abstract
Auteur : $origin
Date de production de la donnée : $pubdate
Chemin : $shppath</abstract>
<enabled>true</enabled>
<description>
  metadata: $metadata </description></featureType>" \
     "$url/geoserver/rest/workspaces/$workspace/datastores/$datastore/featuretypes/${output}1"   2>&1)
  #--output /dev/null
  #<enabled>true</enabled><advertised>true</advertised> est nécessaire pour éviter que la couche ne soit dépubliée (car par défaut "enabled" est mis à false lors d'un update
  # pour rajouter des mots clés
  # ...</description><keywords><string>my_keyword1</string><string>my_keyword2</string></keywords></featureType>


  # si le code de la réponse http est compris entre [200,300[ alors OK
  if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
    if  [ $verbose ]; then
      echo "ok $statuscode"
    fi
    echo "metadata publiées : ${output}1 "
  else
    echoerror "http code : $statuscode for metadata of $output"
  fi


} #end of importmetadata()

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
