#!/usr/bin/python
# -*-coding:Utf-8 -*

# pré-requis : apt install python-owslib

""""""

def publish_2_gn(input, url, login, password, workspace, verbose):

    from cleanName import cleanName
    import owslib

    print "dans metadata.publish_2_gn"

    print "Travail de CleanName.py"
    output = cleanName(input, True)
    print "Fin de CleanName.py"
    
    if verbose:
      print "input : ", input
      print "output : ", output
      print "url : ", url
      print "login : ", login
      print "password : ", password
    

    import os
    home = os.environ["HOME"] # home = /home/georchestra-ouvert

    input = home + "/owncloudsync/" + input  
    #print input   

    import sys  
    reload(sys)  
    sys.setdefaultencoding('utf8')


    # création du répertoire temporaire
    tmpdir = home + "/tmp/geosync_metadata"
    if os.path.exists(tmpdir):
    	import shutil
        shutil.rmtree(tmpdir)
        os.mkdir(tmpdir)

    # Translate Esri metadata to ISO19139

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
            saxon_xsl = "-xsl:" + home + "/bin/lib/ArcGIS2ISO19139.xsl"
            saxon_output = "-o:" + tmpdir + "/sax_" +  output 
            print str(saxon_output)
            subprocess.call(["saxonb-xslt", "-ext:on", saxon_input, saxon_xsl, saxon_output])
	    input = tmpdir + "/sax_" +  output # input = /home/georchestra-ouvert/tmp/geosync_metadata/sax_cc_jura_nord.shp.xml
            print input
            break
    file_input.close() 



    # Add Geoserver link to metadata and delete identifier

    from xml.dom import minidom
    doc = minidom.parse(input)
   
    root = doc.documentElement
    
    line1 = root.firstChild				# Permet d'insérer des balises avec le namespace gmd
    line2 = line1.nextSibling.toprettyxml()		# si le document xml original en contient
    line1 = line1.toprettyxml()				# GN gère bien l'import avec ou sans gmd, du moment
    if ('gmd:' in line1) or ('gmd:' in line2) :		# que le fichier soit cohérent
        print "Fichier avec gmd"  
	gmd = 'gmd:'
    else :
	gmd = ''
 
    typename_csw = gmd + 'MD_Metadata'

    balise = gmd + 'fileIdentifier'
    for element in doc.getElementsByTagName(balise):
        print 'fileIdentifier en cours de suppression'
        doc.documentElement.removeChild(element)

    balise = gmd + 'MD_DigitalTransferOptions'

    test_digital = doc.getElementsByTagName(balise)

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
 
        # AJOUT DES NOEUDS DANS L'ARBRE !!!!




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
    element_descr_gco = doc.createElement(b_gco)
    element_descr.appendChild(element_descr_gco)
    element_descr_txt = doc.createTextNode(output.split(".")[0])   #baies_metadata__baies_metadata      #u"baies_metadata__baies_metadataéééééééééé"
    element_descr_gco.appendChild(element_descr_txt)

    print balise
 
    for element in doc.getElementsByTagName(balise):
        print element.appendChild(element_online)
	print element_online.appendChild(element_ressource)
	print element_ressource.appendChild(element_linkage)
	print element_linkage.appendChild(element_url)
	print element_ressource.appendChild(element_protocol)
	print element_ressource.appendChild(element_name)
	print element_ressource.appendChild(element_descr)
	
    input_csw = tmpdir + "/csw_" +  output
    print input_csw
    output_fic = open(input_csw,'w') 
    #output_fic.write('essai')
    txt = doc.toxml().encode('utf-8','ignore')
    output_fic.write(txt)
    output_fic.close()

    # Connect to a CSW, and inspect its properties:
    from owslib.csw import CatalogueServiceWeb
    #csw = CatalogueServiceWeb(url, skip_caps=True, username=login, password=password)
    url_csw = url + "/geonetwork/srv/fre/csw-publication"
    csw = CatalogueServiceWeb(url_csw, skip_caps=True, username=login, password=password)
    #csw = CatalogueServiceWeb('https://georchestra-dev.umrthema.univ-fcomte.fr/geonetwork/srv/fre/csw-publication', skip_caps=True, username='testadmin', password='testadmin')
    
    # suppression des métadonnées relatives à la même couche geoserver
    from owslib.fes import PropertyIsEqualTo, PropertyIsLike
    myquery = PropertyIsEqualTo('csw:AnyText',name_layer_gs)
    csw.getrecords2(constraints=[myquery], maxrecords=10)
    resultat = csw.results
    print "resultat : " , resultat 
    for rec in csw.records:
        print "suppression de " + csw.records[rec].title + csw.records[rec].identifier
        csw.transaction(ttype='delete', typename=typename_csw, identifier=csw.records[rec].identifier)
   
    # Transaction: insert
    #typename_csw = gmd + 'MD_Metadata' # FAIT PLUS HAUT, JUSTE APRES DETERMINATION GMD OU PAS
    #print typename_csw
    print input_csw


    #import unicodedata
    #acc = open(input_csw).read()
    #acc_8 = acc.decode('utf-8').encode('ascii', 'ignore')	# supprime les caractères avec accents
    #acc_d = acc.decode('utf-8')
    #acc_8 = unicodedata.normalize('NFKD',acc_d).encode('ascii', 'ignore')	# nécessite unicodedata, supprime les accents

    csw.transaction(ttype='insert', typename=typename_csw, record=open(input_csw).read())
    #csw.transaction(ttype='insert', typename=typename_csw, record=acc_8)
    #csw.transaction(ttype='insert', typename='gmd:MD_Metadata', record=open('haies_sans_lien_geoserver.xml').read())


    #---------TEST UPDATE PRIVILEGE-----
    sql_req = "set schema 'geonetwork'; INSERT INTO operationallowed SELECT 1, metadata.id, 1 FROM metadata WHERE data ILIKE '%" + name_layer_gs + "%' ; \n INSERT INTO operationallowed SELECT 1, metadata.id, 5 FROM metadata WHERE data ILIKE '%" + name_layer_gs + "%' ;"
    sql_file = open("update_privilege.sql","w")
    sql_file.write(sql_req)
    sql_file.close()
    os.system("psql -h localhost -d georchestra -U geosync -a -f update_privilege.sql")



# test de la fonction publish_2_gn
if __name__ == "__main__":

    import argparse

    parser = argparse.ArgumentParser(add_help=True)
    #parser.add_argument('-i', action="store",      dest="input",    required=True)
    parser.add_argument('-i', action="store",      dest="input",    default="metadata_no_uid.xml")
    #parser.add_argument('-l', action="store",      dest="login",    required=True)
    parser.add_argument('-l', action="store",      dest="login",    default="admin")
    parser.add_argument('-o', action="store",      dest="output"                 )
    #parser.add_argument('-p', action="store",      dest="password", required=True)
    parser.add_argument('-p', action="store",      dest="password", default="admin")
    parser.add_argument('-s', action="store",      dest="datastore"              )
    parser.add_argument('-u', action="store",      dest="url"     , default="http://geonetwork-mshe.univ-fcomte.fr:8080/geonetwork/srv/fre/csw-publication")
    parser.add_argument('-v', action="store_true", dest="verbose",  default=False)
    parser.add_argument('-w', action="store",      dest="workspace", default="geosync-ouvert")

    args = parser.parse_args()
    print parser.parse_args()


    if args.input:
        publish_2_gn(args.input, args.url, args.login, args.password, args.workspace, args.verbose)

