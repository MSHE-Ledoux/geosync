#!/usr/bin/python
# -*-coding:Utf-8 -*

"""module contenant cleanName"""


def cleanName(path, r=False):
    '''takes a filepath and returns a pretty name
    examples
    cleanName -p tic/tac toe.shp         -> tac_toe.shp
    cleanName -p tic/tac toe.shp' -d     -> tic__tac_toe.shp
    cleanName -p tic/tac/toc toe.shp' -d -> tac__toc_toe.shp'''

    import os
    import re

    print "input : ", path

    path = re.sub(r" ", r"_", path)
    path = re.sub(r"-", r"_", path)

    head, tail = os.path.split(path)
    # par défaut, ne prend que le nom du fichier
    # avec l'option -d, prend tout le chemin
    if r == True:
        print "head : ", head
        print "tail : ", tail
        # ne conserve que le dernier répertoire
        head = re.sub(r"^.*/([^/]*)$", r"\1", head)
        print "tail : ", tail
        print "head :>", head, "<"
        result = head+"__"+tail
        result = re.sub(r"^__", r"", result)
        #result = re.sub(r"[^\s]*", r"", result)
    else:
        result = tail
        result = re.sub(r"\s", r"", result)

    print "result : <%s>" % result
    print "result : <{}>".format(result)

    # Si le nom est trop long, on le tronque et avertit dans les logs
    result = result[-61:].lower()

    return result


# test de la fonction cleanName
if __name__ == "__main__":

    import argparse

    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("-d", "--dir",  action="store_true", dest="dir" , default=False)
    parser.add_argument("-p", "--path", action="store"  ,    dest="path", required=True)
    args = parser.parse_args()

    print parser.parse_args()

    if args.path:
        cleanName(args.path, args.dir)
    else:
        cleanName('tic/tac toe.shp', False)
        cleanName('tic/tac toe.shp', True)
        cleanName('tic/tac/toc toe.shp', True)
        cleanName('tic/tac/toc toiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiie.shp', True)

