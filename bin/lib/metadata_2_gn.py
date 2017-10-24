#!/usr/bin/python
# -*-coding:Utf-8 -*

# pré-requis : apt install python-owslib

""""""
import os
import sys 

def publish_2_gn(input, url, login, password, workspace, database_hostname, verbose):

    from cleanName import cleanName
    import owslib

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

    # aide au diagnostic : vérifie l'existence du fichier input
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

    # aide au diagnostic : vérifie la présence de ArcGIS2ISO19139.xsl
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
    print "titre"
    print titre.text

    # utilisation de minidom pour modifier l'arbre xlm. à refaire avec lxml !!
    from xml.dom import minidom
    doc = minidom.parse(input)
    root = doc.documentElement
    
    line1 = root.firstChild				# Permet d'insérer des balises avec le namespace gmd
    line2 = line1.nextSibling.toprettyxml()		# si le document xml original en contient
    line1 = line1.toprettyxml()				# geonetwork gère bien l'import avec ou sans gmd, du moment
    if ('gmd:' in line1) or ('gmd:' in line2) :		# que le fichier soit cohérent
        print "Fichier avec gmd"  # GMD : Geographic MetaData extensible markup language
        gmd = 'gmd:'
    else :
        gmd = ''
 
    typename_csw = gmd + 'MD_Metadata'

    balise = gmd + 'fileIdentifier'
    for element in doc.getElementsByTagName(balise):
        print 'fileIdentifier en cours de suppression'
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
    print url_wms
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
    print "b_gco " + b_gco
    element_descr_gco = doc.createElement(b_gco)
    element_descr.appendChild(element_descr_gco)
    element_descr_txt = doc.createTextNode(output.split(".")[0])   #baies_metadata__baies_metadata      #u"baies_metadata__baies_metadataéééééééééé"
    element_descr_gco.appendChild(element_descr_txt)

    print b_DigitalTransferOptions
 
    for element in doc.getElementsByTagName(b_DigitalTransferOptions):
        print element.appendChild(element_online)
        print element.toxml()
        print element_online.appendChild(element_ressource)
        print element.toxml()
        print element_ressource.appendChild(element_linkage)
        print element.toxml()
        print element_linkage.appendChild(element_url)
        print element.toxml()
        print element_ressource.appendChild(element_protocol)
        print element.toxml()
        print element_ressource.appendChild(element_name)
        print element.toxml()
        print element_ressource.appendChild(element_descr)
        print element.toxml()

    input_csw = tmpdir + "/csw_" +  output
    output_fic = open(input_csw,'w') 
    txt = doc.toxml().encode('utf-8','ignore')
    output_fic.write(txt)
    output_fic.close()

    # Connect to a CSW, and inspect its properties:
    from owslib.csw import CatalogueServiceWeb
    #csw = CatalogueServiceWeb(url, skip_caps=True, username=login, password=password)
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
    print "resultat : " , resultat 
    for rec in csw.records:
        print "suppression de " + csw.records[rec].title + csw.records[rec].identifier
        csw.transaction(ttype='delete', typename=typename_csw, identifier=csw.records[rec].identifier)
   
    # Transaction: insert
    #typename_csw = gmd + 'MD_Metadata' # FAIT PLUS HAUT, JUSTE APRES DETERMINATION GMD OU PAS
    print "typename_csw " + typename_csw
    print "input_csw " + input_csw

    #import unicodedata
    #acc = open(input_csw).read()
    #acc_8 = acc.decode('utf-8').encode('ascii', 'ignore')	# supprime les caractères avec accents
    #acc_d = acc.decode('utf-8')
    #acc_8 = unicodedata.normalize('NFKD',acc_d).encode('ascii', 'ignore')	# nécessite unicodedata, supprime les accents

    csw.transaction(ttype='insert', typename=typename_csw, record=open(input_csw).read())
    #csw.transaction(ttype='insert', typename=typename_csw, record=acc_8)
    #csw.transaction(ttype='insert', typename='gmd:MD_Metadata', record=open('haies_sans_lien_geoserver.xml').read())

    # Modification des privilèges d'une fiche de metadata pour pouvoir voir sa carte interactive / voir son lien de téléchargement des données :
    # doc : http://geonetwork-opensource.org/manuals/trunk/eng/users/user-guide/publishing/managing-privileges.html
  
    # via l'interface web : https://georchestra-mshe.univ-fcomte.fr/geonetwork/srv/fre/catalog.edit#/board

    # via la base de données (schema geonetwork) :
    # TODO il serait hautement préférable de passer par l'API REST que par la modification de la base de données de geonetwork
    # INSERT INTO geonetwork.operationallowed ( metadataid, groupid, operationid) VALUES ( '[METADATAID]', '1', '[OPERATIONID]');
    # (groupid=1 pour "Tous")
    # * Télécharger (operationid=1)
    # * Carte interactive (operationid=5)

    # Update metadata privilege
    #    sql_req = """set schema 'geonetwork'; 
    #               INSERT INTO operationallowed SELECT 1, metadata.id, 1 FROM metadata WHERE data ILIKE '%" + name_layer_gs + "%' ; 
    #               INSERT INTO operationallowed SELECT 1, metadata.id, 5 FROM metadata WHERE data ILIKE '%" + name_layer_gs + "%' ; 
    #               INSERT INTO operationallowed SELECT 1, metadata.id, 0 FROM metadata WHERE data ILIKE '%" + name_layer_gs + "%' AND NOT EXISTS (SELECT * FROM operationallowed JOIN metadata ON operationallowed.metadataid = metadata.id WHERE data ILIKE '%" + name_layer_gs + "%' AND operationid = 0) ; """ # """ permette l'écriture sur plusieurs lignes"

    # -- attention --
    # la recherche via "data ILIKE '%fouilles_chailluz__pt_limsit_sra%'" peut occasionner des doublons (par exemple avec un nom plus large qui inclut la chaîne cherchée, ou si la fiche de metadata a été duppliquée d'une autre sans être bien modifiée)
    # dans ce cas, produit l'erreur suivante :
    # psql:/tmp/geosync_metadata/update_privilege.sql:1: ERREUR:  la valeur d'une clé dupliquée rompt la contrainte unique « operationallowed_pkey »
    # DÉTAIL : La clé « (groupid, metadataid, operationid)=(1, 485713, 1) » existe déjà.

    # l'erreur psql: fe_sendauth: no password supplied
    # peut être due à une erreur dans le user de la base de données de geonetwork, voir aussi le .pgpass

    sql_req = "set schema 'geonetwork';  INSERT INTO operationallowed SELECT 1, metadata.id, 5 FROM metadata WHERE data ILIKE '%" + name_layer_gs + "%' ; INSERT INTO operationallowed SELECT 1, metadata.id, 0 FROM metadata WHERE data ILIKE '%" + name_layer_gs + "%' AND NOT EXISTS (SELECT * FROM operationallowed JOIN metadata ON operationallowed.metadataid = metadata.id WHERE data ILIKE '%" + name_layer_gs + "%' AND operationid = 0) ; INSERT INTO operationallowed SELECT 1, metadata.id, 1 FROM metadata WHERE data ILIKE '%" + name_layer_gs + "%' ; "

    print sql_req 
    sql_file_name = tmpdir + "/update_privilege.sql"
    sql_file = open(sql_file_name,"w")
    sql_file.write(sql_req)
    sql_file.close()
    os.system("psql -h " + database_hostname + " -d georchestra -U geonetwork -w -a -f " + sql_file_name)


