#!/bin/bash


# date dans les logs
date >> /var/log/geosync/clean.log
date >> /var/log/geosync/clean_error.log
  
# appel de clean.sh
bash /home/georchestra-ouvert/bin/clean.sh -v -d 1>>/var/log/geosync/clean.log 2>>/var/log/geosync/clean_error.log

# à inclure dans un crontab
# tous les soirs de la semaine à 22h, nettoie le geoserver des couches qui ne sont plus partagées avec lui
# 0 22 * * 1-5   /home/georchestra-ouvert/bin/clean_data.sh

