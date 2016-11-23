#!/bin/bash
# permet de supprimer (dépublier) les couches du geoserver

usage() { 
  echo "Usage : clean.sh [OPTION]"
  echo ""
  echo "Options"
  echo " -a     (all) supprime toutes les couches du geoserver"
  echo " -d     (diff) supprime les couches qui ne sont plus partagées (différence entre les couches du geoserver par celles de owncloud"
  echo " -s     (simulation) ne supprime rien"  
  echo " -v     verbeux"  
  echo " (-h)   affiche cette aide"
  echo ""
} 

xpath() { 
local xp=$1 
echo $(xmllint --xpath "$xp" "$input" 2>/dev/null )
# redirige l'erreur standard vers null pour éviter d'être averti de chaque valeur manquante (XPath set is empty)
# mais cela peut empêcher de détecter d'autres erreurs
# TODO: faire tout de même un test, une fois sur le fichier, de la validité du xml
} 

main() {
  # chemin du script pour pouvoir appeler d'autres scripts dans le même dossier
  BASEDIR=$(dirname "$0")
  #echo "BASEDIR:$BASEDIR"
  
  local OPTIND opt
  while getopts "adsvh" opt; do
    # le : signifie que l'option attend un argument
    case $opt in
      a) deleteall=1 ;;
      d) deletediff=1 ;;
      s) simulation=1 ;;
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
  
  # si aucune suppression n'est demandée, alors affiche l'aide
  if  [ ! "$deleteall" ] && [ ! "$deletediff" ]; then
    usage
    exit
  fi
  
  if  [ $simulation ]; then
      echo "simulation !"
  fi
  
  # pour générer un nom lisible et simplifier pour fichier
  # $(util::cleanName "./tic/tac toe.shp") -> tac_toe.shp #takes a filepath and returns a pretty name
  source "$BASEDIR/lib/util.sh"

  path="$HOME/owncloudsync" 

  paramfilepath="$BASEDIR/.geosync.conf"

  # récupère les paramètres de connexion dans le fichier .geosync situé dans le même dossier que ce script
  local host login passwd workspace datastore pg_datastore db logs
  source "$paramfilepath"

  # attention le fichier .geosync est interprété et fait donc confiance au code
  # pour une solution plus sûr envisager quelque chose comme : #while read -r line; do declare $line; done < "$BASEDIR/.pass"

  # vérification du host/login/mot de passe
  if [ ! "$login" ] || [ ! "$passwd" ] || [ ! "$host" ]; then
    error "url du georserver, login ou mot de passe non définit; le fichier spécifié avec l'option -p [paramfilepath] doit contenir la définition des variables suivantes sur 3 lignes : login=[login] passwd=[password] host=[geoserver's url]"
  fi

  url=$host
  password=$passwd

  # créer un dossier temporaire et stocke son chemin dans une variable
  local tmpdir=~/tmp/geosync_clean

  # supprime le dossier temporaire et le recrée
  rm -R "$tmpdir"
  mkdir "$tmpdir"

  ###################
  # pour les vecteurs
  ###################
  output="vectors_featuretypes.xml"
  touch "$tmpdir/$output"
  # liste les vecteurs du datastore
  
  cmd="curl --silent -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces/$workspace/datastores/$datastore/featuretypes.xml"
  if  [ $verbose ]; then
    echo "récupére la liste des vecteurs"
    echo $cmd
  fi
  xml=$(eval $cmd)
  echo $xml > "$tmpdir/$output"
  
  input="$tmpdir/$output"
  itemsCount=$(xpath 'count(/featureTypes/featureType)')

  touch "$tmpdir/vectors_published"
  for (( i=1; i < $itemsCount + 1; i++ )); do 
    name=$(xpath '/featureTypes/featureType['$i']/name/text()') # '
    echo $name >> "$tmpdir/vectors_published"
  done


  # ------------------------ Pour vecteurs issus de postgis

  output="vectors_featuretypes_pgsql.xml"
  touch "$tmpdir/$output"
  # liste les vecteurs du datastore

  cmd="curl --silent -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces/$workspace/datastores/$pg_datastore/featuretypes.xml"
  if  [ $verbose ]; then
    echo "récupére la liste des vecteurs"
    echo $cmd
  fi
  xml=$(eval $cmd)
  echo $xml > "$tmpdir/$output"

  input="$tmpdir/$output"
  itemsCount=$(xpath 'count(/featureTypes/featureType)')

  touch "$tmpdir/vectors_published_pgsql"
  for (( i=1; i < $itemsCount + 1; i++ )); do
    name=$(xpath '/featureTypes/featureType['$i']/name/text()') # '
    echo $name >> "$tmpdir/vectors_published_pgsql"
  done
  
  ###################
  # pour les rasteurs
  ###################
  output="rasters_coveragestores.xml"
  touch "$tmpdir/$output"
  # liste les coveragestores
  cmd="curl --silent -u '${login}:${password}' -XGET $url/geoserver/rest/workspaces/$workspace/coveragestores.xml" 
  if  [ $verbose ]; then
    echo "récupére la liste des rasteurs"
    echo $cmd
  fi
  xml=$(eval $cmd)
  echo $xml > "$tmpdir/$output"
  
  input="$tmpdir/$output"
  itemsCount=$(xpath 'count(/coverageStores/coverageStore)')

  touch "$tmpdir/rasters_published"
  for (( i=1; i < $itemsCount + 1; i++ )); do 
    name=$(xpath '/coverageStores/coverageStore['$i']/name/text()') 
    echo $name >> "$tmpdir/rasters_published"
  done

  ###################
  # pour les styles
  ###################
  output="styles.xml"
  touch "$tmpdir/$output"
  # liste les styles
  cmd="curl --silent -u '${login}:${password}' -XGET $url/geoserver/rest/styles.xml"
  if  [ $verbose ]; then
    echo "récupére la liste des styles"
    echo $cmd
  fi
  xml=$(eval $cmd)
  echo $xml > "$tmpdir/$output"

  input="$tmpdir/$output"
  itemsCount=$(xpath 'count(/styles/style)')

  touch "$tmpdir/styles_published"
  for (( i=1; i < $itemsCount + 1; i++ )); do
    name=$(xpath '//styles/style['$i']/name/text()')
    echo $name >> "$tmpdir/styles_published"
  done

  ######################
    
  # si on souhaite supprimer la différence entre les couches publiées et celles partagées
  # alors calcule la différence des listes et la stocke dans la liste des couches à supprimer
  if [ "$deletediff" ]; then
      #echo "synchronise les fichiers du montage webdav owncloud dans le dossier owncloudsync"
      #cmd="rsync -avr --delete --exclude '_geosync' --exclude 'lost+found' '/home/georchestra-ouvert/owncloud/' '/home/georchestra-ouvert/owncloudsync/'"
      #echo $cmd 
      #eval $cmd
      
      cd "$path"
      
      shopt -s globstar
      # set globstar, so that the pattern ** used in a pathname expansion context will 
      # match a files and zero or more directories and subdirectories.  
      #shopt -s extglob allow (.tif|.jpg) but does not work with globstar **
      
      ###################
      # pour les vecteurs
      ###################
      for filepath in **/*.shp; do
        outputlayername=$(util::cleanName "$filepath" -p)
        outputlayernamesansext=${outputlayername%%.*} #sans extension : toe.shp.xml -> toe
        outputlayernamesansext=$outputlayernamesansext"1"
        #echo "{$outputlayernamesansext}"
        echo "$outputlayernamesansext" >> "$tmpdir/vectors_shared"
      done
      
      # prend uniquement les noms présents dans la première liste (arraydiff <- liste1 - liste2)
      comm -23 <(sort "$tmpdir/vectors_published") <(sort "$tmpdir/vectors_shared") > "$tmpdir/vectors_tobedeleted"
      # -2 suppress lines unique to FILE2
      # -3 suppress lines that appear in both files
      
      
      # ------------------ pour les vecteurs postgis

      for filepath in **/*.shp; do
        outputlayername=$(util::cleanName "$filepath" -p)
        outputlayernamesansext=${outputlayername%%.*} #sans extension : toe.shp.xml -> toe
        #echo "{$outputlayernamesansext}"
        echo "$outputlayernamesansext" >> "$tmpdir/vectors_shared_pgsql"
      done

      # prend uniquement les noms présents dans la première liste (arraydiff <- liste1 - liste2)
      comm -23 <(sort "$tmpdir/vectors_published_pgsql") <(sort "$tmpdir/vectors_shared_pgsql") > "$tmpdir/vectors_tobedeleted_pgsql"
      # -2 suppress lines unique to FILE2
      # -3 suppress lines that appear in both files


      ###################
      # pour les rasters
      ###################
      for filepath in **/*.{tif,png,jpg,ecw} **/w001001.adf; do
        outputlayername=$(util::cleanName "$filepath" -p)
        outputlayernamesansext=${outputlayername%%.*} #sans extension : toe.shp.xml -> toe
        #echo "{$outputlayernamesansext}"
        echo "$outputlayernamesansext" >> "$tmpdir/rasters_shared"
      done
      
      # prend uniquement les noms présents dans la première liste (arraydiff <- liste1 - liste2)
      comm -23 <(sort "$tmpdir/rasters_published") <(sort "$tmpdir/rasters_shared") > "$tmpdir/rasters_tobedeleted"
      
      ####################
      # pour les styles
      ###################
       
      for filepath in **/*.sld ; do
        outputlayername=$(util::cleanName "$filepath" -p)
        outputlayernamesansext=${outputlayername%%.*} #sans extension : toe.shp.xml -> toe
        echo "$outputlayernamesansext" >> "$tmpdir/styles_shared"
      done

      # prend uniquement les noms présents dans la première liste (arraydiff <- liste1 - liste2)
      comm -23 <(sort "$tmpdir/styles_published") <(sort "$tmpdir/styles_shared") > "$tmpdir/styles_tobedeleted"

  # --------------------------    
  
  # si on souhaite supprimer toutes les couches
  # alors stocke la liste des couches publiées dans la liste des couches à supprimer
  elif [ "$deleteall" ]; then
      cat "$tmpdir/vectors_published" > "$tmpdir/vectors_tobedeleted"
      cat "$tmpdir/vectors_published_pgsql" > "$tmpdir/vectors_tobedeleted_pgsql"
      cat "$tmpdir/rasters_published" > "$tmpdir/rasters_tobedeleted"
      cat "$tmpdir/styles_published" > "$tmpdir/styles_tobedeleted" 
  fi
  
  # parcourt la liste des styles à supprimer dans le système de fichier
  # et supprime chacun d'eux
  while read style; do
    # Changement de style des couches utilisant le style qui va être supprimé
    # nécessaire car impossible de supprimer un style qui est utilisé par une couche
    # nécessaire d'effectuer l'opération avant la suppression des couches sinon erreur si couche supprimée
    while read layer; do
      if [[ "$layer" == "${style}1" ]]; then
        echo "Les couches shp symbolisées par ${style} prennent le style par défaut"
        cmd="curl --silent \
                 -u ${login}:${password} \
                 -XPUT -H \"Content-type: text/xml\" \
                 -d \"<layer><defaultStyle><name>generic</name></defaultStyle></layer>\" \
                 $url/geoserver/rest/layers/$workspace:${layer}"
        echo $cmd
        eval $cmd
      fi
    done <"$tmpdir/vectors_published"
    # Idem pour les styles utilisés par les couches pgsql
    while read layer; do
      if [[ "${layer}1" == "$style" ]]; then
        echo "Les couches pgsql symbolisées par ${style} prennent le style par défaut"
        cmd="curl --silent \
                 -u ${login}:${password} \
                 -XPUT -H \"Content-type: text/xml\" \
                 -d \"<layer><defaultStyle><name>generic</name></defaultStyle></layer>\" \
                 $url/geoserver/rest/layers/$workspace:${layer}"
        echo $cmd
        eval $cmd
      fi
    done <"$tmpdir/vectors_published_pgsql"
    # Idem pour les styles utilisés par les rasters
    while read layer; do
      if [[ "$layer" == "${style}" ]]; then
      echo "Les couches rasters symbolisées par ${style} prennent le style par défaut"
        cmd="curl --silent \
                 -u ${login}:${password} \
                 -XPUT -H \"Content-type: text/xml\" \
                 -d \"<layer><defaultStyle><name>raster</name></defaultStyle></layer>\" \
                 $url/geoserver/rest/layers/$workspace:${layer}"
        echo $cmd
        eval $cmd
      fi
    done <"$tmpdir/rasters_published"

    if [ "$style" != "generic" ] && [ "$style" != "line" ] && [ "$style" != "polygon" ] && [ "$style" != "point" ]  && [ "$style" != "raster" ] ; then
      echo "suppression de : $style"
      # supprime le style en ligne
      cmd="curl --silent -u '$login:$passwd' -XDELETE '$url/geoserver/rest/styles/${style}'" # erreur lors du curl : Accès interdit / Désolé, vous n'avez pas accès à cette page
      if  [ $verbose ]; then
        echo $cmd
      fi
      if  [ ! $simulation ]; then
        eval $cmd
      fi
    fi  
  done <"$tmpdir/styles_tobedeleted"


  # parcours la liste des vecteurs à supprimer
  # et supprime chacun d'eux
  while read vector; do
    echo "suppression de : $vector"
    # supprime une couche
    
    cmd="curl --silent -u '$login:$passwd' -XDELETE '$url/geoserver/rest/workspaces/$workspace/datastores/$datastore/featuretypes/$vector?recurse=true&purge=all'"
    # http://docs.geoserver.org/stable/en/user/rest/api/featuretypes.html#workspaces-ws-datastores-ds-featuretypes-ft-format
    # dans le cas d'un filesystem "recurse=true" dans le cas d'une bd postgis "recurse=false"
    if  [ $verbose ]; then
      echo $cmd
    fi
    if  [ ! $simulation ]; then
      eval $cmd
    fi

  done <"$tmpdir/vectors_tobedeleted"
  
  # parcours la liste des vecteurs de postgis à supprimer
  # et supprime chacun d'eux
  while read vector; do
    echo "suppression de : $vector"
    # supprime une couche

    cmd="curl --silent -u '$login:$passwd' -XDELETE '$url/geoserver/rest/workspaces/$workspace/datastores/$pg_datastore/featuretypes/$vector?recurse=true&purge=all'"
    cmd_pgsql="psql -h $dbhost -d $db -U geosync -w -c 'DROP TABLE \"$vector\";'"
    # http://docs.geoserver.org/stable/en/user/rest/api/featuretypes.html#workspaces-ws-datastores-ds-featuretypes-ft-format
    # dans le cas d'un filesystem "recurse=true" dans le cas d'une bd postgis "recurse=false"
    if [ $verbose ]; then
      echo $cmd
      echo $cmd_pgsql
    fi
    if [ ! $simulation ]; then
      eval $cmd
      eval $cmd_pgsql
    fi

    # suppression de la métadonnée associée
    cmd="python $BASEDIR/lib/deleteMetadata.py -l '$login' -p '$passwd' -u '$url' -w '$workspace' -i '$vector' $verbosestr"
    if [ $verbose ]; then
      echo $cmd
    fi
    if [ ! $simulation ]; then
        eval $cmd
    fi  

  done <"$tmpdir/vectors_tobedeleted_pgsql"


  # parcours la liste des rasteurs à supprimer dans le système de fichiers et postgis
  # et supprime chacun d'eux
  while read raster; do
    echo "suppression de : $raster"
    # supprime une couche
    cmd="curl --silent -u '$login:$passwd' -XDELETE '$url/geoserver/rest/workspaces/$workspace/coveragestores/$raster?recurse=true&purge=all'"
    # http://docs.geoserver.org/stable/en/user/rest/api/coveragestores.html#workspaces-ws-coveragestores-cs-format
    cmd_pgsql="psql -h $dbhost -d $db -U geosync -w -c 'DROP TABLE \"$raster\";'"
    if  [ $verbose ]; then
      echo $cmd
      echo $cmd_pgsql
    fi
    if  [ ! $simulation ]; then
      eval $cmd
      eval $cmd_pgsql
    fi
 
  # suppression de la métadonnée associée
    cmd="python $BASEDIR/lib/deleteMetadata.py -l '$login' -p '$passwd' -u '$url' -w '$workspace' -i '$raster' $verbosestr"
    if [ $verbose ]; then
      echo $cmd
    fi
    if [ ! $simulation ]; then
        eval $cmd
    fi
  
  done <"$tmpdir/rasters_tobedeleted"


} #end of main

# if this script is a directly call as a subshell (versus being sourced), then call main()
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi

