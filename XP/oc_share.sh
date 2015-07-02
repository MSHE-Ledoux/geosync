#!/bin/bash
# script de récupération des droits dans la base postgresql de owncloud

pghost="owncloud.umrthema.univ-fcomte.fr"
pguser="postgres"
pgpasswd="SeaSex&S1"
pgport="5432"
pgdb="cloud"
tblintermed="oc_intermed"
tblshare="oc_share"
tblldap="oc_ldap_user_mapping"
fileintermed="/tmp/layers_users.csv"
fileproperties="/var/lib/tomcat-geoserver0/webapps/geoserver/data/security/layers.properties"

rm -R $fileintermed

# sql 1- destruction de la table intermédiaire
# sql 2- création à partir de la table des partages ($tblshare) de la table intermédiaire ($tblintermed) enregistrant uniquement les répertoires partagés avec georchestra-ouvert
# sql 3- jointure entre la table des partages ($tblshare) et la table des utilisateurs ldap ($tblldap) et entre la table des partages ($tblshare) et la table intermédiaire ($tblintermed) pour sélectionner uniquement les distinguished names ($tblldap.ldap_dn) des utilisateurs qui ont des répertoires partagés communs à ceux de georchestra-ouvert (nb: les distinguished names sont formatés pour obtenir un nom d'utilisateur de type initiale du prénom + nom complet)
# boucle while à chaque fois qu'une ligne du résultat psql est lue les noms des shapefiles placés dans les répertoires $file_target soient joints un à un dans un fichier .csv aux individus à qui ils sont partagés
PGPASSWORD=$pgpasswd psql -P 'format=unaligned' -P 'fieldsep= ' -U $pguser -h $pghost -p $pgport \
	-c "DROP TABLE $tblintermed; \
	CREATE TABLE $tblintermed (oc_file_target) \
	AS (SELECT DISTINCT file_target FROM $tblshare WHERE share_with='georchestra-dev-ouvert'); \
	SELECT SUBSTR($tblldap.ldap_dn,4,1) || SPLIT_PART((SPLIT_PART($tblldap.ldap_dn,',',1)),' ',2) as share_with, $tblshare.file_target \
	FROM $tblshare, $tblldap, $tblintermed \
	WHERE $tblshare.share_with=$tblldap.owncloud_name AND $tblshare.file_target=$tblintermed.oc_file_target" $pgdb \
	| tail -n +2 | head -n -1 \
	| while read share_with file_target; do  
		for i in $(find /home/georchestra-ouvert/owncloud/owncloud/${file_target///} -name '*.shp'); do
			echo "$(basename $i .shp);$share_with" >> $fileintermed
		done
	done

# sql - jointure entre la table des partages ($tblshare) et la table des utilisateurs ldap ($tblldap) pour sélectionner les distinguished names ($tblldap.ldap_dn) des utilisateurs propriétaires des répertoires partagés (nb: les distinguished names sont formatés pour obtenir un nom d'utilisateur de type initiale du prénom + nom complet)
# boucle while à chaque fois qu'une ligne du résultat psql est lue les noms des shapefiles placés dans les répertoires $file_target soient joints un à un dans un fichier .csv aux individus qui en sont les propriétaires 
PGPASSWORD=$pgpasswd psql -P 'format=unaligned' -P 'fieldsep= ' -U $pguser -h $pghost -p $pgport \
	-c "SELECT SUBSTR($tblldap.ldap_dn,4,1) || SPLIT_PART((SPLIT_PART($tblldap.ldap_dn,',',1)),' ',2), $tblshare.file_target
	FROM $tblshare, $tblldap
	WHERE $tblshare.uid_owner=$tblldap.owncloud_name" $pgdb \
	| tail -n +2 | head -n -1 \
	| while read owner file_target; do  
		for i in ${file_target///}/*.shp; do
			echo "$(basename $i .shp);$owner" >> $fileintermed
		done
	done

	
while IFS=";" read col1 col2; do
	echo $col1 $col2
	echo "*.$col1.r=ROLE_$col2" >> $fileproperties
done < $fileintermed

cat $fileproperties | sort -g | uniq > $fileproperties


#$(find /home -name ${file_target///})/*.shp
# cat $fileintermed | sort -g | uniq > $fileintermed