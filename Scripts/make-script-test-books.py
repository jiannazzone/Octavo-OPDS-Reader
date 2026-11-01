#!/usr/bin/env python3
"""Generate script-test books in every format foliate-js reads (formats spike).

All content is synthetic placeholder text written for this test. Public domain (CC0).

Usage: python3 -I Scripts/make-script-test-books.py [OUTPUT_DIR] [--beacon URL]
Default output: SampleBooks/ (gitignored). Write-up: docs/notes/formats-spike.md.

Each book carries the same list of "vectors": ways a book could try to run
JavaScript or reach the network without being asked (an inline <script>,
event-handler attributes that fire on their own, javascript: URLs, nested
frames, meta refresh, remote images/styles/fonts, <base>, a script loaded from
the book's own resources...). If a vector's JavaScript runs, it leaves marks
that the checks look for:

- `data-ran-<vector>` on its document's root element;
- `<vector>` appended to `top.__bookScriptRan`;
- requests to the beacon, `<beacon>/ran?v=<vector>` (an image) and
  `<beacon>/ran-fetch?v=<vector>`;
- a `log` message to the app's `octavo` handler ("BOOK SCRIPT RAN <vector>").

Vectors that need no JavaScript (remote loads, refresh) are caught at the
beacon only: every request to it is a failure. Run
docs/notes/formats-spike/tools/beacon.py to listen.

Outputs:
  script-test.epub         EPUB 3, payloads written straight into the XHTML,
                           plus a manifest .js item. The control: EPUB is the
                           format whose blocking was already tested.
  script-test.azw3         KF8 only    } calibre converts a placeholder EPUB
  script-test.mobi         MOBI 6 only } (calibre strips scripts from MOBI 6),
  script-test.joint.mobi   MOBI 6+KF8  } then each placeholder is swapped for
                           its payload, byte for byte, in the uncompressed
                           text records. The swap keeps every length, so all
                           of the file's offsets and indexes stay valid. The
                           book's one image record is replaced with JavaScript,
                           for the "script from the book's own resources" vector.
  script-test.fb2          FictionBook 2: what FB2 can express (script
                           elements in several namespaces, javascript: and
                           remote hrefs, scripted SVG binaries, attribute
                           injection, a remote cover...).
  script-test.fbz          The same FB2, zipped.
  script-test-xxe.fb2      FB2 whose DOCTYPE declares external entities
                           (the beacon and file:///etc/hosts).

The MOBI/AZW3 files need calibre's ebook-convert (set EBOOK_CONVERT; calibre is
GPL, used here as a tool only). Without it only the EPUB and FB2 files are made.
"""
import base64
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile
import zlib

BOOK_ID = 'urn:uuid:0c4b1e1a-6f5e-4f3e-9b7a-4f1d2a0f5c11'
BEACON = 'http://localhost:8799'


def mark(vector):
    """JavaScript that leaves every mark for `vector`. No `<`, `&` or `"`, so
    it fits in XHTML text and in double-quoted attributes unescaped."""
    return (
        "(function(v){var d=document;"
        "try{d.documentElement.setAttribute('data-ran-'+v,'1')}catch(e){}"
        "try{top.__bookScriptRan=(top.__bookScriptRan||[]).concat(v)}catch(e){}"
        f"try{{new Image().src='{BEACON}/ran?v='+v}}catch(e){{}}"
        f"try{{fetch('{BEACON}/ran-fetch?v='+v)}}catch(e){{}}"
        "try{top.webkit.messageHandlers.octavo.postMessage(JSON.stringify({type:'log',level:'error',message:'BOOK SCRIPT RAN '+v}))}catch(e){}"
        f"}})('{vector}')"
    )


def attr(text):
    return text.replace('&', '&amp;').replace('<', '&lt;').replace('"', '&quot;')


def data_html(vector):
    return 'data:text/html,' + urllib.parse.quote(f'<script>{mark(vector)}</script>')


