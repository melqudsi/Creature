#!/usr/bin/env python3
"""HTTPS server for Godot web export (required for LAN / non-localhost)."""
from __future__ import annotations

import datetime
import ipaddress
import os
import socket
import ssl
import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 8443
ROOT = Path(__file__).resolve().parent / "web"
CERT_DIR = Path(__file__).resolve().parent / "web-certs"


class GodotWebHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **getattr(SimpleHTTPRequestHandler, "extensions_map", {}),
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "application/javascript",
        ".webmanifest": "application/manifest+json",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        print(f"[{self.log_date_time_string()}] {fmt % args}")


def local_ips() -> list[str]:
    ips = {"127.0.0.1"}
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except OSError:
        pass
    return sorted(ips)


def ensure_cryptography() -> None:
    try:
        import cryptography  # noqa: F401
    except ImportError:
        print("Installing cryptography (one-time, for dev HTTPS cert)...")
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "cryptography", "-q"],
            stdout=subprocess.DEVNULL,
        )


def ensure_cert() -> tuple[Path, Path]:
    CERT_DIR.mkdir(exist_ok=True)
    cert_path = CERT_DIR / "dev-cert.pem"
    key_path = CERT_DIR / "dev-key.pem"
    if cert_path.exists() and key_path.exists():
        return cert_path, key_path

    ensure_cryptography()
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "creature-dev-local")])

    san_entries: list[x509.GeneralName] = [
        x509.DNSName("localhost"),
        x509.DNSName("gamepc2"),
    ]
    for ip in local_ips():
        try:
            san_entries.append(x509.IPAddress(ipaddress.ip_address(ip)))
        except ValueError:
            pass

    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=825))
        .add_extension(x509.SubjectAlternativeName(san_entries), critical=False)
        .sign(key, hashes.SHA256())
    )

    cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    key_path.write_bytes(
        key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    print(f"Created dev certificate in {CERT_DIR}")
    return cert_path, key_path


def main() -> None:
    if not ROOT.is_dir():
        print(f"Missing export folder: {ROOT}")
        sys.exit(1)

    cert_path, key_path = ensure_cert()
    ips = local_ips()
    wifi_hint = next((ip for ip in ips if ip.startswith("192.168.")), ips[-1])

    print("")
    print("Creature RTS — Godot web (HTTPS required off localhost)")
    print(f"  Desktop:  https://127.0.0.1:{PORT}/")
    print(f"  Phone:    https://{wifi_hint}:{PORT}/  (same Wi-Fi)")
    print("")
    print("  First visit: accept the self-signed certificate warning.")
    print("  Godot will NOT run over http://<LAN-IP> — only https or localhost.")
    print("")
    print("  Dev mode: service workers are disabled on port 8443 — re-export and")
    print("  refresh normally; no need to clear site data or use incognito.")
    print("  Force SW on locally: add ?dev=0 to the URL.")
    print("")

    os.chdir(ROOT)
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), GodotWebHandler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=str(cert_path), keyfile=str(key_path))
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
