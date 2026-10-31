#!/usr/bin/env python3
"""Generate a small EPUB 3 that produces blank (empty) pages in foliate-js's paginator.

All content is synthetic placeholder text written for this test. Public domain (CC0).

Usage: Scripts/make-blank-page-epub.py [OUTPUT.epub] [--variants]
Default output: SampleBooks/blank-page-test.epub (gitignored). Write-up:
docs/notes/foliate-blank-page-upstream.md.

Spine (section index as foliate-js counts it):
  0  control       Plain paragraphs. No blank pages. Baseline for CFI stability.
  1  tall-block    Text, then an empty block 3000px tall, then text. The block
                   spans several columns and the middle ones hold nothing but
                   that block, so they are blank pages in every engine.
  2  double-break  A short block with `page-break-after: always`, then an `h2`
                   with `page-break-before: always`, shaped like the front
                   matter of Project Gutenberg's illustrated "Pride and
                   Prejudice" (ebook 1342). Some engines leave an empty column
                   between the two breaks.
  3  vh-title      A `height: 100vh` title block, then an `h2` with
                   `page-break-before: always`. foliate-js rewrites `vh` to the
                   window height, which is taller than a column, so the block's
                   tail spills into a column of its own.
  4  control-end   Plain paragraphs, so section 3 is not the last one.

--variants writes a different book: one section per variant of the
double-break markup, to find which detail makes an engine leave a blank column.

Everything is in one external stylesheet on purpose: foliate-js rewrites
`page-break-*` to `-webkit-column-break-*` only in CSS files, not in `<style>`
elements or `style` attributes.
"""
import os
import sys
import zipfile

BOOK_ID = 'urn:uuid:5f0c1a52-2b8e-4f43-9a51-0b1a7c0b1a5e'


def para(section, n, sentences=6):
    text = ' '.join(
        f'This is sentence {s + 1} of paragraph {n} in section {section}, '
        f'written only to fill the page with ordinary running text.'
        for s in range(sentences))
    return f'<p id="s{section}p{n}">{text}</p>'


def paras(section, start, count):
    return '\n'.join(para(section, n) for n in range(start, start + count))


def xhtml(title, body):
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en">
<head>
<meta charset="utf-8"/>
<title>{title}</title>
<link rel="stylesheet" type="text/css" href="style.css"/>
</head>
<body>
{body}
</body>
</html>
'''


STYLE = '''p { margin: 0 0 0.8em; text-indent: 1.5em; }
h1, h2 { text-align: center; }
p.c { text-align: center; text-indent: 0; }
.blk { page-break-before: always; page-break-after: always; margin: 2em auto; }
h2.after-blk { page-break-before: always; }
.titlepage { height: 100vh; text-align: center; }
h2.after-title { page-break-before: always; }

/* --variants only */
.brk-after { page-break-after: always; }
.brk-before { page-break-before: always; }
.margin { margin: 2em auto; }
h2.pg { padding-top: 1em; margin-top: 4%; margin-bottom: 2%; clear: both; }
'''

IMG = '<p class="c"><img src="small.svg" alt="Placeholder illustration"/></p>'
PAGENO = '<span class="pageno" id="pn{n}"><a id="page{n}"></a></span>'


def main_sections():
    return [
        ('control', 'Control', f'<h1 id="control">Control</h1>\n{paras(0, 1, 12)}'),
        ('tall-block', 'Tall empty block', f'''<h1 id="tall">Tall empty block</h1>
{paras(1, 1, 2)}
<div id="spacer" style="height: 3000px"></div>
<p id="after-spacer">This is the first paragraph after the tall empty block.</p>
{paras(1, 3, 4)}'''),
        ('double-break', 'Two adjacent forced breaks', f'''<h1 id="double">Two adjacent forced breaks</h1>
{paras(2, 1, 1)}
<div class="blk">{PAGENO.format(n=1)}
{IMG}
</div>
<h2 class="after-blk" id="next-heading"><a id="anchor-next"></a>Next heading</h2>
{paras(2, 2, 6)}'''),
        ('vh-title', 'Full-height title block', f'''<div class="titlepage" id="titlepage">
