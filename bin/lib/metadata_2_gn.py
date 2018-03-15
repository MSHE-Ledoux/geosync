#!/usr/bin/python
# -*-coding:Utf-8 -*

# pré-requis : 
# apt install python-owslib python-lxml python-dev libxml2-utils libsaxonb-java

# objectif : envoyer le fichier de métadonnées xml au GeoNetwork
# on modifie le fichier xml à la volée pour lui ajouter des balises xml
#
# 1) pour faire apparaître le bouton "Visualiser" dans GeoNetwork, on ajoute les balises suivantes dans <gmd:MD_DigitalTransferOptions>
#
#  <gmd:distributionInfo>
#    <gmd:MD_Distribution>
#      <gmd:transferOptions>
#        <gmd:MD_DigitalTransferOptions>
#          <gmd:onLine>
#            <gmd:CI_OnlineResource>
#              <gmd:linkage>
#                <gmd:URL>https://georchestra-mshe.univ-fcomte.fr/geoserver/ows?SERVICE=WMS&amp;</gmd:URL>
#              </gmd:linkage>
#              <gmd:protocol>
#                <gco:CharacterString>OGC:WMS-1.3.0-http-get-map</gco:CharacterString>
#              </gmd:protocol>
#              <gmd:name>
#                <gco:CharacterString>geosync-restreint:NOM_DE_LA_COUCHE</gco:CharacterString>
#              </gmd:name>
#              <gmd:description>
#                <gco:CharacterString>NOM_DE_LA_COUCHE</gco:CharacterString>
#              </gmd:description>
#            </gmd:CI_OnlineResource>
#          </gmd:onLine>
#        </gmd:MD_DigitalTransferOptions>
#
# 2) on ajoute également un uuid au fichier, dans la balise gmd:fileIdentifier
#
#  <gmd:fileIdentifier><
#    gco:CharacterString>8349df1c-1ebd-4734-9b69-1efd60a43b33</gco:CharacterString>
#  </gmd:fileIdentifier>
#

import os
import sys
import owslib
import requests
import uuid
import shutil
from   requests.auth import HTTPBasicAuth
from   httplib       import HTTPConnection
from   lxml          import etree
from   xml.dom       import minidom