# test de la fonction publish_2_gn
if __name__ == "__main__":

    import argparse

    parser = argparse.ArgumentParser(add_help=True)
    #parser.add_argument('-i',          action="store",      dest="input",              required=True)
    parser.add_argument('-i',           action="store",      dest="input",              default="metadata_no_uid.xml")
    #parser.add_argument('-l',          action="store",      dest="login",              required=True)
    parser.add_argument('-l',           action="store",      dest="login",              default="admin")
    parser.add_argument('-o',           action="store",      dest="output"                 )
    #parser.add_argument('-p',          action="store",      dest="password",           required=True)
    parser.add_argument('-p',           action="store",      dest="password",           default="admin")
    parser.add_argument('-s',           action="store",      dest="datastore"              )
    parser.add_argument('-u',           action="store",      dest="url",                default="http://geonetwork-mshe.univ-fcomte.fr:8080/geonetwork/srv/fre/csw-publication")
    parser.add_argument('-v',           action="store_true", dest="verbose",            default=False)
    parser.add_argument('-w',           action="store",      dest="workspace",          default="geosync-ouvert")
    parser.add_argument('--db_hostname',action="store",      dest="database_hostname",  default="localhost")

    args = parser.parse_args()
    print parser.parse_args()

    if args.input:
        publish_2_gn(args.input, args.url, args.login, args.password, args.workspace, args.database_hostname, args.verbose)

