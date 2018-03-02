#!/usr/bin/python
# -*-coding:Utf-8 -*

# pré-requis : 
# apt install python-owslib python-lxml python-dev libxml2-utils libsaxonb-java

""""""
import os
import sys
import owslib
import requests
from requests.auth import HTTPBasicAuth
from httplib import HTTPConnection

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

    reload(sys)  
    sys.setdefaultencoding('utf8')

    # vérifie l'existence du fichier input
    if not os.path.isfile(input):
        sys.stderr.write("ERROR input file not found : " + input + "\n")
        return

    home = os.environ["HOME"] 

    # création du répertoire temporaire
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
    if not os.path.isfile(xsl_path):
        sys.stderr.write("ERROR xsl file not found : " + xsl_path + "\n")
        return

    #import codecs					
    #file_input = codecs.open(input,'r',encoding='utf-8') # Force la reconnaissance du fichier en utf-8
    file_input = open(input,'r')
    for line in file_input :
        if "<Esri>" in line :
            print "Métadonnée de type ArcGIS à convertir"
            #  utilisation de saxonb pour traduire ArcGIS metadata => iso 19139
            import subprocess
            saxon_input = "-s:" + input
            print str(saxon_input) 
            saxon_xsl = "-xsl:" + xsl_path 
            saxon_output = "-o:" + tmpdir + "/sax_" +  output 
            print str(saxon_output)
            # saxonb-xslt requiert le package libsaxonb-java (apt install libsaxonb-java)
            cmd = "saxonb-xslt", "-ext:on", saxon_input, saxon_xsl, saxon_output
            if verbose:
                print "saxonb cmd :", cmd
            subprocess.call(cmd)
            input = tmpdir + "/sax_" +  output # input = /home/georchestra-ouvert/tmp/geosync_metadata/sax_cc_jura_nord.shp.xml
            print input
            break
    file_input.close() 

    # Add Geoserver link to metadata and delete identifier

    # utilisation de lxml pour récupérer le contenu de la balise resTitle
    from lxml import etree
    tree = etree.parse(input)
    root = tree.getroot()
    resultat = root.xpath('//gmd:title/gco:CharacterString',
                          namespaces={'gmd': 'http://www.isotc211.org/2005/gmd',
                                      'gco': 'http://www.isotc211.org/2005/gco'})
    titre = (resultat)[0]
    print 'titre : ' + titre.text

    # utilisation de minidom pour modifier l'arbre xlm. à refaire avec lxml !!
    from xml.dom import minidom
    doc = minidom.parse(input)
    root = doc.documentElement
    
    line1 = root.firstChild				# Permet d'insérer des balises avec le namespace gmd
    line2 = line1.nextSibling.toprettyxml()		# si le document xml original en contient
    line1 = line1.toprettyxml()				# geonetwork gère bien l'import avec ou sans gmd, du moment
    if ('gmd:' in line1) or ('gmd:' in line2) :		# que le fichier soit cohérent
        #print "Fichier avec gmd"  # GMD : Geographic MetaData extensible markup language
        gmd = 'gmd:'
    else :
        gmd = ''
 
    typename_csw = gmd + 'MD_Metadata'

    balise = gmd + 'fileIdentifier'
    for element in doc.getElementsByTagName(balise):
        #print 'fileIdentifier en cours de suppression'
        doc.documentElement.removeChild(element)

    b_DigitalTransferOptions = gmd + 'MD_DigitalTransferOptions'

    test_digital = doc.getElementsByTagName(b_DigitalTransferOptions)

    if not test_digital :	# creation de l'arborescence nécessaire à la creation de la  balise MD_DigitalTransferOptions
        b_dist = gmd + 'distributionInfo'
        element_dist = doc.createElement(b_dist)
        b_MD_dist = gmd + 'MD_Distribution'
        element_MD_dist = doc.createElement(b_MD_dist)
        b_transfert = gmd + 'transferOptions'
        element_transfert = doc.createElement(b_transfert)
        b_digital = gmd + 'MD_DigitalTransferOptions'
        element_digital = doc.createElement(b_digital)
        for element in doc.getElementsByTagName(typename_csw) : 
            print element.appendChild(element_dist)
            print element_dist.appendChild(element_MD_dist)
            print element_MD_dist.appendChild(element_transfert)
            print element_transfert.appendChild(element_digital)
 
    # AJOUT DES NOEUDS DANS L'ARBRE
    # pour faire apparaître le bouton "Visualiser" dans geonetwork
    # dans <gmd:MD_DigitalTransferOptions>
    # <gmd:onLine>
    #     <gmd:CI_OnlineResource>
    #         <gmd:linkage>
    #             <gmd:URL>https://georchestra-mshe.univ-fcomte.fr/geoserver/ows?SERVICE=WMS&amp;</gmd:URL>
    #         </gmd:linkage>
    #         <gmd:protocol>
    #             <gco:CharacterString>OGC:WMS-1.3.0-http-get-map</gco:CharacterString>
    #         </gmd:protocol>
    #         <gmd:name>
    #             <gco:CharacterString>geosync-restreint:NOM_DE_LA_COUCHE</gco:CharacterString>
    #         </gmd:name>
    #         <gmd:description>
    #             <gco:CharacterString>NOM_DE_LA_COUCHE</gco:CharacterString>
    #         </gmd:description>
    #     </gmd:CI_OnlineResource>
    # </gmd:onLine>

    b_online = gmd + 'onLine'				# creation balise online
    element_online = doc.createElement(b_online)
    b_ressource = gmd + 'CI_OnlineResource'		# creation balise ressource
    element_ressource = doc.createElement(b_ressource)	
    b_linkage = gmd + 'linkage'				# creation balise linkage
    element_linkage = doc.createElement(b_linkage)
    b_url = gmd + 'URL'					# creation et remplissage balise url  
    element_url = doc.createElement(b_url)
    url_wms = url + "/geoserver/ows?SERVICE=WMS&"	# url_wms = https://georchestra-dev.umrthema.univ-fcomte.fr/geoserver/ows?SERVICE=WMS&
    #print url_wms
    element_url_txt = doc.createTextNode(url_wms)
    element_url.appendChild(element_url_txt)
    b_protocol = gmd + 'protocol'				# creation et remplissage balise protocole
    element_protocol = doc.createElement(b_protocol)	
    b_gco = 'gco:CharacterString'
    element_protocol_gco = doc.createElement(b_gco)
    element_protocol.appendChild(element_protocol_gco)
    #element_protocol_txt = doc.createTextNode(u"OGC:WMS-1.3.0-http-get-capabilities")
    element_protocol_txt = doc.createTextNode(u"OGC:WMS-1.3.0-http-get-map")
    element_protocol_gco.appendChild(element_protocol_txt)    
    b_name = gmd + u'name'					# creation et remplissage balise name
    element_name = doc.createElement(b_name)
    b_gco = 'gco:CharacterString'
    element_name_gco = doc.createElement(b_gco)
    element_name.appendChild(element_name_gco)
    name_layer_gs = workspace + ":" + output.split(".")[0]		# name_layer_gs = geosync-restreint:baies_metadata__baies_metadata
    element_name_txt = doc.createTextNode(name_layer_gs)
    element_name_gco.appendChild(element_name_txt)
    b_descr = gmd +'description'				# creation et remplissage balise description
    element_descr = doc.createElement(b_descr)
    b_gco = 'gco:CharacterString'
    #print "b_gco " + b_gco
    element_descr_gco = doc.createElement(b_gco)
    element_descr.appendChild(element_descr_gco)
    element_descr_txt = doc.createTextNode(output.split(".")[0])   #baies_metadata__baies_metadata      #u"baies_metadata__baies_metadataéééééééééé"
    element_descr_gco.appendChild(element_descr_txt)

    #print b_DigitalTransferOptions

