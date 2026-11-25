"""Disposable loopback server for the Quickshell discovery/action test."""

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import threading


class Handler(BaseHTTPRequestHandler):
    def reply(self, status):
        if self.headers.get("User-Agent") != "omarchy-localhost":
            return
        self.send_response(status)
        self.end_headers()

    def do_HEAD(self):
        self.reply(204 if self.path == "/" else 404)

    def log_message(self, *_args):
        pass


class ApiHandler(Handler):
    def do_HEAD(self):
        self.reply(405 if self.path == "/health" else 404)

    def do_GET(self):
        self.reply(204 if self.path == "/health" else 404)


if __name__ == "__main__":
    with HTTPServer(("127.0.0.1", 0), Handler) as server, HTTPServer(("127.0.0.1", 0), ApiHandler) as other:
        threading.Thread(target=other.serve_forever, daemon=True).start()
        print(json.dumps([server.server_port, other.server_port]), flush=True)
        server.serve_forever()
