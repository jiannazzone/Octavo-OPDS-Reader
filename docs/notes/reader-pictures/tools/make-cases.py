#!/usr/bin/env python3
"""Writes picture-cases.epub: the ways a book can make a picture wider than its
column, one per block, with ids the survey prints. make-cases.py <output.epub>"""
import struct, sys, zipfile, zlib

def png(width, height):
    row = b"\0" + b"\x88\x99\xaa" * width
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b""))

big = '<img id="%s" alt="" src="big.png"%s/>'
small = '<img id="%s" alt="" src="small.png"%s/>'
small_limit = ' style="max-width: 60px;"'
big_limit = ' style="max-width: 400px;"'
caption = '<p>A caption long enough that it would run out of a box that is too wide for the column.</p>'
cases = [
    # Project Gutenberg's own markup.
    f'<div class="figcenter" style="width: 550px;">{big % ("wide-box", "")}{caption}</div>',
    f'<div class="figcenter" style="width: 550px;">{small % ("wide-box-small-picture", "")}</div>',
    # The box's own margin and padding count too.
    f'<div style="width: 30em; margin-left: 2em; padding: 0 1em;">{big % ("wide-box-margin-padding", "")}</div>',
    f'<div style="float: left; width: 500px;">{big % ("wide-float", "")}</div><p style="clear: both;"/>',
    f'<div style="display: inline-block; width: 600px;">{big % ("wide-inline-block", "")}</div>',
    f'<div style="width: 700px;"><div style="width: 600px;">{big % ("wide-nested", "")}</div></div>',
    f'<figure style="width: 600px;">{big % ("wide-figure", "")}<figcaption>A caption for the figure, wide enough to show it.</figcaption></figure>',
    f'<table style="width: 600px;"><tr><td>{big % ("wide-table", "")}</td></tr></table>',
    f'<p style="width: 600px;">Words around a picture in a paragraph. {small % ("wide-paragraph", "")} More words after it, enough for a line or two.</p>',
    f'<figure style="display: table; width: 600px;">{big % ("wide-display-table", "")}<figcaption>A caption held to the picture by its table box.</figcaption></figure>',
    f'<div style="display: table; width: 600px; margin: 0 auto;">{big % ("wide-display-table-centred", "")}</div>',
    f'<table><tr><td width="600">{big % ("wide-cell-attribute", "")}</td></tr></table>',
    f'<table><tr><td style="width: 600px;">{big % ("wide-cell-style", "")}</td></tr></table>',
    f'<table><col width="600"/><tr><td>{big % ("wide-col", "")}</td></tr></table>',
    # A table with no width of its own, and two pictures side by side.
    f'<table><tr><td>{big % ("auto-table", "")}</td></tr></table>',
    f'<table><tr><td>{big % ("two-cells-left", "")}</td><td>{big % ("two-cells-right", "")}</td></tr></table>',
    # A box that takes its size from a small picture: text wraps beside it.
    f'<div style="float: left;">{big % ("float-small-limit", small_limit)}</div><p>Words that wrap beside a small picture, as many as it takes to show that they do.</p><p style="clear: both;"/>',
    f'<span style="display: inline-block;">{big % ("inline-block-small-limit", small_limit)}</span>',
    f'<div style="float: left;">{big % ("float-big-limit", big_limit)}</div><p style="clear: both;"/>',
    # The picture's own size.
    big % ("max-width-px", ' style="max-width: 800px;"'),
    big % ("max-width-class", ' class="capped"'),
    big % ("width-attribute", ' width="800" height="533"'),
    big % ("width-vw", ' style="width: 100vw;"'),
    '<svg id="svg-wide" xmlns="http://www.w3.org/2000/svg" width="800" height="533" viewBox="0 0 800 533"><rect width="800" height="533" fill="#889"/></svg>',
    '<video id="video-wide" width="800" height="450"></video>',
    # What must not change.
    big % ("max-width-percent", ' style="max-width: 40%;"'),
    small % ("plain-small", ""),
    big % ("plain-big", ""),
    # foliate reads a limit of 0 as none.
    big % ("zero-limit", ' style="max-width: 0;"'),
    # min-width beats max-width: left to the book.
    big % ("min-width", ' style="min-width: 600px;"'),
]
page = f'''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Pictures</title><style>
.figcenter {{ margin: 3% auto; clear: both; text-align: center; text-indent: 0; }}
img.capped {{ max-width: 40em; }}
</style></head><body>
{"".join(f"<p>Text before the next picture.</p>{case}" for case in cases)}
</body></html>'''
words = "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife. "
text = f'''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Text</title></head><body>
{"".join(f"<p>{words * 6}</p>" for _ in range(20))}
</body></html>'''
opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:uuid:7b0c5b2e-0000-4000-8000-0000000000aa</dc:identifier>
<dc:title>Picture cases</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-11-04T00:00:00Z</meta></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml" properties="svg"/>
<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
<item id="big" href="big.png" media-type="image/png"/><item id="small" href="small.png" media-type="image/png"/></manifest>
<spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>'''
nav = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body>
<nav epub:type="toc"><ol><li><a href="c1.xhtml">Pictures</a></li><li><a href="c2.xhtml">Text</a></li></ol></nav></body></html>'''
container = '''<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'''
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("mimetype", "application/epub+zip", zipfile.ZIP_STORED)
    z.writestr("META-INF/container.xml", container)
    z.writestr("OEBPS/content.opf", opf)
    z.writestr("OEBPS/nav.xhtml", nav)
    z.writestr("OEBPS/c1.xhtml", page)
    z.writestr("OEBPS/c2.xhtml", text)
    z.writestr("OEBPS/big.png", png(1200, 800))
    z.writestr("OEBPS/small.png", png(200, 100))