#   # affichage du fichier de metadonnées 
#    for element in doc.getElementsByTagName(b_DigitalTransferOptions):
#        print element.appendChild(element_online)
#        print element.toxml()
#        print element_online.appendChild(element_ressource)
#        print element.toxml()
#        print element_ressource.appendChild(element_linkage)
#        print element.toxml()
#        print element_linkage.appendChild(element_url)
#        print element.toxml()
#        print element_ressource.appendChild(element_protocol)
#        print element.toxml()
#        print element_ressource.appendChild(element_name)
#        print element.toxml()
#        print element_ressource.appendChild(element_descr)
#        print element.toxml()

    input_csw = tmpdir + "/csw_" +  output
    output_fic = open(input_csw,'w') 
    txt = doc.toxml().encode('utf-8','ignore')
    output_fic.write(txt)
    output_fic.close()

    # connexion à geonetwork avec la librairie owslib
    from owslib.csw import CatalogueServiceWeb
    url_csw = url + "/geonetwork/srv/fre/csw-publication"
    # Attention : l'utilisateur (login) doit avoir le rôle GN_EDITOR (ou GN_ADMIN) (anciennement SV_EDITOR / SV_ADMIN) voir administration ldap
    ## sinon peut générer l'erreur : lxml.etree.XMLSyntaxError: Opening and ending tag mismatch
    csw = CatalogueServiceWeb(url_csw, skip_caps=True, username=login, password=password)
    
    # suppression des métadonnées relatives à la même couche geoserver
    print "suppression de " + titre.text + " " + name_layer_gs
    from owslib.fes import PropertyIsEqualTo, PropertyIsLike
    myquery = PropertyIsEqualTo('csw:AnyText', name_layer_gs)
    csw.getrecords2(constraints=[myquery], maxrecords=10)
    resultat = csw.results
    #print "resultat : " , resultat 
    for rec in csw.records:
        print "suppression de " + csw.records[rec].title + csw.records[rec].identifier
        csw.transaction(ttype='delete', typename=typename_csw, identifier=csw.records[rec].identifier)
   
    # Transaction: insert
    #print "typename_csw " + typename_csw
    print "input_csw : " + input_csw

    # le fichier de métadonnées est envoyé avec la librairie owslib
    #csw.transaction(ttype='insert', typename=typename_csw, record=open(input_csw).read())
    # problème : les données ne sont alors pas publiques
    # on utilise donc l'API de genonetwork
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
    #print r_post.text
    #print r_post.json()
    content = r_post.json()
    #print(content.keys())
    #print(content[u'metadataInfos'])
    #print(content[u'metadataInfos'].keys())
    identifiant = content[u'metadataInfos'].keys()
    #print identifiant
    #print type(identifiant)
    #print identifiant[0]
    identifiant = identifiant[0]
    #print 'identifiant : ' + identifiant
    print "métadonnées envoyées : " + input_csw

    # modification des privilèges
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
    parser.add_argument('-i',           action="store",      dest="input",              default="geonetwork-record.xml")
    #parser.add_argument('-l',          action="store",      dest="login",              required=True)
    parser.add_argument('-l',           action="store",      dest="login",              default="testadmin")
    #parser.add_argument('-o',           action="store",      dest="output"                 )
    parser.add_argument('-o',           action="store",      dest="output",             default="geonetwork-record.xml")
    #parser.add_argument('-p',          action="store",      dest="password",           required=True)
    parser.add_argument('-p',           action="store",      dest="password",           default="testadmin")
    parser.add_argument('-s',           action="store",      dest="datastore"              )
    parser.add_argument('-u',           action="store",      dest="url",                default="https://georchestra-docker.umrthema.univ-fcomte.fr")
    parser.add_argument('-v',           action="store_true", dest="verbose",            default=False)
    parser.add_argument('-w',           action="store",      dest="workspace",          default="geosync-ouvert")
    parser.add_argument('--db_hostname',action="store",      dest="database_hostname",  default="localhost")

    args = parser.parse_args()
    print parser.parse_args()

    if args.input:
        publish_2_gn(args.input, args.url, args.login, args.password, args.workspace, args.database_hostname, args.verbose)

