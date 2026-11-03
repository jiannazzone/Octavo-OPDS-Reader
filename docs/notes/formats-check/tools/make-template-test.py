import sys, zipfile
out = sys.argv[1]
chapter = '''<!DOCTYPE html><html><head><title>t</title></head><body>
<div id="host"><template shadowrootmode="open"><img src="data:," onerror="top.__tpl1=1"><p>Shadow text.</p></template></div>
<template id="inert"><img src="data:," onerror="top.__tpl2=1"></template>
<p>Body text of the template test.</p>
</body></html>'''
opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">template-test</dc:identifier><dc:title>Template test</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-11-02T00:00:00Z</meta></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="c1.html" media-type="text/html"/></manifest>
<spine><itemref idref="c1"/></spine></package>'''
nav = '''<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>nav</title></head><body><nav epub:type="toc"><ol><li><a href="c1.html">One</a></li></ol></nav></body></html>'''
with zipfile.ZipFile(out, 'w') as z:
    z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    z.writestr('content.opf', opf); z.writestr('nav.xhtml', nav); z.writestr('c1.html', chapter)