<h1>Full-height title block</h1>
<p class="c">A block that is exactly as tall as the window.</p>
</div>
<h2 class="after-title" id="after-title">After the title block</h2>
{paras(3, 1, 6)}'''),
        ('control-end', 'Control (end)', f'<h1 id="control-end">Control (end)</h1>\n{paras(4, 1, 6)}'),
    ]


def variant_sections():
    # each variant: a block with page-break-after, then an h2 with page-break-before
    variants = {
        'v1-plain': ('brk-after', '', 'brk-before', False),
        'v2-div-margin': ('brk-after margin', '', 'brk-before', False),
        'v3-div-margin-pageno': ('brk-after margin', PAGENO.format(n=3), 'brk-before', False),
        'v4-both-breaks-on-div': ('brk-before brk-after margin', '', 'brk-before', False),
        'v5-h2-pg-style': ('brk-after margin', '', 'brk-before pg', False),
        'v6-h2-anchor': ('brk-after margin', '', 'brk-before', True),
        'v7-full-mimic': ('brk-before brk-after margin', PAGENO.format(n=7), 'brk-before pg', True),
        'v8-no-image': ('brk-after margin', '', 'brk-before', False),
    }
    sections = []
    for i, (name, (div_cls, pageno, h2_cls, anchor)) in enumerate(variants.items()):
        content = '<p class="c">A short line of text in the block.</p>' if name == 'v8-no-image' else IMG
        a = f'<a id="a{i}"></a>' if anchor else ''
        sections.append((name, name, f'''<h1>{name}</h1>
{paras(i, 1, 1)}
<div class="{div_cls}">{pageno}
{content}
</div>
<h2 class="{h2_cls}">{a}Heading after the block</h2>
{paras(i, 2, 3)}'''))
    return sections


SMALL_SVG = '''<?xml version="1.0" encoding="utf-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="300" height="200" viewBox="0 0 300 200">
<rect x="0" y="0" width="300" height="200" fill="#ddd" stroke="#333" stroke-width="6"/>
<text x="150" y="110" font-size="28" text-anchor="middle" font-family="sans-serif">placeholder</text>
</svg>
'''

CONTAINER = '''<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
'''


def opf(title, sections):
    items = '\n'.join(f'<item id="{name}" href="{name}.xhtml" media-type="application/xhtml+xml"/>'
                      for name, _, _ in sections)
    refs = '\n'.join(f'<itemref idref="{name}"/>' for name, _, _ in sections)
    return f'''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id" xml:lang="en">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">{BOOK_ID}</dc:identifier>
<dc:title>{title}</dc:title>
<dc:language>en</dc:language>
<dc:rights>Public domain (CC0). Synthetic placeholder content.</dc:rights>
<meta property="dcterms:modified">2026-10-31T00:00:00Z</meta>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="css" href="style.css" media-type="text/css"/>
<item id="small-svg" href="small.svg" media-type="image/svg+xml"/>
{items}
</manifest>
<spine>
{refs}
</spine>
</package>
'''


def main(out, variants):
    sections = variant_sections() if variants else main_sections()
    title = 'foliate-js blank page variants' if variants else 'foliate-js blank page test'
    nav = xhtml('Contents', '<nav epub:type="toc" id="toc"><h1>Contents</h1><ol>\n' + '\n'.join(
        f'<li><a href="{name}.xhtml">{label}</a></li>' for name, label, _ in sections) + '\n</ol></nav>')
    fixed = (2026, 10, 31, 0, 0, 0)

    def add(z, name, data, compress=zipfile.ZIP_DEFLATED):
        info = zipfile.ZipInfo(name, fixed)
        info.compress_type = compress
        z.writestr(info, data)

    with zipfile.ZipFile(out, 'w') as z:
        add(z, 'mimetype', 'application/epub+zip', zipfile.ZIP_STORED)
        add(z, 'META-INF/container.xml', CONTAINER)
        add(z, 'OEBPS/content.opf', opf(title, sections))
        add(z, 'OEBPS/nav.xhtml', nav)
        add(z, 'OEBPS/style.css', STYLE)
        add(z, 'OEBPS/small.svg', SMALL_SVG)
        for name, label, body in sections:
            add(z, f'OEBPS/{name}.xhtml', xhtml(label, body))


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if a != '--variants']
    variants = '--variants' in sys.argv[1:]
    default = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'SampleBooks',
                           'blank-page-variants.epub' if variants else 'blank-page-test.epub')
    out = args[0] if args else os.path.normpath(default)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    main(out, variants)
    print(out)
