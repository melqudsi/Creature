#!/usr/bin/env python3
"""Serve Godot web export with WASM MIME + COOP/COEP headers."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
import socket

PORT = 8080
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")


class GodotWebHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **getattr(SimpleHTTPRequestHandler, "extensions_map", {}),
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "application/javascript",
        ".webmanifest": "application/manifest+json",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


def main() -> None:
    os.chdir(ROOT)
    ip = local_ip()
    print("")
    print("Creature RTS — Godot web build (HTTP — localhost only)")
    print(f"  Desktop:  http://127.0.0.1:{PORT}/")
    print("")
    print("  LAN / phone requires HTTPS. Run: python serve-web-https.py")
    print("")
    print("  Dev mode: service workers disabled on port 8080 (fresh load each visit).")
    print("")
    with ThreadingHTTPServer(("0.0.0.0", PORT), GodotWebHandler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
