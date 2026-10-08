#!/usr/bin/env python3
import json, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlsplit, parse_qs
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/slow':
            time.sleep(5)
        if path == '/large':
            record = json.dumps({'id': 1, 'name': 'Studio headphones', 'description': 'Detailed product data ' * 40, 'price': 129, 'active': True}, separators=(',', ':')).encode()
            count = 120000
            self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length', str(2 + count * len(record) + count - 1)); self.end_headers()
            try:
                self.wfile.write(b'[')
                for i in range(count):
                    self.wfile.write((b',' if i else b'') + record)
                self.wfile.write(b']')
            except (BrokenPipeError, ConnectionResetError): pass
            return
        data = {'data': [
            {'id':'prod_01','name':'Studio headphones','category':'Audio','price':129.00,'currency':'EUR','in_stock':True,'tags':['wireless','noise-cancelling']},
            {'id':'prod_02','name':'Mechanical keyboard','category':'Accessories','price':89.00,'currency':'EUR','in_stock':True,'tags':['usb-c','compact']},
            {'id':'prod_03','name':'Desk lamp','category':'Home','price':49.00,'currency':'EUR','in_stock':False,'tags':['led','adjustable']}
        ], 'pagination': {'page':1,'limit':50,'total':3}, 'meta': {'request_id':'req_a8f3c2','api_version':'2026-10-01'}}
        if path == '/echo': data = {'method':self.command,'query':parse_qs(urlsplit(self.path).query),'headers':dict(self.headers)}
        if path == '/error': self.respond({'error':'Not found'},404); return
        self.respond(data)
    def do_POST(self):
        size = int(self.headers.get('Content-Length',0)); body = self.rfile.read(size)
        self.respond({'method':self.command,'bytes':len(body),'body':body.decode(errors='replace'),'headers':dict(self.headers)},201)
    do_PUT = do_POST
    do_PATCH = do_POST
    do_DELETE = do_GET
    def do_HEAD(self): self.send_response(204); self.end_headers()
    def respond(self,data,status=200):
        body=json.dumps(data,separators=(',',':')).encode(); self.send_response(status); self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Content-Length',str(len(body))); self.send_header('X-Request-Id','req_a8f3c2'); self.end_headers(); self.wfile.write(body)
ThreadingHTTPServer(('127.0.0.1',18765),Handler).serve_forever()
