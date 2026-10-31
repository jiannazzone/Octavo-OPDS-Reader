"""Static file server for the foliate-js repro, plus POST /log to collect results.

Usage: python3 -I server.py ROOT PORT LOGFILE
"""
import json
import sys
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

root, port, logfile = sys.argv[1], int(sys.argv[2]), sys.argv[3]


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        '.js': 'text/javascript',
        '.mjs': 'text/javascript',
        '.epub': 'application/epub+zip',
        '.xhtml': 'application/xhtml+xml',
    }

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_POST(self):
        if self.path != '/log':
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        try:
            data = json.loads(body)
        except ValueError:
            data = {'raw': body.decode('utf-8', 'replace')}
        data['_received'] = time.time()
        data['_ua'] = self.headers.get('User-Agent')
        with open(logfile, 'a') as f:
            f.write(json.dumps(data) + '\n')
        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


ThreadingHTTPServer(('127.0.0.1', port), partial(Handler, directory=root)).serve_forever()
