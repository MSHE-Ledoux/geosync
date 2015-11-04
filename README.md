Objectif de geosync :
---------------------
Indexer dans geOrchestra les données déposées par les utilisateurs dans OwnCloud.

Vue d'ensemble de l'architecture :
----------------------------------

Description des fichiers de l'utilisateur georchestra-ouvert sur la machine georchestra :
* ~/**owncloud/owncloud** : montage webdav des fichiers de georchestra-ouvert sur ownncloud ; recopié par **rsync** dans ~/**owncloudsync**
* ~/owncloud/_geosync/**data** : entrées/sorties de l'outil de synchronisation. contient la dernière date des couches synchronisées (lastdate.txt)
* ~/owncloud/_geosync/data/**lastdate.txt** : stocke la dernière date des couches synchronisées ; pour resynchroniser toutes les couches, alors supprimer ce fichier
* ~/owncloud/owncloud/* : toutes les couches qui ont été partagées à georchestra-ouvert



Chaîne d'appel :
----------------

* **crontab**
  * **cron** (cron.sh) 
  * erreurs --> cron_error.log
    * **main.sh**
    * erreurs --> main_error.log
      * **publish.sh**
      * erreurs --> error.log
      * log --> publish.log
      * lit/écrit dans lastdate.txt
        * lib/**vector.sh**
        * lib/**metadata.sh**
        * lib/**raster.sh**
  * **clean.sh**
  * erreurs --> clean_error.log

Pistes d'évolution
------------------

* le fichier (.pass) contenant les mots de passe devrait être retiré des sources; il pourrait toutefois continuer à être partagé par owncloud et déplacer dans ~/owncloud/_geosync/; il faudrait dans ce cas modifier son chemin dans main.sh
* l'EPSG est définit par défaut; ce choix est à questionner; autant pour les couches de la métropole française cela peut être utile de les uniformisées en Lambert-93, autant pour les autres, cela est discutable; en fait, ce choix découle de la présence de nombreuses couches faites avec arcgis dont le système de coordonnées est inconnu pour le geoserver; il faut donc convertir ces couches; dans un premier temps, pour résoudre ce problème toutes les couches ont été converties; dans un second temps on pourrait envisager de ne convertir que les couches dont le systèmes de coordonnées est inconnu par le geoserver (couches ESRI arcgis)
* réplication des droits de owncloud au geoserver : owncloud -- geosync --> geonetwork; dans le dossier XP se trouvent des essais; oc_share.sh est une expérimentation pour récupérer directement depuis la base de données "à qui est partagé un fichier ?"; ceci est une expérimentation et ne devrait pas être la solution retenue pour la prod; la méthode recommandée consiste à faire un plugin sur le modèle de provisioning API qui expose sous forme de service web les informations de partage; la question à laquelle il doit répondre est : pour tel fichier qui m'est partagé (georchestra-ouvert) à qui d'autres est-il partagé ? ; ensuite  pour répliquer les régles de partage pour le geoserver, il faut écrire dans le fichiers de régles : 1 ligne par partage par personne (role) par couche, sachant qu'il faut créer automatiquement 1 role par groupe, et 1 groupe par personne du LDAP
* récupération des metadata des raster : exiftool ? 
* publication des metadata 

        # pour publier dans le geonetwork
        curl -u georchestraouvert:############ -XPOST -H "Content-Type: application/x-www-form-urlencoded" -d "dir=%2Ftmp%2Ftestimport%2F&file_type=single&uuidAction=overwrite&styleSheet=ArcCatalog8_to_ISO19115.xsl&assign=on&group=2&category=_none_&failOnError=off"  http://georchestra.umrthema.univ-fcomte.fr/geonetwork/srv/fre/util.import
        # reste à savoir comment faire le lien entre la fiche de métadonnées et les données même

