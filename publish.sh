#!/bin/bash

usage() { 
  program=$(basename "$0") 
  echo "==> usage :"
  echo "$program [-i inputpath=.] [-o output] [-g datapath=.] [-p passfile=./.geosync.conf] -w workspace -d datastore [-c coveragestore] [-e epsg] [-v]"
  echo "$program -i 'directory of vectors/rasters' [-g datapath=.] [-p passfile=./.geosync.conf] -w workspace -d datastore [-e epsg] [-v]"
  echo "$program -i vector.shp [-p passfile=./.geosync.conf] -w workspace -d datastore [-e epsg] [-v]"
  echo "$program -i raster.tif|png|adf|jpg|ecw [-p passfile=./.geosync.conf] -w workspace -c coveragestore [-e epsg] [-v]"
  echo ""
  echo "Publie les couches (rasteurs, vecteurs) dans le geoserver depuis le dossier donné ([input]) ou sinon courant et ses sous-dossiers"
  echo ""
  echo "le login, mot de passe et l'url du geoserver doivent être dans un fichier (par défaut, .geosync.conf dans le même dossier que ce script)"
} 

echoerror() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  #Redirection vers la sortie d'erreurs standard  (stderr)
} 

error() {
  echoerror "$@"
  exit 1
}

# importe les vecteurs et rasteurs du dossier (path) et sous-dossiers
# écrit dans un fichier dans le datapath la date de changement la plus récente des fichiers indexés
importallfiles() {
  local path="$1"
  shift #consomme l'argument du tableau des arguments, pour pouvoir récupérer le reste dans "$@"
  local datapath="$1"
  shift #consomme l'argument du tableau des arguments, pour pouvoir récupérer le reste dans "$@"

  local lastdatemodif=0
  local newlastdatemodif

  # si datapath n'est pas un dossier existant alors on le créée
  if  [ ! -d "$datapath" ]; then
    echo "creation de datapath : $datapath"
    mkdir $datapath
  fi

  #fichier dédié à stocker la valeur lastdatemodif, date de changement la plus récente des fichiers indexés
  configfile="$datapath/lastdate.txt"

  #test si le fichier  temporaire stockant la date de modif la plus récente existe
  #si tel est le cas, alors la récupère
  if [ -f "$configfile" ]; then 
    lastdatemodif=$(cat "$configfile")
  fi
  #newlastdatemodif est la valeur qui sera stockée à la place de lastdatemodif
  newlastdatemodif=$lastdatemodif

  cd "$path"

  shopt -s globstar
  # set globstar, so that the pattern ** used in a pathname expansion context will 
  # match a files and zero or more directories and subdirectories.  
  #shopt -s extglob allow (.tif|.jpg) but does not work with globstar **

  # TODO: format des rasters supportés: tif, png, adf, jpg, ecw
  # si des extension sont rajouter, alors penser à mettre à jour lib/util.sh util::typeoflayer()
  for filepath in **/*.{shp,tif,png,jpg,ecw,sld} **/w001001.adf; do
      # alternative dangeureuse :
      # for filepath in $(find "$path" -iname "*.shp"); do
      # option -iname à find pour un filte (-name) mais insensible à la casse (.SHP,.shp...)
    
      # test si le fichier existe bien car (dans certaines conditions encore inconnues selon qu'on le lance par le terminal ou le cron)
      # **/*.shp retourne aussi un fichier nommé "**/*.shp"
      if [ -f "$filepath" ]; then 
        # récupére la date de changement la plus récente des fichiers (de même nom) de la couche, exemple .shp.xml
        # attention cela différe de la date de modification
        # le rsync la modifie à l'heure locale lorsque le fichier est a été modifié
        datemodif=$(util::getlastchangedate "$filepath")
    
        if [[ "$datemodif" > "$lastdatemodif" ]]; then  # [[ .. ]] nécessaire pour comparer les chaines avec >
    
          importfile "$filepath" ""
    
          # TODO: ne modifier la date que si l'import du fichier a été un succés
          if [[ "$datemodif" > "$newlastdatemodif" ]]; then # [[ .. ]] nécessaire pour comparer les chaines avec >
            newlastdatemodif=$datemodif
          fi
        fi
    
      fi
  done

  echo "$newlastdatemodif" > "$configfile"

}

