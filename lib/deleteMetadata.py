#!/usr/bin/python
# -*-coding:Utf-8 -*

"""module contenant deleteMetadata"""


def deleteMetadata(name, login, password, url, workspace):
    #takes a keyword and delete metadata associated

    import os
    import re

    print "url : ", url
    url_csw = url + "/geonetwork/srv/fre/csw-publication"    
    print url_csw
    print "name : ", name
    keyword = workspace + ":" + name              # keyword = geosync-restreint:baies_metadata__baies_metadata
    print keyword 

    # Connect to a CSW, and inspect its properties:
    from owslib.csw import CatalogueServiceWeb
    csw = CatalogueServiceWeb(url_csw, skip_caps=True, username=login, password=password)
    # suppression des métadonnées relatives à "keyword" / couche geoserver
    from owslib.fes import PropertyIsEqualTo, PropertyIsLike
    myquery = PropertyIsEqualTo('csw:AnyText',keyword)
    csw.getrecords2(constraints=[myquery], maxrecords=10)
    resultat = csw.results
    print "resultat : " , resultat
    global result
    result = "toto"
    for rec in csw.records:
        try:
            csw.transaction(ttype='delete', typename='MD_Metadata', identifier=csw.records[rec].identifier) #marche apparement pour les metadonnees étant de type gmd:MD_Metadata
            result = "Métadonnée associée à ${keyword} supprimée"
            print "suppression de " + csw.records[rec].title + csw.records[rec].identifier	#genere une erreur si titre vide ou pas d'identifiant
        except:

            result = "erreur !"

    return result


# test de la fonction deleteMetadata 
if __name__ == "__main__":

    import argparse

    parser = argparse.ArgumentParser(add_help=True)

    parser.add_argument("-i", "--name", action="store"  ,    dest="name", required=True)
    parser.add_argument('-l', action="store",      dest="login",    required=True)
    parser.add_argument('-p', action="store",      dest="password", required=True)
    parser.add_argument("-u", "--url",  action="store", dest="url" , required=True)
    parser.add_argument("-w", "--workspace", action="store", dest="workspace", required="True")
    args = parser.parse_args()

    print parser.parse_args()

    if args.url:
        deleteMetadata(args.name, args.login, args.password, args.url, args.workspace)

