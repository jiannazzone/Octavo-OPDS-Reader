import sys, zipfile
out = sys.argv[1]
payload = "data:text/html,%3Cscript%3Etop.__nav%3D(top.__nav%7C%7C0)%2B1%3C%2Fscript%3E"
chapter = f'''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:svg="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><head><title>links</title></head><body>
<p>Link test.</p>
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="40"><a id="svg-a" xlink:href="{payload}"><text x="5" y="20">svg link</text></a></svg>
<img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" usemap="#m" width="50" height="20" alt="map"/>
<map name="m"><area id="area" shape="rect" coords="0,0,50,20" href="{payload}"/></map>
<math xmlns="http://www.w3.org/1998/Math/MathML"><mi id="math" href="{payload}">x</mi></math>
<form id="form" action="{payload}" method="get"><button id="button" type="submit">go</button></form>
<object id="obj"><param name="src" value="{payload}"/></object>
</body></html>'''
opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">link-test</dc:identifier><dc:title>Link test</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-11-02T00:00:00Z</meta></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="c1"/></spine></package>'''
nav = '''<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>nav</title></head><body><nav epub:type="toc"><ol><li><a href="c1.xhtml">One</a></li></ol></nav></body></html>'''
with zipfile.ZipFile(out, 'w') as z:
    z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    z.writestr('content.opf', opf); z.writestr('nav.xhtml', nav); z.writestr('c1.xhtml', chapter)
