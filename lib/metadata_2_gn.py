#!/usr/bin/python
# -*-coding:Utf-8 -*

# pré-requis : apt install python-owslib

""""""

def publish_2_gn(input, url, login, password):

    from cleanName import cleanName
    import owslib

    print "dans metadata.publish_2_gn"

    output = cleanName(input, True)
    print "input : ", input
    print "output : ", output
    print "url : ", url
    print "login : ", login
    print "password : ", password

    import os
    home = os.environ["HOME"] # home = /home/georchestra-ouvert

    #import sys  
    #reload(sys)  
    #sys.setdefaultencoding('utf8')

    # Translate Esri metadata to ISO19139

    file_input = open(input, "r")
    for line in file_input :
        if "<Esri>" in line :
            print "Métadonnée de type ArcGIS à convertir"
            # création du répertoire temporaire
            tmpdir = home + "/tmp/geosync_metadata"
            if os.path.exists(tmpdir):
                import shutil
                shutil.rmtree(tmpdir)
            os.mkdir(tmpdir)
            #  utilisation de saxonb pour traduire ArcGIS metadata => iso 19139
            import subprocess
            saxon_input = "-s:" + input
            print str(saxon_input) 
            saxon_output = "-o:" + tmpdir + "/" +  input
            print str(saxon_output)
            subprocess.call(["saxonb-xslt", "-ext:on", saxon_input, "-xsl:./ArcGIS2ISO19139.xsl", saxon_output])
            input = tmpdir + "/" +  input # input = /home/georchestra-ouvert/tmp/geosync_metadata/cc_jura_nord.shp.xml
            break
    file_input.close() 

    # Connect to a CSW, and inspect its properties:
    from owslib.csw import CatalogueServiceWeb
    #csw = CatalogueServiceWeb(url, skip_caps=True, username=login, password=password)
    csw = CatalogueServiceWeb(url, skip_caps=True, username='admin', password='admin')
    #csw = CatalogueServiceWeb('https://georchestra-dev.umrthema.univ-fcomte.fr/geonetwork/srv/fre/csw-publication', skip_caps=True, username='testadmin', password='testadmin')

    # Transaction: insert
    #csw.transaction(ttype='insert', typename='gmd:MD_Metadata', record=open(input).read())
    csw.transaction(ttype='insert', typename='gmd:MD_Metadata', record=open('Haies_Franche_Comte_metadata.xml').read())

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
    parser.add_argument('-w', action="store",      dest="workspace"              )

    args = parser.parse_args()
    print parser.parse_args()

    if args.input:
        publish_2_gn(args.input, args.url, args.login, args.password)

