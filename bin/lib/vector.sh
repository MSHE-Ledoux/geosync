#!/bin/bash/
#
# Importe une couche .shp dans un geoserver

usage() { 
  echo "==> usage : "
  echo "source /lib/vector.sh"
  echo "vector::publish -i input [-o output=input] [-e epsg=2154] -l login -p password -u url -w workspace -s datastore -g pg_datastore -b db -d dbuser [-v]"
  echo ""
  echo "1. convertit (une copie du) shapefile (-i input) dans le système de coordonnées désiré (-e epsg)"
  echo "2. publie le shapefile converti sous le nom (-o output=input)"
  echo "   dans l'entrepôt (-s datastore) de l'espace de travail (-w workspace)"
  echo "   dans le geoserver accéssible à l'adresse donnée (-u url)"
} 

xpath() {
local xp=$1
echo $(xmllint --xpath "$xp" "$input" 2>/dev/null )
# redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
# mais cela peut empêcher de détecter d'autres erreurs
# TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
}

vector::publish() {

  echoerror() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2  #Redirection vers la sortie d'erreurs standard  (stderr)
  } 

  usage() {
    echoerror "vector::publish: -i input [-o output=input] [-e epsg=2154] -l login -p password -u url -w workspace -s datastore -g pg_datastore -b db -d dbuser [-v]"
  }

  #echo if verbose=1
  echo_ifverbose() {
    if [ $verbose ]; then echo "$@"; fi
  }

  local DIR
  # chemin du script (sourcé ou non) pour pouvoir appeler d'autres scripts dans le même dossier
  DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  # echo "BASH_SOURCE:${BASH_SOURCE[0]}"
  # echo "DIR:$DIR"
  # http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
  #readonly DIR

  # pour générer un nom lisible et simplifier
  # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp #takes a filepath and returns a pretty name
  source "$DIR/util.sh"

  local input output epsg login password url workspace datastore verbose
  local OPTIND opt
  while getopts "i:o:e:l:p:u:w:s:g:b:d:v" opt; do
    # le : signifie que l'option attend un argument
    case $opt in
      i) input=$OPTARG ;;
      o) output=$OPTARG ;;
      e) epsg=$OPTARG ;;
      l) login=$OPTARG ;;
      p) password=$OPTARG ;;
      u) url=$OPTARG ;;
      w) workspace=$OPTARG ;;
      s) datastore=$OPTARG ;;
      g) pg_datastore=$OPTARG ;;
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
    # filename correspondant à l'$input par défaut "prettyfied"
    # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp
    output=$(util::cleanName "$input" -p)
  fi

  if [ ! "$epsg" ]; then
    # Lambert 93 par défaut
    epsg="2154"
  fi

  # teste si le fichier shapefile en $input existe
  # si le fichier n'existe pas, alors quitter
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

  # crée un dossier temporaire et stocke son chemin dans une variable
  local tmpdir=~/tmp/geosync_vector

  # supprime le dossier temporaire et le recrée
  rm -R "$tmpdir"
  mkdir -p "$tmpdir"
  #tmpdir=$(mktemp --directory /tmp/geoscript_vector_XXXXXXX) # !!! does NOT work as file://$tmpdir becomes file:/tmp instead of file:///tmp

  # détecte l'encoding, indépendamment de la casse
  # si présence d'un fichier .cpg
  #  alors prendre le contenu du fichier .cpg
  # sinon, si présence d'un .dbf
  #  détecter l'encoding du fichier .dbf
  filenameext=$(basename "$input") # /path/t.o/file/vecteur.foo.shp -> vecteur.foo.shp
  filename=${filenameext%%.*}  # vecteur.foo.shp -> vecteur  
  filepath=$(dirname "$input") # relative/path/to/file/vecteur.shp -> relative/path/to/file
   
  echo "filename $filename"
  echo "filepath $filepath"
  
  # vérifie la présence des 2 fichiers .shx et .prj qui sont nécessaires en plus du .shp
  shx_found=($(find "${filepath}" -maxdepth 1 -iname "${filename}.shx"))
  if [ ${#shx_found[@]} -eq 0 ]; then  # ne pas utiliser [ -n $cpg_found ] comme c'est un array
    echo "ERROR le fichier ${filename}.shx n'a pas été trouvé. Interruption de la publication de ${input}"
    echoerror "le fichier .shx n'a pas été trouvé : ${filename}.shx"
    return 1 # erreur
  fi
  prj_found=($(find "${filepath}" -maxdepth 1 -iname "${filename}.prj"))
  if [ ${#prj_found[@]} -eq 0 ]; then  # ne pas utiliser [ -n $cpg_found ] comme c'est un array
    echo "ERROR le fichier ${filename}.prj n'a pas été trouvé. Interruption de la publication de ${input}"
    echoerror "le fichier .prj n'a pas été trouvé : ${filename}.prj"
    return 1 # erreur
  fi

  encoding="UTF-8"
  
  cpg_found=($(find "${filepath}" -maxdepth 1 -iname "${filename}.cpg"))
  if [ ${#cpg_found[@]} -gt 0 ]; then  # ne pas utiliser [ -n $cpg_found ] comme c'est un array
    echo "cpg existe $cpg_found"
  	encoding=$(cat "${cpg_found[0]}") # contenu du fichier .cpg, par exemple "UTF-8"
  else
	echo "cpg n'existe PAS"
    dbf_found=($(find "${filepath}" -maxdepth 1 -iname "${filename}.dbf"))
    if [ ${#dbf_found[@]} -gt 0 ]; then # ne pas utiliser [ -n $dbf_found ] comme c'est un array
      echo "dbf existe $dbf_found "
      #exemple de sortie de dbview foo.dbf | file -i -
      #/dev/stdin: text/plain; charset=iso-8859-1
      encoding=$(dbview "${dbf_found[0]}" | file -i - | cut -d= -f2)  # charset du fichier .dbf, par exemple "ISO-8859-1" ou encore "UTF-8"

      # avec encoding=unknown-8bit on obtient l'erreur suivante :
      # Unable to convert field name to UTF-8 (iconv reports "Argument invalide"). Current encoding is "unknown-8bit". Try "LATIN1" (Western European), or one of the values described at http://www.gnu.org/software/libiconv/
      # donc dans ce cas, cosidére encoding=LATIN1
      if [[ $encoding == unknown* ]]; then
        encoding="LATIN1"
      fi
    else
	  echo "dbf n'existe PAS"
	fi
  fi
   
  echo "encoding $encoding"
  
  # convertit le système de coordonnées du shapefile
  # attention : ne pas mettre le résultat directement dans le répertoire du datastore (data_dir) du Geoserver (l'appel à l'API rest s'en charge)
  echo_ifverbose "INFO convertit le shapefile (système de coordonnées) avec ogr2ogr"
  cmd="ogr2ogr -t_srs EPSG:$epsg -overwrite -skipfailures $tmpdir/$output $input"
  echo_ifverbose "INFO ${cmd}"

  eval ${cmd}
  # ogr2ogr -t_srs "EPSG:$epsg" -lco ENCODING=${encoding} -overwrite -skipfailures "$tmpdir/$output" "$input"
  #-lco ENCODING=ISO-8859-1  # correspond à LATIN1
  # attention : le datastore doit être en UTF-8
  # lorsque l'encodage, qui est connu, est définit à ce niveau par la Layer creation option (-lco ENCODING=${encoding})
  # cela peut produire l'erreur suivante : ERROR 1: Failed to create field name 'Id' : cannot convert to iso-8859-1
  # et poser problème au niveau de la table attibutaire
  # donc laisse la conversion à shp2pgsql (-W ${encoding})


  # ----------------------------- PUBLICATION POSTGIS -------------

  # necessaire car le nom d'une table postgres ne peut avoir de .
  output_pgsql=$(echo $output | cut -d. -f1) 
  
  # envoi du shapefile vers postgis
  cmd="shp2pgsql -I -W ${encoding} -s 2154 -d //$tmpdir/$output $output_pgsql | psql -h $dbhost -d $db -U $dbuser -w 1>/dev/null"
  echo $cmd
  eval $cmd

  # si la table est déjà publiée sur geoserver, la dépublie
  if [ -d "/var/www/geoserver/data/workspaces/$workspace/$pg_datastore/$output_pgsql" ]; then
    echo "la couche est déjà publiée sur geoserver : elle va être dépubliée"
    cmd="curl --silent -u '${login}:${password}' -XDELETE '$url/geoserver/rest/workspaces/$workspace/datastores/$pg_datastore/featuretypes/$output_pgsql?recurse=true&purge=all'"
    echo $cmd
    eval $cmd
  fi 

  # publication des données sur geoserver

  if [ $verbose ]; then
    var_v=$"-v"
    echo "curl $var_v -w %{http_code} -u \"${login}:#########\" -XPOST -H \"Content-type: text/xml\"  -d \"<featureType><name>$output_pgsql</name></featureType>\" \
    $url/geoserver/rest/workspaces/$workspace/datastores/$pg_datastore/featuretypes"
  else
    var_v=$"--silent --output /dev/null"
  fi

  cmd="curl $var_v -w %{http_code} -u '${login}:${password}' -XPOST -H 'Content-type: text/xml'  -d '<featureType><name>$output_pgsql</name></featureType>' \
  $url/geoserver/rest/workspaces/$workspace/datastores/$pg_datastore/featuretypes 2>&1"

  statuscode=$(eval $cmd)

  if  [ $verbose ]; then
    echo "" #saut de ligne
    echo "valeur du statuscode $statuscode"
  fi

  statuscode=$(echo $statuscode | tail -c 4)
  echo "statuscode $statuscode"

  # si le code de la réponse http est compris entre [200,300[
  if [ "$statuscode" -ge "200" ] && [ "$statuscode" -lt "300" ]; then
    if  [ $verbose ]; then
      echo "ok vecteur publié depuis postgis $statuscode"
    fi
    echo "vecteur publié depuis postgis: $output_pgsql ($input)"
  else
    echoerror "error vecteur publié depuis postgis http code : $statuscode for $output"
  fi


  # ---------------------------- Recherche d'un style correspondant au nom de la couche envoyée

          cmd="curl --silent \
	             -u ${login}:${password} \
	             -XGET $url/geoserver/rest/styles.xml"
	  if [ $verbose ]; then
            echo $cmd
          fi
          
          local tmpdir_styles=~/tmp/geosync_sld
          rm -R "$tmpdir_styles"
          mkdir -p "$tmpdir_styles"
          output="styles.xml"
          touch "$tmpdir_styles/$output"
          
          xml=$(eval $cmd)
          echo $xml
          echo $xml > "$tmpdir_styles/$output"

          input="$tmpdir_styles/$output"
          itemsCount=$(xpath 'count(/styles/style)')

          touch "$tmpdir_styles/styles_existants"
          for (( i=1; i < $itemsCount + 1; i++ )); do
            name=$(xpath '//styles/style['${i}']/name/text()')
            echo $name
            echo $name >> "$tmpdir_styles/styles_existants"
          done

	  while read line 
	  do
	    name=$line
	    if [[ "$output_pgsql" == "${name}"* ]]; then
	      cmd="curl --silent \
	                 -u ${login}:${password} \
	                 -XPUT -H \"Content-type: text/xml\" \
	                 -d \"<layer><defaultStyle><name>${name}</name></defaultStyle></layer>\" \
	                 $url/geoserver/rest/layers/${workspace}:${output_pgsql}"
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