# import un fichier (couche) si le fichier ou ses dépendances (du même nom) ont une date de changement supérieure à la date donnée (0 pour toujours)
# convertit, publie les data, publie les metadata (TODO: paramètre les droits, publie le style)
# importfile ~/owncloud/Point.shp "2015-05-13 10:00:06.000000000 +0200"
# beware : modify newlastdatemodif
importfile() {
  local filepath="$1"
  shift #consomme l'argument du tableau des arguments, pour pouvoir récupérer le reste dans "$@"
  local outputlayername="$1"
  shift #consomme l'argument du tableau des arguments, pour pouvoir récupérer le reste dans "$@"

  local layertype="unknown"
  layertype=$(util::typeoflayer "$filepath")

  local layername
  #global newlastdatemodif

  vector() {
  
    #takes a filepath and returns a pretty name
    #examples
    # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp
    # $(util::cleanName "./tic/tac toe.shp" -p) -> tic_tac_toe.shp
    if [ ! "$outputlayername" ]; then
      echo "filepath : $filepath"
      outputlayername=$(util::cleanName "$filepath" -p)
    fi

    # convertit et publie la couche
    cmd="vector::publish -i '$filepath' -o '$outputlayername' -l '$login' -p '$pass' -u '$host'  -w '$workspace' -d '$datastore' -e '$epsg' $verbosestr"
    echo $cmd
    eval $cmd

    #publie les metadata même si le .xml n'existe pas pour les couches de l'entrepot postgis_data (dans ce cas publie les données par défaut)
    cmd="metadata::publish -i '$filepath.xml' -o '$outputlayername' -l '$login' -p '$pass' -u '$host' -w '$workspace' -d 'postgis_data' $verbosestr"
    echo $cmd
    eval $cmd
  
    #publie les metadata même si le .xml n'existe pas pour les couches de l'entrepot shpowncloud (dans ce cas publie les données par défaut)
    cmd="metadata::publish -i '$filepath.xml' -o '${outputlayername}1' -l '$login' -p '$pass' -u '$host' -w '$workspace' -d '$datastore' $verbosestr"
    echo $cmd
    eval $cmd

  }

  raster() {

    #takes a filepath and returns a pretty name
    #examples
    # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp
    # $(util::cleanName "./tic/tac toe.shp" -p) -> tic_tac_toe.shp
    if [ ! "$outputlayername" ]; then
      outputlayername=$(util::cleanName "$filepath" -p)
    fi

    cmd="raster::publish -i '$filepath' -o '$outputlayername' -l '$login' -p '$pass' -u '$host' -w '$workspace' -c '$coveragestore' -e '$epsg' $verbosestr"
    echo $cmd
    eval $cmd

  }

  style() {
  if [ ! "$outputlayername" ]; then
    outputlayername=$(util::cleanName "$filepath")
  fi 

  cmd="style::publish -i '$filepath' -o '$outputlayername' -l '$login' -p '$pass' -u '$host' $verbosestr"
  echo $cmd
  eval $cmd
  }


  case $layertype in
  'vector') vector ;;
  'raster') raster ;;
  'style') style ;;
  *) echoerror "file not supported : $filepath" ;;
  esac

  # TODO: retourner si succès ou non
  
}