def publish_2_gn(input, url, login, password, workspace, database_hostname, verbose):

    from cleanName import cleanName

    output = cleanName(input, True)
    
    if verbose:
        print "input     : ", input
        print "output    : ", output
        print "url       : ", url
        print "login     : ", login
        print "password  : ", password
        print "workspace : ", workspace
        print "dbhost    : ", database_hostname

    # https://stackoverflow.com/questions/3828723/why-should-we-not-use-sys-setdefaultencodingutf-8-in-a-py-script/34378962
    # il serait préférable de positionner correctement la variable d'environnement PYTHONIOENCODING="UTF-8"
    reload(sys)  
    sys.setdefaultencoding('utf8')

    # vérifie l'existence du fichier d'entrée, au format xml, qui contient les métadonnées à envoyer à GeoNetwork
    if not os.path.isfile(input):
        sys.stderr.write("ERROR input file not found : " + input + "\n")
        return

    home = os.environ["HOME"] 

    # on affiche dans les commentaires le nom de la couche associée à la métadonnée
    # name_layer_gs = geosync-restreint:baies_metadata__baies_metadata
    name_layer_gs = workspace + ":" + output.split(".")[0]

    # création d'un répertoire temporaire pour y enregistrer le fichier de travail
    tmpdir = home + "/tmp/geosync_metadata"
    if os.path.exists(tmpdir):
        import shutil
        shutil.rmtree(tmpdir,True) # ignore_errors
        try:
            os.mkdir(tmpdir)
        except OSError as e:
            if e.errno != errno.EEXIST:
                #sys.stderr.write("erreur lors de la création de tmpdir"+ tmpdir +"\n")
                raise  # raises the error again
    else :
        os.mkdir(tmpdir) 

    # Translate Esri metadata to ISO19139

    # vérifie la présence de ArcGIS2ISO19139.xsl
    script_path = os.path.dirname(os.path.abspath(__file__))
    xsl_path = script_path + "/ArcGIS2ISO19139.xsl"
    if not os.path.isfile(xsl_path) :
        sys.stderr.write("ERROR xsl file not found : " + xsl_path + "\n")
        return

    # import des codecs pour les fichiers ArcGIS
    # à améliorer : le nom du fichier input est renommé dans la boucle de lecture du fichier
    initial_file_name = input
    no_change = True
    # recherche de la base Esri
    tree = etree.parse(input)
    xpath_esri = tree.xpath('Esri')
    if xpath_esri :
        print "Métadonnée de type ArcGIS à convertir en ISO 19139"
        # utilisation de saxonb pour traduire ArcGIS metadata => iso 19139
        import subprocess
        saxon_input  = "-s:" + input
        print str(saxon_input) 
        saxon_xsl    = "-xsl:" + xsl_path 
        saxon_output = "-o:" + tmpdir + "/sax_" +  output 
        print str(saxon_output)
        cmd = "saxonb-xslt", "-ext:on", saxon_input, saxon_xsl, saxon_output
        if verbose:
            print "saxonb cmd :", cmd
        subprocess.call(cmd)
        input = tmpdir + "/sax_" +  output
        print "input : " + input
        no_change = False
    else :
        print "pas de conversion saxonb-xslt"

    # Add Geoserver link to metadata and generate UUID

    # utilisation de lxml pour récupérer le contenu de la balise gmd:title
    # exemple :
    #      <gmd:title>
    #        <gco:CharacterString>Haies de Franche-Comté en 2010</gco:CharacterString>
    #      </gmd:title>
    # question : pourrait-on avoir une balise title sans gmd et/ou sans gco ?
    # oui, ça marche aussi avec
    #      <title>
    #        <gco:CharacterString>Haies_Besancon_ouest</gco:CharacterString>
    #      </title>

    # recherche de la balise title
    tree = etree.parse(input)
    xpath_title = tree.xpath('//gmd:title/gco:CharacterString',
                             namespaces={'gmd': 'http://www.isotc211.org/2005/gmd',
                                         'gco': 'http://www.isotc211.org/2005/gco'})
    # quand il y a plusieurs balises gmd:title, on obtient un tableau de titres
    titre = ''
    i = 0
    if len(xpath_title) :
        for title in xpath_title :
            i += 1
            titre = titre + str(title.text)
            print "titre " + str(i) + " : " + str(title.text)
    else :
       print "balise gmd:title non trouvée"
       titre = 'sans titre'

    # utilisation de minidom pour lire et modifier l'arbre xlm
    # tutoriel minidom : http://www.fil.univ-lille1.fr/~marvie/python/chapitre4.html
    # à refaire éventuellement avec lxml
    doc = minidom.parse(input)
    element = doc.documentElement

    # à quel type de fichier de métadonnées avons-nous à faire ? 
    # typiquement on a une balise principale qui peut être l'une 3 balises suivantes :
    # - <metadata...>
    # - <MD_Metadata...>
    # - <gmd:MD_Metadata...
    # objectif : insérer des balises avec le namespace gmd si le document xml original en contient
    # GeoNetwork gère bien l'import avec ou sans gmd, dès lors que le fichier est cohérent
    # GMD : Geographic MetaData extensible markup language
    type_csw = doc.firstChild.tagName
    print "type_csw : " + type_csw
    # on positionne dans une variable la présence des préfixes gmd:
    if ('gmd:' in type_csw) :
        gmd = 'gmd:'
    else :
        gmd = ''

    # recherche de la balise gmd:fileIdentifier
    # on recherche d'abord toutes les balises gco:CharacterString et on s'arrête quand le parent est une balise gmd:fileIdentifier ou fileIdentifier
    balise = 'gco:CharacterString'

    fileIdentifier = False
    for element in doc.getElementsByTagName(balise):
        # si la balise gmd:fileIdentifier existe déjà
        b_file = gmd + "fileIdentifier"
	if b_file in str(element.parentNode):
	    fileIdentifier = True
	    print "fileIdentifier trouvé : " + element.firstChild.nodeValue

    # si la balise gmd:fileIdentifier n'existe pas, alors on la créée, avec un nouvel uuid
    if not fileIdentifier :
        print "création à la volée d'un identifiant"
        b_file = gmd + 'fileIdentifier'
        element_file = doc.createElement(b_file)
        b_gco = 'gco:CharacterString'
        element_file_gco = doc.createElement(b_gco)
        element_file.appendChild(element_file_gco)
	# https://stackoverflow.com/questions/534839/how-to-create-a-guid-uuid-in-python
        file_txt = str(uuid.uuid4())
        element_file_txt = doc.createTextNode(file_txt)
        element_file_gco.appendChild(element_file_txt)
        print "insertion de la balise fileIdentifier dans l'arbre"
        for element in doc.getElementsByTagName(type_csw) :
            element.appendChild(element_file)
        if no_change :
            no_change = False

    # recherche de la balise gmd:URL avec lxml
    # tutoriel : http://lxml.de/tutorial.html
    # même remarque : on suppose que toutes les balises contiennent gmd:
    lien_existant = False
    xpath_url = tree.xpath('//gmd:distributionInfo/gmd:MD_Distribution/gmd:transferOptions/gmd:MD_DigitalTransferOptions/gmd:onLine/gmd:CI_OnlineResource/gmd:linkage/gmd:URL',
                           namespaces={'gmd': 'http://www.isotc211.org/2005/gmd',
                                       'gco': 'http://www.isotc211.org/2005/gco'})
    #print "xpath_url : " + str(xpath_url)
    # on obtient un tableau quand il y a plusieurs url
    if len(xpath_url) :
        for xurl in xpath_url :
            print str(xurl.text)
            # le lien vers le geoserver existe-t-il déjà ?
            # à améliorer pour éviter les redondances de liens dev/test/prod
            if url in xurl.text :
                lien_existant = True
                print "le lien vers " + url + " est déjà positionné"

    if not lien_existant :
        # si le lien vers le geoserver n'existe pas, on doit le créer.
        # mais est-ce que la balise MD_DigitalTransferOptions existe déjà ?
        # si elle n'existe pas, alors on la créée

        # recherche de la balise MD_DigitalTransferOptions avec minidom
        b_DigitalTransferOptions = gmd + 'MD_DigitalTransferOptions'
        test_digital = doc.getElementsByTagName(b_DigitalTransferOptions)

        # création de l'arborescence nécessaire à la création de la balise MD_DigitalTransferOptions
        if test_digital :
            print "balise MD_DigitalTransferOptions trouvée"
        else :
            print "pas de balise MD_DigitalTransferOptions"
            # donc création des 4 balises xml imbriquées :
            # gmd:distributionInfo / gmd:MD_Distribution / gmd:transferOptions / gmd:MD_DigitalTransferOptions"

            b_dist = gmd + 'distributionInfo'
            element_dist = doc.createElement(b_dist)
            b_MD_dist = gmd + 'MD_Distribution'
            element_MD_dist = doc.createElement(b_MD_dist)
            b_transfert = gmd + 'transferOptions'
            element_transfert = doc.createElement(b_transfert)
            b_digital = gmd + 'MD_DigitalTransferOptions'
            element_digital = doc.createElement(b_digital)

            print "insertion des balises dans l'arbre des 4 balises"
            for element in doc.getElementsByTagName(type_csw) : 
                element.appendChild(element_dist)
                element_dist.appendChild(element_MD_dist)
                element_MD_dist.appendChild(element_transfert)
                element_transfert.appendChild(element_digital)
 
        # la balise gmd:MD_DigitalTransferOptions existait déjà
        # on lui rajoute un lien vers notre geoserver

        # création balise online
        b_online = gmd + 'onLine'
        element_online = doc.createElement(b_online)

        # création balise ressource
        b_ressource = gmd + 'CI_OnlineResource'
        element_ressource = doc.createElement(b_ressource)	

        # création balise linkage
        b_linkage = gmd + 'linkage'
        element_linkage = doc.createElement(b_linkage)

        # création et remplissage balise url
        b_url = gmd + 'URL' 
        element_url = doc.createElement(b_url)
        url_wms = url + "/geoserver/ows?SERVICE=WMS&"
        element_url_txt = doc.createTextNode(url_wms)
        element_url.appendChild(element_url_txt)

        # création et remplissage balise protocole
        b_protocol = gmd + 'protocol'	
        element_protocol = doc.createElement(b_protocol)	
        b_gco = 'gco:CharacterString'
        element_protocol_gco = doc.createElement(b_gco)
        element_protocol.appendChild(element_protocol_gco)
        #element_protocol_txt = doc.createTextNode(u"OGC:WMS-1.3.0-http-get-capabilities")
        element_protocol_txt = doc.createTextNode(u"OGC:WMS-1.3.0-http-get-map")
        element_protocol_gco.appendChild(element_protocol_txt)        

        # création et remplissage balise name
        b_name = gmd + u'name'
        element_name = doc.createElement(b_name)
        b_gco = 'gco:CharacterString'
        element_name_gco = doc.createElement(b_gco)
        element_name.appendChild(element_name_gco)

        # création et remplissage balise name_layer_gs qui contient le nom de la couche geoserver
        # name_layer_gs est initialisée en début de procédure
        element_name_txt = doc.createTextNode(name_layer_gs)
        element_name_gco.appendChild(element_name_txt)

        # création et remplissage balise description
        b_descr = gmd +'description'
        element_descr = doc.createElement(b_descr)
        b_gco = 'gco:CharacterString'
        element_descr_gco = doc.createElement(b_gco)
        element_descr.appendChild(element_descr_gco)
        element_descr_txt = doc.createTextNode(output.split(".")[0])
        element_descr_gco.appendChild(element_descr_txt)

        # une fois créé, chaque élément est inséré dans l'arbre
        # la fonction print sert à l'affichage à la console
        for element in doc.getElementsByTagName(b_DigitalTransferOptions):
            element.appendChild(element_online)
            #print element.toxml()
            element_online.appendChild(element_ressource)
            #print element.toxml()
            element_ressource.appendChild(element_linkage)
            #print element.toxml()
            element_linkage.appendChild(element_url)
            #print element.toxml()
            element_ressource.appendChild(element_protocol)
            #print element.toxml()
            element_ressource.appendChild(element_name)
            #print element.toxml()
            element_ressource.appendChild(element_descr)
            #print element.toxml()

        if no_change :
            no_change = False

    # le fichier est écrit dans le répertoire temporaire
    input_csw = tmpdir + "/csw_" +  output
    input_csw_fic = open(input_csw,'w') 
    txt = doc.toxml().encode('utf-8','ignore')
    input_csw_fic.write(txt)
    input_csw_fic.close()

    # le fichier transformé est copié dans le répertoire de partage owncloud, à son emplacement initial, 
    # de manière à retourner vers l'utilisateur... 
    # attention aux boucles qui consisteraient à modifier systématiquement le fichier
    rep = os.path.dirname(initial_file_name)
    fic = os.path.basename(initial_file_name)
    #print "rep : " + rep + " fic : " + fic
    #output_csw = rep + "/csw_" +  output
    print "input_csw         : " + input_csw 
    print "initial_file_name : " + initial_file_name
    # s'il n'y a eu aucune modification, on ne copie pas le fichier
    if not no_change :
        shutil.copyfile(input_csw, initial_file_name)

    # connexion à GeoNetwork avec la librairie owslib
    from owslib.csw import CatalogueServiceWeb
    url_csw = url + "/geonetwork/srv/fre/csw-publication"
    # Attention : l'utilisateur (login) doit avoir le rôle GN_EDITOR (ou GN_ADMIN) voir administration ldap
    ## sinon peut générer l'erreur : lxml.etree.XMLSyntaxError: Opening and ending tag mismatch
    csw = CatalogueServiceWeb(url_csw, skip_caps=True, username=login, password=password)
    
    # suppression des métadonnées relatives à la même couche geoserver
    print "suppression de " + titre + " " + name_layer_gs
    from owslib.fes import PropertyIsEqualTo, PropertyIsLike
    myquery = PropertyIsEqualTo('csw:AnyText', name_layer_gs)
    csw.getrecords2(constraints=[myquery], maxrecords=10)
    resultat = csw.results
    #print "resultat : " , resultat 
    for rec in csw.records:
        print "suppression de " + csw.records[rec].title + csw.records[rec].identifier
        csw.transaction(ttype='delete', typename=type_csw, identifier=csw.records[rec].identifier)
   
    # Transaction: insert
    #print "type_csw " + type_csw
    print "input_csw : " + input_csw

    # le fichier de métadonnées pourrait être envoyé avec la librairie owslib, si ça marchait bien.
    # csw.transaction(ttype='insert', typename=type_csw, record=open(input_csw).read())
    # mais problème : les données ne sont pas publiques qiand elles sont envoyées avec owslib
    # on utilise donc l'API de GeoNetwork
    # https://georchestra-mshe.univ-fcomte.fr/geonetwork/doc/api/

    HTTPConnection.debuglevel = 0

    # ouverture de session
    geonetwork_session = requests.Session()
    geonetwork_session.auth = HTTPBasicAuth(login, password)
    geonetwork_session.headers.update({"Accept" : "application/xml"})

    # 1er POST, pour récupérer le token xsrf
    geonetwork_url = url + '/geonetwork/srv/eng/info?type=me'
    r_post = geonetwork_session.post(geonetwork_url)

    # prise en compte du token xsrf
    # https://geonetwork-opensource.org/manuals/trunk/eng/users/customizing-application/misc.html
    token = geonetwork_session.cookies.get('XSRF-TOKEN')
    geonetwork_session.headers.update({"X-XSRF-TOKEN" : geonetwork_session.cookies.get('XSRF-TOKEN')})

    # envoi du fichier de métadonnées
    geonetwork_post_url = url + '/geonetwork/srv/api/0.1/records?uuidProcessing=OVERWRITE'
    files = {'file': (input_csw, open(input_csw,'rb'), 'application/xml', {'Expires': '0'})}
    geonetwork_session.headers.update({"Accept" : "application/json"})
    r_post = geonetwork_session.post(geonetwork_post_url, files=files)
    content = r_post.json()
    identifiant = content[u'metadataInfos'].keys()
    identifiant = identifiant[0]
    print "métadonnées envoyées : " + input_csw

    # modification des privilèges de la métadonnée qu'on vient d'insérer dans GeoNetwork
    # Attention : l'utilisateur (login) doit avoir le rôle GN_ADMIN. voir administration ldap
    data_privilege = '{ "clear": true, "privileges": [ {"operations":{"view":true,"download":false,"dynamic":false,"featured":false,"notify":false,"editing":false},"group":-1}, {"operations":{"view":true,"download":false,"dynamic":false,"featured":false,"notify":false,"editing":false},"group":0}, {"operations":{"view":true,"download":false,"dynamic":false,"featured":false,"notify":false,"editing":false},"group":1} ] }'
    geonetwork_session.headers.update({"Accept" : "*/*"})
    geonetwork_session.headers.update({"Content-Type" : "application/json"})
    geonetwork_session.headers.update({"X-XSRF-TOKEN" : token})
    geonetwork_put_url = url + '/geonetwork/srv/api/0.1/records/' + identifiant + '/sharing'
    print geonetwork_put_url
    r_put = geonetwork_session.put(geonetwork_put_url, data=data_privilege)
    print r_put.text
    print "métadonnées rendues publiques"

