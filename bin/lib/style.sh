#!/bin/bash
#
# Importe un style .sld dans un geoserver et l'assigne à des couches (vecteurs, rasteurs)

# TODO envisager de revoir l'assignation des styles aux couches
# pour l'instant lors de l'assignation d'un style à une couche, le style remplace celui par défaut
# et pour qu'un style soit assigné à une couche, le nom de la couche doit être le même que celui du style (intialement envisagé : le nom de la couche devait finir par celui du style; cas particulier : être identique)
# mais sachant qu'une couche peut avoir plusieurs styles (et un style plusieurs couches)
# on pourrait envisager de conserver le style par défaut et de rajouter si besoin le style aux autres styles d'une couche
# (le fait de ne pas modifier le style par défaut devrait faciliter le clean des styles mais compliquer l'assignation d'un style (-> car ajout à une couche si pas déjà le cas))
# le lien entre les couches et les styles pourrait être fait au niveau des fichiers avec par exemple nom_couche.shp.nom_sytle_autonome.sld (et nom_sytle_autonome.sld) (en plus du nom_couche.sld)

usage() { 
  echo "==> usage : "
  echo "source /lib/style.sh"
  echo "style::publish -i input [-o output=input] -l login -p password -u url [-v]"
  echo ""
  echo "1. Publie un nouveau style à partir du fichier sld "
  echo "2. Affecte ce nouveau style aux couches qui lui sont associées"
  echo "   (de même nom)"
} 

