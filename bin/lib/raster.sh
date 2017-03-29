#!/bin/bash
#
# Importe un raster (ex:.tif) dans un geoserver

usage() { 
  echo "==> usage : "
  echo "source /lib/raster.sh"
  echo "raster::publish -i input [-o output=input] [-e epsg=2154] -l login -p password -u url -w workspace -c coveragestore -b db -d dbuser [-v]"
  echo ""
  echo "1. convertit (une copie du) raster (-i input) en tiff, dans le système de coordonnées désiré (-e epsg, ex: 4326 pour WGS84 )"
  echo "2. publie le raster converti sous le nom (-o output=input)"
  echo "   dans l'entrepôt (-c coveragestore) de l'espace de travail (-w workspace)"
  echo "   dans le geoserver accéssible à l'adresse donnée (-u url)"
} 

raster::publish() {

  echoerror() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  # Redirection vers la sortie d'erreurs standard  (stderr)
  } 

  usage() {
    error "raster::publish: -i input [-o output=input] [-e epsg=2154] -l login -p password -u url -w workspace -c coveragestore [-v]"
  }

  local DIR
  # chemin du script (sourcé ou non) pour pouvoir appeler d'autres scripts dans le même dossier
  DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  # http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
  #readonly DIR

  # pour générer un nom lisible et simplifier
  # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp #takes a filepath and returns a pretty name
  source "$DIR/util.sh"

  local input output epsg login password url workspace coveragestore verbose
  local OPTIND opt
  while getopts "i:o:e:l:p:u:w:c:b:d:vh" opt; do
    # le : signifie que l'option attend un argument
    case $opt in
      i) input=$OPTARG ;;
      o) output=$OPTARG ;;
      e) epsg=$OPTARG ;;
      l) login=$OPTARG ;;
      p) password=$OPTARG ;;
      u) url=$OPTARG ;;
      w) workspace=$OPTARG ;;
      c) coveragestore=$OPTARG ;;
      b) db=$OPTARG ;;
      d) dbuser=$OPTARG ;;
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


  # valeurs des paramètres par défaut

  if [ ! "$output" ]; then
    # par défaut correspondant à l'$input "prettyfied" e
    # $(util::cleanName "./tic/tac toe.tif") -> tac_toe.tif
    output=$(util::cleanName "$input" -p)
    #output=${filename%%.*}.tif # substitue son extension par tif
  fi


  if [ ! "$epsg" ]; then
    # Lambert 93 par défaut
    epsg="2154"
  fi

  if [ ! "$coveragestore" ]; then
    # par défaut, enlève l'extension pour le coveragestore (ex: tic/tac/toe.tif -> toe)
    coveragestore=${output%%.*}
  fi

  # teste si le fichier shapefile en $input existe
  # si le fichier n'existe pas, alors quitter
  if [ ! -f "$input" ]; then 
    echoerror "le fichier $input n'existe pas"
    return 1 # erreur
  fi

  if  [ $verbose ]; then
    echo "raster en entrée : $input"
    echo "raster en sortie : $output"
    echo "système de coordonnées en sortie : $epsg"
    echo "url du Geoserver : $url"
    echo "workspace du Geoserver : $workspace"
    echo "coveragestore du Geoserver : $coveragestore"
  fi

  local statuscode=0

  # crée un dossier temporaire et stocke son chemin dans une variable
  local tmpdir1=~/tmp/geosync_raster_step1
  local tmpdir=~/tmp/geosync_raster_step2

  # supprime le dossier temporaire et le recrée
  rm -R "$tmpdir1"
  mkdir -p "$tmpdir1"
  rm -R "$tmpdir"
  mkdir -p "$tmpdir"
  #tmpdir=$(mktemp --directory /tmp/geoscript_vector_XXXXXXX) # !!! does NOT work as file://$tmpdir becomes file:/tmp instead of file:///tmp

  # convertit le raster en .tif
  cmd="gdal_translate -q -of GTiff '$input' '$tmpdir1/$output'"
  if  [ $verbose ]; then
    echo $cmd
  fi
  eval $cmd
  #-q: (quiet) Suppress progress monitor and other non-error output.

  # reprojete le raster et définit une valeur par défaut pour les nodata
  # + enregistrement dans le data dir de Geoserver
  cmd="gdalwarp -q -dstnodata 255 -t_srs 'EPSG:$epsg' '$tmpdir1/$output' '$tmpdir/$output'"
  if  [ $verbose ]; then
    echo $cmd
  fi
  eval $cmd

  # ----------------------------- INTEGRATION POSTGIS -------------

  # nécessaire car le nom d'une table postgres ne peut avoir de .
  output_pgsql=$(echo $output | cut -d. -f1)
  #output_pgsql=${output_pgsql//-/_}  # Gestionnaire de bd de QGIS 2.12 n'accepte pas les rasters avec des - dans le nom

  # envoi du raster vers postgis
  # utilisation de l'option -d nécessaire pour écraser proprement les tables et d'inscrire des erreurs d'insert dans les logs de postgreql
  # il est necessaire d'augmenter dans /etc/postgresql/9.4/main/postgresql.conf la valeur par défaut
  # de checkpoint_segments à 10 ou au-delà pour éviter les erreurs LOG:  les points de vérification (checkpoints) arrivent trop fréquemment
  echo "raster2pgsql -s $epsg -d //$tmpdir/$output $output_pgsql | psql -h $dbhost -d $db -U $dbuser"
  raster2pgsql -s $epsg -d //$tmpdir/$output $output_pgsql | psql -h $dbhost -d $db -U $dbuser 2>/dev/null 1>/dev/null

  # ----------------------------------------------------------------

  # publication du raster dans le Geoserver
  # doc : http://docs.geoserver.org/stable/en/user/rest/api/coveragestores.html#workspaces-ws-coveragestores-cs-file-extension

  # publication du raster dans le Geoserver (méthode A : écriture des métadonnées de publication)
  if  [ $verbose ]; then
    echo "curl -w %{http_code} -u \"${login}:#######\" -XPUT -H 'Content-type: image/tiff' \
   -d \"file://$tmpdir/$output\" \
   \"$url/geoserver/rest/workspaces/$workspace/coveragestores/$coveragestore/external.geotiff?update=overwrite&recalculate=nativebbox,latlonbbox\""

  curl -v -u "${login}:${password}" -XPUT -H 'Content-type: image/tiff' \
   --data-binary "@$tmpdir/$output" \
   "$url/geoserver/rest/workspaces/$workspace/coveragestores/$coveragestore/file.geotiff?update=overwrite&recalculate=nativebbox,latlonbbox"

  fi

  statuscode=$(curl --silent --output /dev/null -w %{http_code} -u "${login}:${password}" -XPUT -H 'Content-type: image/tiff' \
   --data-binary "@$tmpdir/$output" \
   "$url/geoserver/rest/workspaces/$workspace/coveragestores/$coveragestore/file.geotiff?recalculate=nativebbox,latlonbbox" 2>&1)
  # doc : http://docs.geoserver.org/stable/en/user/rest/api/coveragestores.html#workspaces-ws-coveragestores-cs-file-extension
  # doc de recalculate : http://docs.geoserver.org/stable/en/user/rest/api/coveragestores.html#recalculate
  # tester avec update=overwrite&

  # publication uniquement des métadonnées
  #-d "file://$tmpdir/$output" \

  # publication métadonnées + données
  #--data-binary "@$tmpdir/$output" \

  # statuscode=$(curl --silent --output /dev/null -w %{http_code} -u "${login}:${password}" -XPUT -H 'Content-type: text/plain' \
  #   -d "file://$tmpdir/$output" \
  #   "$url/geoserver/rest/workspaces/$workspace/coveragestores/$coveragestore/external.shp?update=overwrite" 2>&1)
  #--silent Silent or quiet mode. Don't show progress meter or error messages
  #-w %{http_code} pour récupérer le status code de la requête

  if  [ $verbose ]; then
    echo "" #saut de ligne
  fi

  # si le code de la réponse http est compris entre [200,300[
  if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
    if  [ $verbose ]; then
      echo "ok $statuscode"
    fi
    echo "rasteur publié : $output ($input)"
  else
    echoerror "error http code : $statuscode for $output"
  fi  

  # NB: le dossier temporaire n'est pas supprimé : rm -R "$tmpdir"

  # Recherche d'un style correspondant
  cmd="curl --silent \
                     -u ${login}:${password} \
                     -XGET $url/geoserver/rest/styles.xml"
          if [ $verbose ]; then
            echo $cmd
          fi

          local tmpdir_styles=~/tmp/geosync_sld
          rm -R "$tmpdir_styles"
          mkdir -p "$tmpdir_styles"
          output_xml="styles.xml"
          touch "$tmpdir_styles/$output_xml"

          xml=$(eval $cmd)
          echo $xml
          echo $xml > "$tmpdir_styles/$output_xml"

          input="$tmpdir_styles/$output_xml"
          itemsCount=$(xpath 'count(/styles/style)')

          touch "$tmpdir_styles/styles_existants"
          for (( i=1; i < $itemsCount + 1; i++ )); do
            name=$(xpath '//styles/style['$i']/name/text()')
            echo $name
            echo $name >> "$tmpdir_styles/styles_existants"
          done

          while read line 
          do
            name=$line
            if [[ "$output" == "${name}"* ]]; then
              cmd="curl --silent \
                         -u ${login}:${password} \
                         -XPUT -H \"Content-type: text/xml\" \
                         -d \"<layer><defaultStyle><name>${name}</name></defaultStyle></layer>\" \
                         $url/geoserver/rest/layers/${workspace}:${output}"
              echo $cmd
              eval $cmd
            fi
          done < "$tmpdir_styles/styles_existants"



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

