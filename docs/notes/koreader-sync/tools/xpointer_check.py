"""The KOReader round trip (`docs/notes/koreader-sync.md`), on the host.

Builds KOReader-style xpointers from an EPUB's XHTML as a browser's XML parser
sees it, the way the bridge would, and resolves KOReader's own the same way.
`places.lua` answers in KOReader, in a container; `run.sh` runs both.

  python3 -I xpointer_check.py make <book.epub> <places.tsv>    # Octavo's places
  python3 -I xpointer_check.py check <book.epub> <ko.tsv>       # KOReader's places in the DOM
  python3 -I xpointer_check.py compare <places.tsv> <landed.tsv>

Reads only the project's public-domain sample books.
"""
import json
import posixpath
import random
import re
import sys
import unicodedata
import xml.dom.minidom as minidom
import zipfile
from xml.dom import Node

# The whitespace CSS collapses. Not U+00A0, which `str.isspace` counts.
CSS_SPACE = ' \t\n\r\f'


def spine(path):
    z = zipfile.ZipFile(path)
    container = minidom.parseString(z.read('META-INF/container.xml'))
    opf_path = container.getElementsByTagName('rootfile')[0].getAttribute('full-path')
    opf = minidom.parseString(z.read(opf_path))
    base = posixpath.dirname(opf_path)
    manifest = {i.getAttribute('id'): i.getAttribute('href') for i in opf.getElementsByTagName('item')}
    hrefs = [posixpath.normpath(posixpath.join(base, manifest[r.getAttribute('idref')].split('#')[0]))
             for r in opf.getElementsByTagName('itemref')]
    return z, hrefs


def body_of(z, href):
    # A DOCTYPE would make expat want its entities.
    data = re.sub(rb'<!DOCTYPE[^>]*>', b'', z.read(href), count=1)
    bodies = minidom.parseString(data).getElementsByTagName('body')
    return bodies[0] if bodies else None


def name(node):
    return node.localName or node.nodeName


def elements(node):
    return [c for c in node.childNodes if c.nodeType == Node.ELEMENT_NODE]


def walk_texts(node):
    for c in node.childNodes:
        if c.nodeType == Node.TEXT_NODE:
            yield c
        elif c.nodeType == Node.ELEMENT_NODE:
            yield from walk_texts(c)


def gather(node):
    return node.data if node.nodeType == Node.TEXT_NODE else ''.join(gather(c) for c in node.childNodes)


def gather_after(node):
    """The text after `node` in its block, for comparing a few words."""
    out, cur = [], node
    while cur is not None and len(''.join(out)) < 200:
        sib = cur.nextSibling
        while sib is not None and len(''.join(out)) < 200:
            out.append(gather(sib))
            sib = sib.nextSibling
        parent = cur.parentNode
        cur = parent if parent is not None and parent.nodeType == Node.ELEMENT_NODE and name(parent) != 'body' else None
    return ''.join(out)


def collapse(text):
    return re.sub(r'\s+', ' ', unicodedata.normalize('NFC', text)).strip()


def same_words(a, b, n=24):
    a, b = collapse(a), collapse(b)
    if not a or not b:
        return False
    k = min(n, len(a), len(b))
    return a[:k] == b[:k]


# --- crengine's counting, as measured against KOReader v2026.07.1 ---

def cre_texts(parent):
    """Text nodes as `text()[n]` counts them: blank ones only inside a
    paragraph's own text, after something in it (not the line break before a
    drop cap), never between blocks."""
    # A no-break space is text to KOReader; only CSS whitespace is blank.
    keep_blank = any(c.nodeType == Node.TEXT_NODE and c.data.strip(CSS_SPACE) for c in parent.childNodes)
    out, started = [], False
    for c in parent.childNodes:
        has_text = c.nodeType == Node.TEXT_NODE and bool(c.data.strip(CSS_SPACE))
        if c.nodeType == Node.TEXT_NODE and (has_text or (keep_blank and started)):
            out.append(c)
        if c.nodeType == Node.ELEMENT_NODE or has_text:
            started = True
    return out


