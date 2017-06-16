#!/usr/bin/python
# -*-coding:Utf-8 -*

import owslib

# Connect to a CSW, and inspect its properties:
from owslib.csw import CatalogueServiceWeb
csw = CatalogueServiceWeb('https://georchestra-docker.umrthema.univ-fcomte.fr/geonetwork/srv/fre/csw')
csw.identification.type
[op.name for op in csw.operations]

# Get supported resultType’s:
csw.getdomain('GetRecords.resultType')
csw.results
{'values': ['results', 'validate', 'hits'], 'parameter': 'GetRecords.resultType', 'type': 'csw:DomainValuesType'}

# Search for dublin data:
from owslib.csw import CatalogueServiceWeb
csw = CatalogueServiceWeb('https://georchestra-docker.umrthema.univ-fcomte.fr/geonetwork/srv/fre/csw-publication', skip_caps=True, username='testadmin', password='testadmin')

from owslib.fes import PropertyIsEqualTo, PropertyIsLike
name_layer_gs="210"

myquery = PropertyIsLike('csw:AnyText',name_layer_gs)
csw.getrecords2(constraints=[myquery], maxrecords=10)
for rec in csw.records:
    print(csw.records[rec].title)