main() {
  #chemin du script pour pouvoir appeler d'autres scripts dans le même dossier
  BASEDIR=$(dirname "$0")

  #local input output epsg datapath passfile workspace datastore coveragestore verbose help
  local OPTIND opt
  while getopts "i:o:e:g:p:w:d:c:vh" opt; do
    # le : signifie que l'option attend un argument
    case $opt in
      i) input=$OPTARG ;;
      o) output=$OPTARG ;;
      e) epsg=$OPTARG ;;
      g) datapath=$OPTARG ;;
      p) passfile=$OPTARG ;;
      w) workspace=$OPTARG ;;
      d) datastore=$OPTARG ;;
      c) coveragestore=$OPTARG ;;
      v) verbose=1; verbosestr="-v" ;;
      h) help=1 ;;
  # si argument faux renvoie la sortie    
      \?) error "Option invalide : -$OPTARG" ;;
  # si option sans argument renvoie la sortie   
      :) error "L'option -$OPTARG requiert un argument." ;;
    esac
  done
  shift $((OPTIND-1))

  if [ "$help" ]; then
    usage
    exit
  fi

  # "passfile" nom/chemin du fichier du host/login/mot de passe
  # par défaut, prend le fichier .geosync.conf dans le dossier de ce script
  if [ ! "$passfile" ]; then
    passfile="$BASEDIR/.geosync.conf"
  fi

  #test l'existence du fichier contenant le host/login/mot de passe
  if [ ! -f "$passfile" ]; then 
    error "le fichier contenant le host/login/mot de passe n'existe pas; le spécifier avec l'option -p [passfile]"
  fi

  #récupère login ($login), mot de passe ($pass), url du geoserver ($host) dans le fichier .geosync.conf situé dans le même dossier que ce script
  local login pass host
  source "$passfile"

  #attention le fichier .geosync.conf est interprété et fait donc confiance au code
  # pour une solution plus sûr envisager quelque chose comme : #while read -r line; do declare $line; done < "$BASEDIR/.geosync.conf"

  # vérification du host/login/mot de passe
  if [ ! "$login" ] || [ ! "$pass" ] || [ ! "$host" ]; then
    error "url du georserver, login ou mot de passe non définit; le fichier spécifié avec l'option -p [passfile] doit contenir la définition des variables suivantes sur 3 lignes : login=[login] pass=[password] host=[geoserver's url]"
  fi

  #valeurs des paramètres par défaut

  # par défaut index le répertoire courant
  if [ ! "$input" ]; then
    # répertoire courant par défaut
    input="."
  fi

  # par défaut cherche le fichier contenant la dernière date de changement du fichier traité dans le répertoire courant
  if [ ! "$datapath" ]; then
    # par défaut
    datapath="."
  fi

  if  [ ! -e "$input" ]; then
    error "n'existe pas : input : $input"
  fi

  # TODO : refactor
  if [ ! "$workspace" ]; then
    echoerror "workspace manquant"
    usage
    exit
  fi

  # pour générer un nom lisible et simplifier pour fichier
  # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp #takes a filepath and returns a pretty name
  source "$BASEDIR/lib/util.sh"
  # pour importer les vecteurs (couches shp)
  source "$BASEDIR/lib/vector.sh"
  # pour importer les rasteurs (couches .tif .adf .png .jpeg .ocw)
  source "$BASEDIR/lib/raster.sh"
  # pour importer les metadonnées des vecteurs
  source "$BASEDIR/lib/metadata.sh"
  # pour importer des fichiers de styles (fichiers .sld)
  source "$BASEDIR/lib/style.sh"

  newlastdatemodif=0

  #si c'est le chemin d'un répertoire alors indexe le répertoire
  if [ -d "$input" ]; then
    importallfiles "$input" "$datapath"

  #si c'est le chemin d'un fichier (couche) alors indexe le fichier
  elif [ -f "$input" ]; then
    importfile "$input" "$output"

  fi

} #end of main

# if this script is a directly call as a subshell (versus being sourced), then call main()
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi


#source d'inpiration pour le style du code bash https://google-styleguide.googlecode.com/svn/trunk/shell.xml
#outil pour vérifier la qualité du code : http://www.shellcheck.net/
