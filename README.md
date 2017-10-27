Objectif de ge@sync :
---------------------
Publier sur geOrchestra les données cartographiques déposées par les utilisateurs dans OwnCloud, et partagées :
- soit avec l'utilisateur georchestra-ouvert, pour un accès public ; 
- soit avec l'utilisateur georchestra-restreint, pour un accès limité aux personnes identifiées de l'IDS geOrchestra.

Les données sont publiées sur le geoserver de geOrchestra ; les métadonnées sont publiées sur le geonetwork de geOrchestra.


Comment installer ge@sync ?
---------------------------
avec Docker, en déployant les conteneurs du projet geOrchestra et le conteneur geosync.
https://github.com/MSHE-Ledoux/georchestra-geosync


Vue d'ensemble de l'architecture :
----------------------------------

Description des fichiers de l'utilisateur georchestra-ouvert sur la machine georchestra :
* **~/owncloudsync** : répertoire de synchronisation par la commande owncloudcmd des données partagées avec georchestra-ouvert ou georchestra-restreint.
                       à noter que les données rangées dans le dossier nommé __unpublished ne sont pas publiées sur geOrchestra.
* **~/data** : entrées/sorties de l'outil de synchronisation
* **~/data/lastdate.txt** : stocke la dernière date des couches synchronisées ; pour resynchroniser toutes les couches, alors supprimer ce fichier
* **~/bin/** : les scripts d'appel
* **~/bin/sync_data.sh** : synchronisation des données et publication sur le geoserver
* **~/bin/clean_data.sh** : dépublication des couches qui ne sont plus partagées
* **~/bin/ad2ldap_sync.py** : transfert des utilisateurs AD dans l'annuaire LDAP de geOrchestra
* **~/bin/lib : les scripts d'envoi de données en fonction de leur type


Chaîne d'appel :
----------------

* **init_data.sh**
  * **init.sh**
    * erreurs --> init_error.log
    * log --> init.log
  
* **crontab**
  * **sync_data.sh**
    * erreurs --> cron_error.log
    * **sync_owncloud_data.sh**
      * erreurs --> sync_error.log
      * log --> sync.log
    * **publish.sh**
      * erreurs --> publish_error.log
      * log --> publish.log
      * lit/écrit dans lastdate.txt
      * utilise des scripts dans lib
        * **lib/vector.sh**
		* **lib/metadata_2_gs.sh**
        * **lib/metadata_2_gn.py**
        * **lib/raster.sh**
  * **clean_data.sh**
    * **clean.sh**
      * erreurs --> clean_error.log
      * log --> clean.log
	  * utilise des scripts dans lib
	    * **lib/deleteMetadata.py**

Pistes d'évolution
------------------

* l'EPSG est définit par défaut; ce choix est à questionner; autant pour les couches de la métropole française cela peut être utile de les uniformisées en Lambert-93, autant pour les autres, cela est discutable; en fait, ce choix découle de la présence de nombreuses couches faites avec arcgis dont le système de coordonnées est inconnu pour le geoserver; il faut donc convertir ces couches; dans un premier temps, pour résoudre ce problème toutes les couches ont été converties; dans un second temps on pourrait envisager de ne convertir que les couches dont le systèmes de coordonnées est inconnu par le geoserver (couches ESRI arcgis)
* réplication des droits de owncloud au geoserver : owncloud -- ge@sync --> geonetwork; dans le dossier XP se trouvent des essais; oc_share.sh est une expérimentation pour récupérer directement depuis la base de données "à qui est partagé un fichier ?"; ceci est une expérimentation et ne devrait pas être la solution retenue pour la prod; la méthode recommandée consiste à faire un plugin sur le modèle de provisioning API qui expose sous forme de service web les informations de partage; la question à laquelle il doit répondre est : pour tel fichier qui m'est partagé (georchestra-ouvert) à qui d'autres est-il partagé ? ; ensuite  pour répliquer les régles de partage pour le geoserver, il faut écrire dans le fichiers de régles : 1 ligne par partage par personne (role) par couche, sachant qu'il faut créer automatiquement 1 role par groupe, et 1 groupe par personne du LDAP

