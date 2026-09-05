"""Disposable loopback server for the Quickshell discovery/action test."""

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import threading


class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    with HTTPServer(("127.0.0.1", 0), Handler) as server, HTTPServer(("127.0.0.1", 0), Handler) as other:
        threading.Thread(target=other.serve_forever, daemon=True).start()
        print(json.dumps([server.server_port, other.server_port]), flush=True)
        server.serve_forever()
