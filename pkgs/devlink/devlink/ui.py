"""The devlink window: a loopback web page. Shows this machine's ID and linked
devices, lets you send text/files, and lists what's in the shared tray.

Loopback only, and rejects any Host/Origin that isn't itself (the usual
DNS-rebinding / drive-by-POST guard). Open it as an app window with:
    chromium --app=http://127.0.0.1:7010
"""

from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from importlib import resources
from urllib.parse import urlparse

from . import tray
from .syncthing import Syncthing, SyncthingError

MAX_BODY = 32 * 1024 * 1024


def page() -> bytes:
    return resources.files("devlink").joinpath("static/index.html").read_bytes()


class H(BaseHTTPRequestHandler):
    server_version = "devlink"
    allowed: set[str]

    def log_message(self, *a):  # quiet
        pass

    def _ok(self) -> bool:
        if self.headers.get("Host", "") not in self.allowed:
            return False
        o = self.headers.get("Origin")
        return o is None or o.removeprefix("http://") in self.allowed

    def _json(self, code, data):
        b = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        if not self._ok():
            return self._json(403, {"error": "forbidden"})
        p = urlparse(self.path).path
        if p in ("/", "/index.html"):
            b = page()
            self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b); return
        if p == "/api/state":
            return self._json(200, self.state())
        self._json(404, {"error": "not found"})

    def do_POST(self):
        if not self._ok():
            return self._json(403, {"error": "forbidden"})
        p = urlparse(self.path).path
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_BODY:
            return self._json(413, {"error": "too large"})
        try:
            data = json.loads(self.rfile.read(n) or b"{}")
        except json.JSONDecodeError:
            return self._json(400, {"error": "bad json"})
        try:
            if p == "/api/send-text":
                tray.send_text(str(data.get("text", "")))
                return self._json(200, {"ok": True})
            if p == "/api/link":
                Syncthing().link(str(data["id"]).strip(), str(tray.tray_dir()), str(data.get("name", "")))
                return self._json(200, {"ok": True})
            if p == "/api/pin":
                import socket as _socket
                from . import pairing
                code = str(data.get("code", "")).strip()
                if not code:
                    return self._json(400, {"error": "enter a code"})
                st = Syncthing()
                mine = st.my_id()
                peer = pairing.pair(code, mine, _socket.gethostname(), float(data.get("timeout", 45)))
                if peer is None:
                    return self._json(200, {"ok": False, "error": "no peer found — use the same code on the other machine at the same time"})
                peer_id, peer_name = peer
                st.link(peer_id, str(tray.tray_dir()), peer_name)
                return self._json(200, {"ok": True, "peer": peer_name})
        except (SyncthingError, KeyError, RuntimeError) as e:
            return self._json(400, {"error": str(e)})
        self._json(404, {"error": "not found"})

    def state(self) -> dict:
        out = {"tray": tray.listing(), "id": "", "devices": [], "error": ""}
        try:
            st = Syncthing()
            out["id"] = st.my_id()
            conns = st.connections().get("connections", {})
            out["devices"] = [
                {"name": d["name"], "id": d["deviceID"],
                 "connected": bool(conns.get(d["deviceID"], {}).get("connected"))}
                for d in st.devices() if d["deviceID"] != out["id"]
            ]
        except SyncthingError as e:
            out["error"] = str(e)
        return out


def serve(port: int = 7010) -> None:
    httpd = ThreadingHTTPServer(("127.0.0.1", port), H)
    port = httpd.server_port
    httpd.RequestHandlerClass = type("DevlinkH", (H,), {"allowed": {f"127.0.0.1:{port}", f"localhost:{port}"}})
    print(f"devlink: window at http://127.0.0.1:{port}", file=sys.stderr)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
