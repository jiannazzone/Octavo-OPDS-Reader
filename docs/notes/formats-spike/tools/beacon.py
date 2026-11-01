#!/usr/bin/env python3
"""Logs every request it gets, one JSON line each (formats spike).

    python3 -I beacon.py LOGFILE [PORT]      (default port 8799)

The script-test books (Scripts/make-script-test-books.py) point every
network vector, and every script that manages to run, at this server. With
blocking working, the log stays empty. The simulator reaches it at
http://localhost:8799.
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

logfile = sys.argv[1]
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8799


class Handler(BaseHTTPRequestHandler):
    def handle_one(self):
        entry = {
            'time': time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime()),
            'method': self.command,
            'path': self.path,
            'referer': self.headers.get('Referer'),
            'origin': self.headers.get('Origin'),
            'ua': self.headers.get('User-Agent'),
        }
        with open(logfile, 'a') as f:
            f.write(json.dumps(entry) + '\n')
        print(json.dumps(entry), flush=True)
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()

    do_GET = do_POST = do_HEAD = do_OPTIONS = handle_one

    def log_message(self, *args):
        pass


ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