style::publish() {
  echoerror() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  # Redirection vers la sortie d'erreurs standard  (stderr)
  } 

  usage() {
    echoerror "vector::publish: -i input [-o output=input] -l login -p password -u url [-v]"
  }

  #echo if verbose=1
  echo_ifverbose() {
    if [ $verbose ]; then echo "$@"; fi
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
  style=${output:0:-4}

  local statuscode=0

  ### publication du style dans le Geoserver 1- création du style vide 2- chargement du style

  ## Création du style vide - création du xml dans /var/www/geoserver/data/styles

  echo_ifverbose "INFO création du style vide : ${style}.sld"
  cmd="curl --silent -w %{http_code} \
                   -u ${login}:${password} \
                   -XPOST -H 'Content-type: text/xml' \
                   -d '<style><name>$style</name><filename>${style}.sld</filename></style>' \
            $url/geoserver/rest/workspaces/${workspace}/styles 2>&1"
  echo_ifverbose "INFO ${cmd}"

  result=$(eval ${cmd}) # retourne le contenu de la réponse suivi du http_code (attention : le contenu n'est pas toujours en xml quand demandé surtout en cas d'erreur; bug geoserver ?)
  statuscode=${result:(-3)} # prend les 3 derniers caractères du retour de curl, soit le http_code
  echo_ifverbose "INFO statuscode=${statuscode}"
  
  #-w %{http_code} pour récupérer le status code de la requête

  if [[ "${statuscode}" -ge "200" ]] && [[ "${statuscode}" -lt "300" ]]; then
    echo "OK création du style ${style} réussie"
  else
    echoerror "ERROR création du style ${style} échouée... error http code : ${statuscode}"
    echoerror "${cmd}"
    echo "ERROR création du style ${style} échouée (${statuscode})"
  fi

  ## Chargement des caractéristiques du style - création du sld dans /var/www/geoserver/data/styles
  echo_ifverbose "INFO chargement des caractéristiques du style : ${style}"
  cmd="curl --silent -w %{http_code} \
                   -u ${login}:${password} \
                   -XPUT -H 'Content-type: application/vnd.ogc.sld+xml' \
                   -d @/home/$login/owncloudsync/$input \
            $url/geoserver/rest/workspaces/${workspace}/styles/$style 2>&1"
  echo_ifverbose "INFO ${cmd}"

  result=$(eval ${cmd}) # retourne le contenu de la réponse suivi du http_code (attention : le contenu n'est pas toujours en xml quand demandé surtout en cas d'erreur; bug geoserver ?)
  statuscode=${result:(-3)} # prend les 3 derniers caractères du retour de curl, soit le http_code
  echo_ifverbose "INFO statuscode=${statuscode}"
  
  #-w %{http_code} pour récupérer le status code de la requête

  if [[ "${statuscode}" -ge "200" ]] && [[ "${statuscode}" -lt "300" ]]; then
    echo "OK assignation du style ${style} réussie"
  else
    echoerror "ERROR assignation du style ${style} échouée... error http code : ${statuscode}"
    echoerror "${cmd}"
    echo "ERROR assignation du style ${style} échouée (${statuscode})"
  fi

  ### Assignation du style à toutes les couches associées : nom_couche_sld_nom_style_sld.shp  <= nom_style.sld 
  echo_ifverbose "INFO assignation du style à toutes les couches associées..."

  # 1 liste les vecteurs du datastore postgis_data et 2 assigne le style à ceux concernés
  echo_ifverbose "INFO liste les vecteurs du datastore PostGIS ${pg_datastore}"
  cmd="curl --silent -w %{http_code} \
             -u ${login}:${password} \
             -XGET ${url}/geoserver/rest/workspaces/${workspace}/datastores/${pg_datastore}/featuretypes.xml"

  echo_ifverbose "INFO ${cmd}"
  
  result=$(eval ${cmd}) # retourne le contenu de la réponse suivi du http_code (attention : le contenu n'est pas toujours en xml quand demandé surtout en cas d'erreur; bug geoserver ?)
  statuscode=${result:(-3)} # prend les 3 derniers caractères du retour de curl, soit le http_code
  echo_ifverbose "INFO statuscode=${statuscode}"

  if [[ "${statuscode}" -ge "200" ]] && [[ "${statuscode}" -lt "300" ]]; then
    : # OK
  else
    echoerror "ERROR récupération de la liste des vecteurs du datastore PostGIS ${pg_datastore}, échouée... error http code : ${statuscode}"
    echoerror "${cmd}"
    echo "ERROR récupération de la liste des vecteurs du datastore PostGIS ${pg_datastore}, échouée (${statuscode})"
    # TODO gérer erreur, ne pas essayer de traiter le xml
  fi

  xml=${result:0:-3} # prend tout sauf les 3 derniers caractères (du http_code)

  itemsCount=$(xmllint --xpath "count(/featureTypes/featureType)" - <<<"$xml" 2>/dev/null)
  # redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
  # mais cela peut empêcher de détecter d'autres erreurs
  # TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
  echo_ifverbose "INFO ${itemsCount} vecteur(s) (PostGIS) trouvé(s)"

  for (( i=1; i < $itemsCount + 1; i++ )); do
    layer=$(xmllint --xpath "/featureTypes/featureType[$i]/name/text()" - <<<"$xml")
    if [[ "${style}" == "${layer}" ]] ; then  # (intialement envisagé : le nom de la couche devait finir par celui du style; cas particulier : être identique) d'ou : "${layer}" == *$style
      echo_ifverbose "INFO assigne le style ${style} à la couche ${layer}"
      cmd="curl --silent -w %{http_code} \
                 -u ${login}:${password} \
                 -XPUT -H \"Content-type: text/xml\" \
                 -d \"<layer><defaultStyle><name>${style}</name></defaultStyle></layer>\" \
                 ${url}/geoserver/rest/layers/${workspace}:${layer}"
      echo_ifverbose "INFO ${cmd}"

      result=$(eval ${cmd}) # retourne le contenu de la réponse suivi du http_code (attention : le contenu n'est pas toujours en xml quand demandé surtout en cas d'erreur; bug geoserver ?)
      statuscode=${result:(-3)} # prend les 3 derniers caractères du retour de curl, soit le http_code
      echo_ifverbose "INFO statuscode=${statuscode}"

      if [[ "${statuscode}" -ge "200" ]] && [[ "${statuscode}" -lt "300" ]]; then
        echo "OK assignation du style ${style} réussie"
      else
        echoerror "ERROR assignation du style ${style} échouée... error http code : ${statuscode}"
        echoerror "${cmd}"
        echo "ERROR assignation du style ${style} échouée (${statuscode})"
      fi
    fi
  done
  
  # 1 liste les vecteurs du datastore shpowncloud et 2 assigne le style à ceux concernés
  echo_ifverbose "INFO liste les vecteurs du datastore Directory ${datastore}"
  cmd="curl --silent -w %{http_code} \
             -u ${login}:${password} \
             -XGET ${url}/geoserver/rest/workspaces/${workspace}/datastores/$datastore/featuretypes.xml"

  echo_ifverbose "INFO ${cmd}"
  
  result=$(eval ${cmd}) # retourne le contenu de la réponse suivi du http_code (attention : le contenu n'est pas toujours en xml quand demandé surtout en cas d'erreur; bug geoserver ?)
  statuscode=${result:(-3)} # prend les 3 derniers caractères du retour de curl, soit le http_code
  echo_ifverbose "INFO statuscode=${statuscode}"

  if [[ "${statuscode}" -ge "200" ]] && [[ "${statuscode}" -lt "300" ]]; then
    : # OK
  else
    echoerror "ERROR récupération de la liste des vecteurs du datastore Directory ${datastore}, échouée... error http code : ${statuscode}"
    echoerror "${cmd}"
    echo "ERROR récupération de la liste des vecteurs du datastore Directory ${datastore}, échouée (${statuscode})"
    # TODO gérer erreur, ne pas essayer de traiter le xml
  fi

  xml=${result:0:-3} # prend tout sauf les 3 derniers caractères (du http_code)

  itemsCount=$(xmllint --xpath "count(/featureTypes/featureType)" - <<<"$xml" 2>/dev/null)
  # redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
  # mais cela peut empêcher de détecter d'autres erreurs
  # TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
  echo_ifverbose "INFO ${itemsCount} vecteur(s) (Directory) trouvé(s)"

  for (( i=1; i < $itemsCount + 1; i++ )); do
    layer=$(xmllint --xpath "/featureTypes/featureType[$i]/name/text()" - <<<"$xml")
    if [[ "${style}" == "${layer}" ]] ; then
      cmd="curl --silent -w %{http_code} \
                 -u ${login}:${password} \
                 -XPUT -H \"Content-type: text/xml\" \
                 -d \"<layer><defaultStyle><name>${style}</name></defaultStyle></layer>\" \
                 $url/geoserver/rest/layers/${workspace}:${layer}"

      result=$(eval ${cmd}) # retourne le contenu de la réponse suivi du http_code (attention : le contenu n'est pas toujours en xml quand demandé surtout en cas d'erreur; bug geoserver ?)
      statuscode=${result:(-3)} # prend les 3 derniers caractères du retour de curl, soit le http_code
      echo_ifverbose "INFO statuscode=${statuscode}"

      if [[ "${statuscode}" -ge "200" ]] && [[ "${statuscode}" -lt "300" ]]; then
        echo "OK assignation du style ${style} réussie"
      else
        echoerror "ERROR assignation du style ${style} échouée... error http code : ${statuscode}"
        echoerror "${cmd}"
        echo "ERROR assignation du style ${style} échouée (${statuscode})"
      fi
    fi
  done

  # 1 liste les coveragestores et 2 assigne le style à ceux concernés
  echo_ifverbose "INFO liste les rasteurs"
  cmd="curl --silent -w %{http_code} \
	     -u '${login}:${password}' \
             -XGET ${url}/geoserver/rest/workspaces/${workspace}/coveragestores.xml"

  echo_ifverbose "INFO ${cmd}"
  
  result=$(eval ${cmd}) # retourne le contenu de la réponse suivi du http_code (attention : le contenu n'est pas toujours en xml quand demandé surtout en cas d'erreur; bug geoserver ?)
  statuscode=${result:(-3)} # prend les 3 derniers caractères du retour de curl, soit le http_code
  echo_ifverbose "INFO statuscode=${statuscode}"

  if [[ "${statuscode}" -ge "200" ]] && [[ "${statuscode}" -lt "300" ]]; then
    : # OK
  else
    echoerror "ERROR récupération de la liste des rasteurs, échouée... error http code : ${statuscode}"
    echoerror "${cmd}"
    echo "ERROR récupération de la liste des rasteurs, échouée (${statuscode})"
    # TODO gérer erreur, ne pas essayer de traiter le xml
  fi

  xml=${result:0:-3} # prend tout sauf les 3 derniers caractères (du http_code)

  itemsCount=$(xmllint --xpath "count(/coverageStores/coverageStore)" - <<<"$xml" 2>/dev/null)
  # redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
  # mais cela peut empêcher de détecter d'autres erreurs
  # TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
  echo_ifverbose "INFO ${itemsCount} rasteur(s) trouvé(s)"

  for (( i=1; i < $itemsCount + 1; i++ )); do
    layer=$(xmllint --xpath "/coverageStores/coverageStore[$i]/name/text()" - <<<"$xml")
    if [[ "${style}" == "${layer}" ]] ; then
      cmd="curl --silent -w %{http_code} \
                 -u ${login}:${password} \
                 -XPUT -H \"Content-type: text/xml\" \
                 -d \"<layer><defaultStyle><name>${style}</name></defaultStyle></layer>\" \
                 ${url}/geoserver/rest/layers/${workspace}:${layer}"

      result=$(eval ${cmd}) # retourne le contenu de la réponse suivi du http_code (attention : le contenu n'est pas toujours en xml quand demandé surtout en cas d'erreur; bug geoserver ?)
      statuscode=${result:(-3)} # prend les 3 derniers caractères du retour de curl, soit le http_code
      echo_ifverbose "INFO statuscode=${statuscode}"

      if [[ "${statuscode}" -ge "200" ]] && [[ "${statuscode}" -lt "300" ]]; then
        echo "OK assignation du style ${style} réussie"
      else
        echoerror "ERROR assignation du style ${style} échouée... error http code : ${statuscode}"
        echoerror "${cmd}"
        echo "ERROR assignation du style ${style} échouée (${statuscode})"
      fi
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

