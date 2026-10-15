#!/usr/bin/env python3
"""Disposable loopback echo endpoint for executing exported cURL commands."""
import json
import sys
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        parts = []
        content_type = self.headers.get("Content-Type", "")
        if content_type.startswith("multipart/form-data"):
            message = BytesParser(policy=policy.default).parsebytes(
                b"Content-Type: " + content_type.encode() + b"\r\n\r\n" + body)
            for part in message.iter_parts():
                parts.append({"name": part.get_param("name", header="content-disposition"),
                              "filename": part.get_filename(), "type": part.get_content_type(), "charset": part.get_param("charset"),
                              "body": part.get_payload(decode=True).decode("utf-8", errors="replace")})
        result = {"method": self.command, "path": self.path,
                  "query": parse_qs(urlsplit(self.path).query, keep_blank_values=True),
                  "headers": dict(self.headers), "body": body.decode("utf-8", errors="replace"), "parts": parts}
        data = json.dumps(result).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data) if self.command != "HEAD" else 0))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = respond


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
port_file = Path(sys.argv[1])
pending_port = port_file.with_suffix(".tmp")
pending_port.write_text(str(server.server_port) + "\n", encoding="ascii")
pending_port.replace(port_file)
print(f"cURL fixture listening on 127.0.0.1:{server.server_port}", flush=True)
server.serve_forever()