# (name, XHTML fragment). Each fragment is well-formed XML, so KF8 sections
# still parse as XHTML (mobi.js falls back to HTML for the rest of the book
# once one section doesn't).
VECTORS = [
    ('inline-script', lambda v: f'<script>{mark(v)}</script>'),
    ('inline-script-typed', lambda v: f'<script type="text/javascript">{mark(v)}</script>'),
    ('img-onerror', lambda v: f'<img src="data:," alt="" onerror="{mark(v)}"/>'),
    ('svg-onload', lambda v: f'<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4" onload="{mark(v)}"/>'),
    ('svg-script', lambda v: f'<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><script>{mark(v)}</script></svg>'),
    ('svg-animate-onbegin', lambda v: f'<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><rect width="4" height="4"><animate attributeName="x" from="0" to="1" dur="1s" onbegin="{mark(v)}"/></rect></svg>'),
    ('details-ontoggle', lambda v: f'<details open="" ontoggle="{mark(v)}"><summary>details</summary>open</details>'),
    ('css-onanimationstart', lambda v: f'<style>@keyframes octavoK {{ from {{ opacity: 1 }} to {{ opacity: 0.99 }} }}</style><span style="animation: octavoK 1s" onanimationstart="{mark(v)}">animated</span>'),
    ('input-autofocus', lambda v: f'<input autofocus="" onfocus="{mark(v)}"/>'),
    ('video-source-onerror', lambda v: f'<video width="4" height="4"><source src="data:," onerror="{mark(v)}"/></video>'),
    ('iframe-srcdoc', lambda v: f'<iframe width="40" height="20" srcdoc="{attr(f"<script>{mark(v)}</script>")}"></iframe>'),
    ('iframe-javascript-url', lambda v: f'<iframe width="40" height="20" src="javascript:{attr(mark(v))}"></iframe>'),
    ('iframe-data-url', lambda v: f'<iframe width="40" height="20" src="{attr(data_html(v))}"></iframe>'),
    ('object-data-url', lambda v: f'<object width="40" height="20" type="text/html" data="{attr(data_html(v))}"></object>'),
    ('embed-svg-data-url', lambda v: '<embed width="40" height="20" type="image/svg+xml" src="data:image/svg+xml,'
        + attr(urllib.parse.quote(f'<svg xmlns="http://www.w3.org/2000/svg" onload="{mark(v)}"/>')) + '"/>'),
    ('link-javascript-url', lambda v: f'<a href="javascript:{attr(mark(v))}">Tap this javascript: link.</a>'),
    ('link-external', lambda v: f'<a href="{BEACON}/link?v={v}">Tap this external link.</a>'),
    ('remote-img', lambda v: f'<img src="{BEACON}/load?v={v}" alt=""/>'),
    ('remote-stylesheet', lambda v: f'<link rel="stylesheet" type="text/css" href="{BEACON}/load?v={v}"/>'),
    ('remote-css-import', lambda v: f"<style>@import url('{BEACON}/load?v={v}');</style>"),
    ('remote-css-background', lambda v: f"<span style=\"background-image: url('{BEACON}/load?v={v}')\">background</span>"),
    ('remote-font', lambda v: f"<style>@font-face {{ font-family: octavoF; src: url('{BEACON}/load?v={v}') }} .octavoF {{ font-family: octavoF }}</style><span class=\"octavoF\">font</span>"),
    ('remote-audio', lambda v: f'<audio autoplay="" src="{BEACON}/load?v={v}"></audio>'),
    ('remote-video-poster', lambda v: f'<video width="4" height="4" poster="{BEACON}/load?v={v}"></video>'),
    ('remote-svg-use', lambda v: f'<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><use href="{BEACON}/load?v={v}#x"/></svg>'),
    ('remote-prefetch', lambda v: f'<link rel="prefetch" href="{BEACON}/load?v={v}"/>'),
    ('base-href', lambda v: f'<base href="{BEACON}/load/{v}/"/><img src="relative.png" alt=""/>'),
]
# These navigate their own frame if they work, so each gets a section of its own.
REFRESH_VECTORS = [
    ('meta-refresh-remote', lambda v: f'<meta http-equiv="refresh" content="1;url={BEACON}/load?v={v}"/>'),
    ('meta-refresh-javascript', lambda v: f'<meta http-equiv="refresh" content="1;url=javascript:{attr(mark(v))}"/>'),
]
# Loads a script from the book's own image record, which the generator
# replaces with JavaScript. The resource syntax differs per format.
RESOURCE_SCRIPT = 'resource-script'


def resource_script_tag(kind, index):
    if kind == 'mobi6':
        return f'<script mediarecindex="{index:05d}"></script>'
    return f'<script src="kindle:embed:{to_base32(index)}?mime=text/javascript"></script>'


def to_base32(n, width=4):
    digits = '0123456789ABCDEFGHIJKLMNOPQRSTUV'
    s = ''
    while n:
        n, r = divmod(n, 32)
        s = digits[r] + s
    return s.rjust(width, '0')


