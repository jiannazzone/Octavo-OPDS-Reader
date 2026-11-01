#!/usr/bin/env python3
"""Serves ReaderWeb/ and one folder of books over http, like the app's
`octavo://` scheme handler, for running the real bridge.js + foliate-js in
macOS WebKit (probe.swift). Formats spike, positive and negative controls.

    python3 -I harness.py REPO BOOKS_DIR PORT MODE

MODE is `csp` or `nocsp`, optionally followed by `+sanitize` and/or `+meta`
(e.g. `nocsp+sanitize+meta`):

- `csp`: every response carries the app's policy, read from
  Octavo/Reader/ReaderSchemeHandler.swift with `octavo://app` replaced by
  this server's origin, plus `nosniff`; books get the book policy. This is
  the app's setup minus the custom scheme.
- `nocsp`: no policy at all. The positive control: whatever a book's
  payloads can do, they do here.
- `+sanitize`, `+meta`: the bridge is served with one extra line after
  `view.open()` that applies the prototype in harden.js (served as
  /foliate-js/octavo-harden.js) with those parts switched on.

Paths: /reader.html, /bridge.js, /foliate-js/* from REPO/ReaderWeb, and
/book/<name> from BOOKS_DIR.
"""
import os
import re
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

repo, books, port, spec = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
mode, *extras = spec.split('+')
origin = f'http://localhost:{port}'
web = os.path.join(repo, 'ReaderWeb')


def app_policies():
    swift = open(os.path.join(repo, 'Octavo/Reader/ReaderSchemeHandler.swift')).read()
    body = re.search(r'static let contentSecurityPolicy = \[(.*?)\]\.joined', swift, re.S).group(1)
    directives = re.findall(r'"([^"]*)"', body)
    reader = '; '.join(d.replace('\\(scheme)://\\(host)', origin) for d in directives)
    book = re.search(r'static let bookContentSecurityPolicy = "([^"]*)"', swift).group(1)
    return reader, book


READER_CSP, BOOK_CSP = app_policies()
print(f'mode {spec}; reader policy: {READER_CSP}', flush=True)

OPEN_LINE = '    await view.open(new File([await response.blob()], name, { type }))\n'


def patched_bridge():
    source = open(os.path.join(web, 'bridge.js')).read()
    assert source.count(OPEN_LINE) == 1, 'bridge.js changed: update OPEN_LINE'
    options = f"{{ sanitize: {'true' if 'sanitize' in extras else 'false'}, meta: {'true' if 'meta' in extras else 'false'} }}"
    return source.replace(OPEN_LINE, OPEN_LINE
        + f"    await (await import('./foliate-js/octavo-harden.js')).harden(view.book, {options})\n").encode()


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        '.js': 'text/javascript', '.html': 'text/html',
        '.epub': 'application/epub+zip', '.fb2': 'application/x-fictionbook+xml',
        '.mobi': 'application/x-mobipocket-ebook', '.azw3': 'application/x-mobipocket-ebook',
        '.cbz': 'application/vnd.comicbook+zip',
    }

    def do_GET(self):
        path = self.path.split('?', 1)[0]
        if extras and path in ('/bridge.js', '/foliate-js/octavo-harden.js'):
            body = patched_bridge() if path == '/bridge.js' else \
                open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'harden.js'), 'rb').read()
            self.send_response(200)
            self.send_header('Content-Type', 'text/javascript')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def translate_path(self, path):
        path = path.split('?', 1)[0]
        if path.startswith('/book/'):
            return os.path.join(books, os.path.basename(path))
        return super().translate_path(path)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        if mode == 'csp':
            self.send_header('Content-Security-Policy', BOOK_CSP if self.path.startswith('/book/') else READER_CSP)
            self.send_header('X-Content-Type-Options', 'nosniff')
        super().end_headers()

    def log_message(self, *args):
        pass


ThreadingHTTPServer(('127.0.0.1', port), lambda *a: Handler(*a, directory=web)).serve_forever()
