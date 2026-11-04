#!/usr/bin/env python3
"""A small pre-paginated EPUB for checking the reader (docs/notes/fixed-layout.md).

Twelve 1000x1400 pages by default, each with a big page number. The pages' files differ in
size on purpose, as a real book's do, because foliate's fractions and locations
count bytes. Page 5 runs a script and an onload handler that would mark the
page if they ever ran.

    make-test-book.py OUT.epub [--spread auto|none|both] [--title TITLE] [--pages N]
"""
import argparse
import zipfile

CONTAINER = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
"""

COLORS = ["#f4e3c1", "#c9e4de", "#c6def1", "#dbcdf0", "#f2c6de", "#f7d9c4"]
CHAPTERS = {1: "Front", 4: "Middle", 9: "Back"}


def page(number):
    script = ""
    if number == 5:
        script = "<script>document.documentElement.setAttribute('data-ran', 'script')</script>"
    onload = ' onload="document.documentElement.setAttribute(\'data-ran\', \'onload\')"' if number == 5 else ""
    # About 1.5 KB to 20 KB of words, so sections aren't the same size.
    filler = " ".join(f"word{i}" for i in range(number * number * 20))
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Page {number}</title>
<meta name="viewport" content="width=1000, height=1400"/>
<style>
html, body {{ margin: 0; padding: 0; width: 1000px; height: 1400px; overflow: hidden; }}
body {{ background: {COLORS[number % len(COLORS)]}; font-family: Georgia, serif; position: relative; }}
.number {{ position: absolute; top: 350px; left: 0; width: 1000px; text-align: center; font-size: 420px; }}
.label {{ position: absolute; top: 100px; left: 0; width: 1000px; text-align: center; font-size: 80px; }}
.foot {{ position: absolute; bottom: 60px; left: 60px; right: 60px; height: 60px; overflow: hidden; font-size: 14px; color: #0003; }}
.inner {{ position: absolute; top: 0; bottom: 0; width: 8px; background: #d33; }}
</style>
{script}
</head>
<body{onload}>
<div class="label">Page {number}</div>
<div class="number">{number}</div>
<div class="inner" style="left: 0"></div>
<div class="inner" style="right: 0"></div>
<div class="foot">{filler}</div>
</body>
</html>
"""


def opf(spread, title, pages):
    scripted = ' properties="scripted"'
    items = "\n".join(
        f'    <item id="p{n}" href="p{n}.xhtml" media-type="application/xhtml+xml"{scripted if n == 5 else ""}/>'
        for n in range(1, pages + 1)
    )
    refs = "\n".join(f'    <itemref idref="p{n}"/>' for n in range(1, pages + 1))
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:octavo:fixed-layout-test:{spread}</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:creator>Octavo</dc:creator>
    <dc:language>en</dc:language>
    <meta property="dcterms:modified">2026-11-04T00:00:00Z</meta>
    <meta property="rendition:layout">pre-paginated</meta>
    <meta property="rendition:spread">{spread}</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
{items}
  </manifest>
  <spine>
{refs}
  </spine>
</package>
"""


def nav():
    entries = "\n".join(f'      <li><a href="p{n}.xhtml">{label}</a></li>' for n, label in CHAPTERS.items())
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head>
<body>
  <nav epub:type="toc">
    <ol>
{entries}
    </ol>
  </nav>
</body>
</html>
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out")
    parser.add_argument("--spread", default="auto", choices=["auto", "none", "both", "landscape", "portrait"])
    parser.add_argument("--title", default=None)
    parser.add_argument("--pages", type=int, default=12)
    args = parser.parse_args()
    title = args.title or f"Fixed layout test ({args.spread})"
    with zipfile.ZipFile(args.out, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", CONTAINER, zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/content.opf", opf(args.spread, title, args.pages), zipfile.ZIP_DEFLATED)
        z.writestr("OEBPS/nav.xhtml", nav(), zipfile.ZIP_DEFLATED)
        for n in range(1, args.pages + 1):
            z.writestr(f"OEBPS/p{n}.xhtml", page(n), zipfile.ZIP_DEFLATED)


if __name__ == "__main__":
    main()