def cre_offset(node, offset):
    """`offset` in `node.data` as crengine counts it: each run of CSS
    whitespace is one character, a leading run too. Not measured inside
    `<pre>`, which keeps its spacing."""
    data, out, i = node.data, 0, 0
    while i < offset:
        if data[i] in CSS_SPACE:
            j = i
            while j < len(data) and data[j] in CSS_SPACE:
                j += 1
            out += 1
            i = min(j, offset)
        else:
            out += 1
            i += 1
    return out


def dom_offset(node, offset):
    """crengine's offset back to an index in `node.data`."""
    for i in range(len(node.data) + 1):
        if cre_offset(node, i) >= offset:
            return i
    return len(node.data)


def element_path(node, body):
    """`div/p[9]`: an index only where siblings share the name. KOReader
    v2026.07.1 writes it this way; DOM version 20260812 always writes [1]."""
    parts = []
    while node is not body:
        same = [c for c in elements(node.parentNode) if name(c) == name(node)]
        parts.append(name(node) + (f'[{same.index(node) + 1}]' if len(same) > 1 else ''))
        node = node.parentNode
    return '/'.join(reversed(parts))


XPOINTER = re.compile(r'/body/DocFragment\[(\d+)\]/body((?:/[A-Za-z][\w-]*(?:\[\d+\])?)*?)(?:/text\(\)(?:\[(\d+)\])?)?(?:\.(\d+))?')


def resolve(xp, bodies):
    """KOReader's xpointer in the DOM: (text from there, (fragment, node,
    index), how), or (None, None, why). An element may end without an offset."""
    m = XPOINTER.fullmatch(xp)
    if not m:
        return None, None, 'unparsed'
    fragment, steps, text_index, offset = int(m.group(1)), m.group(2), m.group(3), int(m.group(4) or 0)
    if fragment - 1 >= len(bodies) or bodies[fragment - 1] is None:
        return None, None, 'no fragment'
    node = bodies[fragment - 1]
    for part in filter(None, steps.split('/')):
        tag, index = re.fullmatch(r'([A-Za-z][\w-]*)(?:\[(\d+)\])?', part).groups()
        same = [c for c in elements(node) if name(c) == tag]
        if int(index or 1) > len(same):
            return None, None, f'missing {part}'
        node = same[int(index or 1) - 1]
    if '/text()' not in xp:
        return collapse(gather(node) + gather_after(node))[:80], (fragment, node, 0), 'element'
    candidates = cre_texts(node)
    if int(text_index or 1) > len(candidates):
        return None, None, 'missing text()'
    t = candidates[int(text_index or 1) - 1]
    at = dom_offset(t, offset)
    return collapse(t.data[at:] + gather_after(t))[:80], (fragment, t, at), 'text'


def foliate_fraction(z, hrefs, bodies, fragment, node, at):
    """Roughly foliate's fraction: sections weighed by bytes, characters
    within one (foliate uses the layout once a section is on screen)."""
    sizes = [z.getinfo(h).file_size for h in hrefs]
    start = sum(sizes[:fragment - 1]) / sum(sizes)
    weight = sizes[fragment - 1] / sum(sizes)
    first = node if node.nodeType == Node.TEXT_NODE else next(walk_texts(node), None)
    before = total = 0
    for t in walk_texts(bodies[fragment - 1]):
        if t is first:
            before = total + (at if node.nodeType == Node.TEXT_NODE else 0)
        total += len(t.data)
    return start + (before / total if total else 0) * weight


def make(book, out, count=30):
    """`count` places at word starts, spread over the book, as the bridge would write them."""
    z, hrefs = spine(book)
    rng = random.Random(11)
    picks = []
    for fragment, href in enumerate(hrefs, 1):
        body = body_of(z, href)
        if body is not None:
            picks += [(fragment, body, t) for t in walk_texts(body) if len(t.data.strip()) > 20]
    rng.shuffle(picks)
    expect = {}
    with open(out, 'w') as f:
        for k, (fragment, body, t) in enumerate(sorted(picks[:int(count)], key=lambda p: p[0])):
            at = rng.choice([m.start() for m in re.finditer(r'(?<!\S)\S', t.data)])
            path = f'/body/DocFragment[{fragment}]/body'
            inner = element_path(t.parentNode, body)
            if inner:
                path += '/' + inner
            siblings = cre_texts(t.parentNode)
            text = 'text()' + (f'[{siblings.index(t) + 1}]' if len(siblings) > 1 else '')
            for form, xp, words in (
                ('words', f'{path}/{text}.{cre_offset(t, at)}', t.data[at:] + gather_after(t)),
                ('paragraph', f'{path}.0', gather(t.parentNode)),
            ):
                f.write(f'{k}:{form}\t{xp}\n')
                expect[f'{k}:{form}'] = collapse(words)[:80]
    with open(out + '.expect.json', 'w') as f:
        json.dump(expect, f)