# test de la fonction publish_2_gn
if __name__ == "__main__":

    import argparse

    parser = argparse.ArgumentParser(add_help=True)
    #parser.add_argument('-i',          action="store",      dest="input",              required=True)
    #parser.add_argument('-i',           action="store",      dest="input",              default="metadata.xml")
    #parser.add_argument('-i',           action="store",      dest="input",              default="200_metadata_xml_QGIS_gmd.xml")
    #parser.add_argument('-i',           action="store",      dest="input",              default="haies_sans_lien_geoserver.xml")
    parser.add_argument('-i',           action="store",      dest="input",              default="Haies_Besancon_ouest.shp.xml")
    #parser.add_argument('-i',           action="store",      dest="input",              default="haies_avec_lien_geoserver.xml")
    #parser.add_argument('-i',           action="store",      dest="input",              default="haies_avec_deux_liens_geoserver.xml")
    #parser.add_argument('-i',           action="store",      dest="input",              default="geonetwork-record.xml")
    #parser.add_argument('-l',          action="store",      dest="login",              required=True)
    parser.add_argument('-l',           action="store",      dest="login",              default="testadmin")
    #parser.add_argument('-o',           action="store",      dest="output"                 )
    #parser.add_argument('-o',           action="store",      dest="output",             default="metadata.xml")
    #parser.add_argument('-o',           action="store",      dest="output",             default="200_metadata_xml_QGIS_gmd.xml")
    #parser.add_argument('-o',           action="store",      dest="output",             default="haies_sans_lien_geoserver.xml")
    parser.add_argument('-o',           action="store",      dest="output",             default="Haies_Besancon_ouest.shp.xml")
    #parser.add_argument('-o',           action="store",      dest="output",             default="haies_avec_lien_geoserver.xml")
    #parser.add_argument('-o',           action="store",      dest="output",             default="haies_avec_deux_liens_geoserver.xml")
    #parser.add_argument('-o',           action="store",      dest="output",             default="geonetwork-record.xml")
    #parser.add_argument('-p',          action="store",      dest="password",           required=True)
    parser.add_argument('-p',           action="store",      dest="password",           default="testadmin")
    parser.add_argument('-s',           action="store",      dest="datastore"              )
    parser.add_argument('-u',           action="store",      dest="url",                default="https://georchestra-docker.umrthema.univ-fcomte.fr")
    parser.add_argument('-v',           action="store_true", dest="verbose",            default=True)
    parser.add_argument('-w',           action="store",      dest="workspace",          default="geosync-ouvert")
    parser.add_argument('--db_hostname',action="store",      dest="database_hostname",  default="localhost")

    args = parser.parse_args()
    print parser.parse_args()

    if args.input:
        publish_2_gn(args.input, args.url, args.login, args.password, args.workspace, args.database_hostname, args.verbose)