def para(section, n):
    text = ' '.join(f'This is sentence {s + 1} of paragraph {n} in the {section} section, '
                    'written only to give the page some ordinary running text.' for s in range(4))
    return f'<p>{text}</p>'


def png(width=8, height=8):
    """A small grey PNG, the book's one image."""
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    raw = b''.join(b'\0' + b'\x80' * width for _ in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def xhtml(title, body, head=''):
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en" xml:lang="en">
<head>
<meta charset="utf-8"/>
<title>{title}</title>
<link rel="stylesheet" type="text/css" href="style.css"/>
{head}
</head>
<body>
{body}
</body>
</html>
'''


STYLE = 'p { margin: 0 0 0.8em; } h2 { text-align: center; } .vector { margin: 0.6em 0; }\n'


def chapters(payload):
    """The book's sections as (id, title, body). `payload(name, fragment)`
    returns what goes into the book for one vector."""
    vectors = '\n'.join(
        f'<div class="vector" id="v-{name}"><p>Vector {name}:</p>{payload(name, make(name))}</div>'
        for name, make in VECTORS)
    resource = f'<div class="vector" id="v-{RESOURCE_SCRIPT}"><p>Vector {RESOURCE_SCRIPT}:</p>{payload(RESOURCE_SCRIPT, None)}</div>'
    image = '<p><img src="image.png" alt="The book\'s one image"/></p>'
    out = [
        ('c1', 'Control', '<h2>Control</h2>\n' + '\n'.join(para('control', n) for n in range(1, 4))),
        ('c2', 'Vectors', '<h2>Vectors</h2>\n<p id="status">If any book script runs, this book is marked.</p>\n'
            + image + '\n' + vectors + '\n' + resource + '\n' + para('vectors', 1)),
    ]
    for i, (name, make) in enumerate(REFRESH_VECTORS):
        out.append((f'c{3 + i}', name, f'<h2>{name}</h2>\n<div class="vector" id="v-{name}"><p>Vector {name}:</p>'
                    f'{payload(name, make(name))}</div>\n' + para(name, 1)))
    out.append((f'c{3 + len(REFRESH_VECTORS)}', 'End', '<h2>End</h2>\n' + para('end', 1)))
    return out


def write_epub(path, sections, extra_files=(), head=''):
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        z.writestr('META-INF/container.xml', '''<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''')
        manifest = [
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
            '<item id="css" href="style.css" media-type="text/css"/>',
            '<item id="img" href="image.png" media-type="image/png"/>',
        ]
        for sid, title, body in sections:
            manifest.append(f'<item id="{sid}" href="{sid}.xhtml" media-type="application/xhtml+xml"/>')
            z.writestr(f'OEBPS/{sid}.xhtml', xhtml(title, body, head))
        for name, media_type, data in extra_files:
            manifest.append(f'<item id="{name.replace(".", "-")}" href="{name}" media-type="{media_type}"/>')
            z.writestr(f'OEBPS/{name}', data)
        spine = ''.join(f'<itemref idref="{sid}"/>' for sid, _, _ in sections)
        z.writestr('OEBPS/content.opf', f'''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">{BOOK_ID}</dc:identifier>
<dc:title>Octavo Script Test</dc:title>
<dc:creator>Octavo formats spike</dc:creator>
<dc:language>en</dc:language>
<meta property="dcterms:modified">2026-10-31T00:00:00Z</meta>
</metadata>
<manifest>{''.join(manifest)}</manifest>
<spine>{spine}</spine>
</package>
''')
        nav = ''.join(f'<li><a href="{sid}.xhtml">{title}</a></li>' for sid, title, _ in sections)
        z.writestr('OEBPS/nav.xhtml', xhtml('Contents', f'<nav epub:type="toc"><ol>{nav}</ol></nav>'))
        z.writestr('OEBPS/style.css', STYLE)
        z.writestr('OEBPS/image.png', png())


# --- MOBI / KF8 ---------------------------------------------------------------

PLACEHOLDER_PAD = 32  # spare bytes, so the resource-script tag fits either syntax


def placeholder(name, length):
    token = f'@@{name}@@'
    return token + 'x' * (length - len(token))


def payload_text(name, fragment):
    # The placeholder sits inside <p>…</p>, so the payload closes and reopens it.
    return f'</p>{fragment}<p>'


def u16(b, o): return struct.unpack_from('>H', b, o)[0]
def u32(b, o): return struct.unpack_from('>I', b, o)[0]


def var_len_from_end(data):
    value = 0
    for byte in data[-4:]:
        if byte & 0x80:
            value = 0
        value = (value << 7) | (byte & 0x7f)
    return value


class PDB:
    def __init__(self, data):
        self.header = data[:78]
        count = u16(data, 76)
        offsets = [u32(data, 78 + 8 * i) for i in range(count)] + [len(data)]
        self.info = [data[78 + 8 * i + 4:78 + 8 * i + 8] for i in range(count)]
        self.records = [bytearray(data[offsets[i]:offsets[i + 1]]) for i in range(count)]

    def bytes(self):
        count = len(self.records)
        start = 78 + 8 * count + 2
        table, body, offset = b'', b'', start
        for info, rec in zip(self.info, self.records):
            table += struct.pack('>I', offset) + info
            body += rec
            offset += len(rec)
        return self.header + table + b'\0\0' + body


def text_parts(pdb, header_index):
    """(record index, text bytes, trailing bytes) for each text record of the
    MOBI/KF8 part whose header is record `header_index`."""
    rec0 = pdb.records[header_index]
    if u16(rec0, 0) != 1:
        raise SystemExit('text is compressed; convert with --dont-compress')
    flags = u32(rec0, 240) if u32(rec0, 20) >= 0xe4 else 0
    parts = []
    for i in range(1, u16(rec0, 8) + 1):
        rec = bytes(pdb.records[header_index + i])
        text = rec
        for _ in range(bin(flags >> 1).count('1')):
            text = text[:-var_len_from_end(text)]
        if flags & 1:
            text = text[:-((text[-1] & 3) + 1)]
        parts.append((header_index + i, text, rec[len(text):]))
    return parts


def exth(rec):
    if not u32(rec, 128) & 0x40:
        return {}
    o = 16 + u32(rec, 20)
    out, p = {}, o + 12
    for _ in range(u32(rec, o + 8)):
        kind, size = u32(rec, p), u32(rec, p + 4)
        out.setdefault(kind, rec[p + 8:p + size])
        p += size
    return out


def patch_kindle(path, kind, payloads):
    """Swap each placeholder for its payload in the text records the reader
    will use (the KF8 part of a joint file), and the book's image record for
    JavaScript. `payloads` maps placeholder text to a function of the image's
    resource index that returns the payload, padded to the same length."""
    pdb = PDB(open(path, 'rb').read())
    rec0 = pdb.records[0]
    first_resource = u32(rec0, 108)
    boundary = u32(exth(rec0).get(121, b'\xff\xff\xff\xff'), 0)
    header_index = boundary if kind != 'mobi6' and boundary != 0xffffffff else 0

    images = [i for i in range(first_resource, len(pdb.records))
              if bytes(pdb.records[i][:4]) in (b'\x89PNG', b'GIF8') or bytes(pdb.records[i][:2]) == b'\xff\xd8']
    if len(images) != 1:
        raise SystemExit(f'{path}: expected one image record, found {images}')
    image = images[0]
    pdb.records[image] = bytearray(mark(RESOURCE_SCRIPT).encode())
    # MOBI 6 recindex and KF8 kindle:embed ids both count from the first
    # resource record, starting at 1 (mobi.js loadResource(index - 1)).
    index = image - first_resource + 1

    parts = text_parts(pdb, header_index)
    text = b''.join(t for _, t, _ in parts)
    for old, make in payloads.items():
        new = make(index).encode()
        old = old.encode()
        assert len(new) == len(old), (old[:20], len(old), len(new))
        if text.count(old) != 1:
            raise SystemExit(f'{path}: placeholder {old[:24]!r} found {text.count(old)} times')
        text = text.replace(old, new)
    offset = 0
    for i, t, trailing in parts:
        pdb.records[i] = bytearray(text[offset:offset + len(t)] + trailing)
        offset += len(t)
    open(path, 'wb').write(pdb.bytes())


def make_kindle(out, convert):
    lengths = {name: len(payload_text(name, make(name))) for name, make in VECTORS + REFRESH_VECTORS}
    lengths[RESOURCE_SCRIPT] = len(payload_text(RESOURCE_SCRIPT, resource_script_tag('kf8', 1))) + PLACEHOLDER_PAD
    holders = {name: placeholder(name, n) for name, n in lengths.items()}
    sections = chapters(lambda name, _: f'<p>{holders[name]}</p>')
    with tempfile.TemporaryDirectory() as tmp:
        source = os.path.join(tmp, 'placeholders.epub')
        write_epub(source, sections)
        for file_name, kind, options in [
            ('script-test.azw3', 'kf8', []),
            ('script-test.mobi', 'mobi6', ['--mobi-file-type', 'old']),
            ('script-test.joint.mobi', 'joint', ['--mobi-file-type', 'both']),
        ]:
            target = os.path.join(tmp, file_name)
            subprocess.run([convert, source, target, '--dont-compress', *options],
                           check=True, stdout=subprocess.DEVNULL)
            makes = {name: make for name, make in VECTORS + REFRESH_VECTORS}

            def payload_for(name, size):
                if name == RESOURCE_SCRIPT:
                    tag = lambda i: resource_script_tag('mobi6' if kind == 'mobi6' else 'kf8', i)
                else:
                    fragment = makes[name](name)
                    tag = lambda i: fragment
                return lambda i: payload_text(name, tag(i)).ljust(size)

            patch_kindle(target, kind, {holders[n]: payload_for(n, len(holders[n])) for n in holders})
            shutil.copy(target, os.path.join(out, file_name))
            print(f'wrote {file_name}')


# --- FB2 ----------------------------------------------------------------------

def fb2_book(beacon_doctype=False):
    svg = base64.b64encode(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8" onload="{mark("fb2-svg-binary-onload")}">'
        f'<script>{mark("fb2-svg-binary-script")}</script><rect width="8" height="8"/></svg>'.encode()).decode()
    html = base64.b64encode(f'<script>{mark("fb2-html-binary")}</script>'.encode()).decode()
    image = base64.b64encode(png()).decode()
    vectors = [
        ('fb2-script-element', f'<script>{mark("fb2-script-element")}</script>'),
        ('fb2-script-xhtml-ns', f'<script xmlns="http://www.w3.org/1999/xhtml">{mark("fb2-script-xhtml-ns")}</script>'),
        ('fb2-script-prefixed', f'<h:script xmlns:h="http://www.w3.org/1999/xhtml">{mark("fb2-script-prefixed")}</h:script>'),
        ('fb2-xhtml-img-onerror', f'<img xmlns="http://www.w3.org/1999/xhtml" src="data:," onerror="{mark("fb2-xhtml-img-onerror")}"/>'),
        ('fb2-xhtml-iframe', '<iframe xmlns="http://www.w3.org/1999/xhtml" srcdoc="'
            + attr('<script>' + mark('fb2-xhtml-iframe') + '</script>') + '"/>'),
        ('fb2-svg-inline', f'<svg xmlns="http://www.w3.org/2000/svg" onload="{mark("fb2-svg-inline")}"><script>{mark("fb2-svg-inline")}</script></svg>'),
        ('fb2-link-javascript', f'<a l:href="javascript:{attr(mark("fb2-link-javascript"))}">Tap this javascript: link.</a>'),
        ('fb2-link-external', f'<a l:href="{BEACON}/link?v=fb2-link-external">Tap this external link.</a>'),
        ('fb2-link-attribute-injection', f'<a l:href="#x&quot; onclick=&quot;{attr(mark("fb2-link-attribute-injection"))}">attribute injection</a>'),
        ('fb2-p-onclick', f'<strong onmouseover="{mark("fb2-p-onclick")}" style="color: red">onmouseover on a known element</strong>'),
        ('fb2-cdata', f'<![CDATA[<script>{mark("fb2-cdata")}</script>]]>'),
        ('fb2-comment', f'<!-- </p><script>{mark("fb2-comment")}</script><p> -->'),
    ]
    images = [
        ('fb2-image-remote', f'<image l:href="{BEACON}/load?v=fb2-image-remote"/>'),
        ('fb2-image-javascript', f'<image l:href="javascript:{attr(mark("fb2-image-javascript"))}"/>'),
        ('fb2-image-data-html', f'<image l:href="{attr(data_html("fb2-image-data-html"))}"/>'),
        ('fb2-image-svg-binary', '<image l:href="#evil.svg"/>'),
        ('fb2-image-html-binary', '<image l:href="#evil.html"/>'),
        ('fb2-image-alt-injection', f'<image l:href="#image.png" alt="&quot;/&gt;&lt;script&gt;{attr(mark("fb2-image-alt-injection"))}&lt;/script&gt;"/>'),
        ('fb2-id-injection', f'<image l:href="#image.png" id="&quot;&gt;&lt;script&gt;{attr(mark("fb2-id-injection"))}&lt;/script&gt;"/>'),
    ]
    paras = lambda name, n: ''.join(
        f'<p>This is paragraph {i + 1} in the {name} section, '
        'written only to give the page some ordinary running text.</p>' for i in range(n))
    vector_ps = ''.join(f'<p>Vector {name}: {frag}</p>' for name, frag in vectors)
    image_ps = ''.join(f'<p>Vector {name}:</p>{frag}' for name, frag in images)
    doctype = ''
    entities = ''
    if beacon_doctype:
        doctype = f'''<!DOCTYPE FictionBook [
<!ENTITY remote SYSTEM "{BEACON}/load?v=fb2-xxe-remote">
<!ENTITY local SYSTEM "file:///etc/hosts">
<!ENTITY internal "internal entity expanded">
]>
'''
        entities = '<p>Remote entity: [&remote;]</p><p>Local file entity: [&local;]</p><p>Internal entity: [&internal;]</p>'
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/css" href="{BEACON}/load?v=fb2-xml-stylesheet"?>
{doctype}<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<stylesheet type="text/css">@import url('{BEACON}/load?v=fb2-stylesheet');</stylesheet>
<script>{mark("fb2-root-script")}</script>
<description>
<title-info>
<genre>antique</genre>
<author><first-name>Octavo</first-name><last-name>Formats Spike</last-name></author>
<book-title>Octavo Script Test{' (XXE)' if beacon_doctype else ''}</book-title>
<annotation><p>Annotation <script>{mark("fb2-annotation-script")}</script><a l:href="javascript:{attr(mark("fb2-annotation-link"))}">link</a></p></annotation>
<coverpage><image l:href="{BEACON}/load?v=fb2-cover-remote"/></coverpage>
<lang>en</lang>
</title-info>
<document-info>
<author><nickname>octavo</nickname></author>
<date value="2026-10-31">31 October 2026</date>
<id>{BOOK_ID}{'-xxe' if beacon_doctype else ''}</id>
<version>1.0</version>
</document-info>
</description>
<body>
<title><p>Octavo Script Test</p></title>
<section><title><p>Control</p></title>{paras('control', 3)}</section>
<section><title><p>Vectors</p></title>
<p id="status">If any book script runs, this book is marked.</p>
{entities}{vector_ps}{image_ps}
<table><tr><td colspan="1" onclick="{mark("fb2-td-onclick")}">table cell</td></tr></table>
{paras('vectors', 1)}
</section>
<section><title><p>End</p></title>{paras('end', 1)}</section>
</body>
<body name="notes">
<section id="note1"><title><p>1</p></title><p>A note. <script>{mark("fb2-notes-script")}</script></p></section>
</body>
<binary id="evil.svg" content-type="image/svg+xml">{svg}</binary>
<binary id="evil.html" content-type="text/html">{html}</binary>
<binary id="image.png" content-type="image/png">{image}</binary>
</FictionBook>
'''


def main():
    args = sys.argv[1:]
    global BEACON
    if '--beacon' in args:
        i = args.index('--beacon')
        BEACON = args[i + 1].rstrip('/')
        del args[i:i + 2]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = args[0] if args else os.path.join(root, 'SampleBooks')
    os.makedirs(out, exist_ok=True)

    sections = chapters(lambda name, fragment: fragment if fragment is not None
                        else '<script src="book.js"></script>')
    write_epub(os.path.join(out, 'script-test.epub'), sections,
               extra_files=[('book.js', 'text/javascript', mark('epub-manifest-script'))],
               head=f'<script>{mark("epub-head-script")}</script>')
    print('wrote script-test.epub')

    with open(os.path.join(out, 'script-test.fb2'), 'w') as f:
        f.write(fb2_book())
    with zipfile.ZipFile(os.path.join(out, 'script-test.fbz'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('script-test.fb2', fb2_book())
    with open(os.path.join(out, 'script-test-xxe.fb2'), 'w') as f:
        f.write(fb2_book(beacon_doctype=True))
    print('wrote script-test.fb2, script-test.fbz, script-test-xxe.fb2')

    convert = os.environ.get('EBOOK_CONVERT') or shutil.which('ebook-convert') \
        or '/Applications/calibre.app/Contents/MacOS/ebook-convert'
    if not os.access(convert, os.X_OK):
        print("calibre's ebook-convert not found: skipping MOBI/AZW3 (set EBOOK_CONVERT)")
        return
    make_kindle(out, convert)


if __name__ == '__main__':
    main()