def check(book, ko):
    z, hrefs = spine(book)
    bodies = [body_of(z, h) for h in hrefs]
    ok, gaps, misses = 0, [], []
    rows = list(open(ko, errors='replace'))[1:]
    for line in rows:
        page, pages, xp, text = line.rstrip('\n').split('\t')
        got, where, how = resolve(xp, bodies)
        if got is not None and (same_words(got, text) or not collapse(text)):
            ok += 1
            gaps.append(abs((int(page) - 1) / int(pages) - foliate_fraction(z, hrefs, bodies, *where)) * 100)
        else:
            misses.append((xp, how, (got or '')[:36], text[:36]))
    gaps.sort()
    pick = lambda q: gaps[min(len(gaps) - 1, int(len(gaps) * q))] if gaps else 0
    print(f'KOReader → DOM: {ok}/{len(rows)} on the same words; percentage gap median {pick(.5):.1f}, '
          f'90th {pick(.9):.1f}, max {pick(1):.1f} points')
    for m in misses[:4]:
        print('   miss', *m, sep=' | ')


def compare(places, landed):
    expect = json.load(open(places + '.expect.json'))
    results = {}
    for line in list(open(landed, errors='replace'))[1:]:
        rid, valid, page, pages, text = line.rstrip('\n').split('\t')[:5]
        form = rid.split(':', 1)[1]
        good = valid == 'true' and same_words(text, expect[rid])
        results.setdefault(form, []).append((good, rid, valid, text[:40], expect[rid][:40]))
    for form, rows in results.items():
        print(f'DOM → KOReader, {form}: {sum(r[0] for r in rows)}/{len(rows)} on the same words')
        for good, rid, valid, got, want in rows:
            if not good:
                print(f'   miss {rid} valid={valid} | KOReader: {got} | DOM: {want}')




def bridge(result, landed):
    """bridge-check.sh's two directions, from the bridge's answer (`bridge.js`)
    and where KOReader landed the bridge's places."""
    out = json.loads(json.load(open(result))['result'])
    got = {}
    for line in list(open(landed, errors='replace'))[1:]:
        rid, valid, page, pages, text = line.rstrip('\n').split('\t')[:5]
        got[rid] = (valid == 'true', text)
    sent = [p for p in out['places'] if p['xpointer']]
    good = [p for p in sent if got.get(p['id'], (False, ''))[0] and same_words(got[p['id']][1], p['words'] or '')]
    print(f'Octavo → KOReader: {len(good)}/{len(out["places"])} land on the words the bridge names'
          f' ({len(out["places"]) - len(sent)} not sent)')
    for p in sent:
        if p not in good:
            valid, text = got.get(p['id'], (False, ''))
            print(f'   miss {p["xpointer"]} valid={valid} | KOReader: {text[:40]} | bridge: {(p["words"] or "")[:40]}')
    read = [k for k in out['ko'] if k['words'] is not None and (same_words(k['words'], k['text']) or not collapse(k['text']))]
    print(f'KOReader → Octavo: {len(read)}/{len(out["ko"])} resolve to the same words')
    for k in out['ko']:
        if k not in read:
            print(f'   miss {k["xpointer"]} | KOReader: {k["text"][:36]} | bridge: {(k["words"] or "None")[:36]}')


if __name__ == '__main__':
    {'make': make, 'check': check, 'compare': compare, 'bridge': bridge}[sys.argv[1]](*sys.argv[2:])
