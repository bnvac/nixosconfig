"""The devlink window: a loopback web page. Shows this machine's ID and linked
devices, sends text/files/tabs, and lists, previews and opens what's in the
shared tray.

Loopback only, and rejects any Host/Origin that isn't itself (the usual
DNS-rebinding / drive-by-POST guard). The page can't be framed by other sites
(clickjacking). Files from the tray — which the OTHER machine wrote — are
served so they can never run script in this page's origin: markup is sent as
plain text, and every file response is sandboxed. Open it as an app window:
    chromium --app=http://127.0.0.1:7010
"""

from __future__ import annotations

import json
import mimetypes
import os
import socket
import subprocess
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from importlib import resources
from urllib.parse import parse_qs, urlparse

from . import tray
from .syncthing import Syncthing, SyncthingError

MAX_BODY = 32 * 1024 * 1024
# shown inline as themselves; anything else is plain text or a download
INLINE = ("image/png", "image/jpeg", "image/gif", "image/webp", "image/avif", "image/bmp",
          "video/", "audio/", "application/pdf")
TEXTY = ("text/", "application/json", "application/xml", "application/javascript",
         "application/x-sh", "image/svg+xml", "application/toml", "application/x-yaml")
# what "Open on this machine" will hand to the default app — never executables
OPENABLE = ("image/", "video/", "audio/", "application/pdf", "text/plain", "text/markdown",
            "text/csv", "application/zip", "application/x-tar", "application/gzip",
            "application/x-7z-compressed", "application/epub+zip", "application/vnd.oasis",
            "application/vnd.openxmlformats", "application/msword", "model/stl")


def page() -> bytes:
    return resources.files("devlink").joinpath("static/index.html").read_bytes()


def _gui_env() -> dict:
    from .tabs import _gui_env as env
    return env()


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

    def _head(self, code: int, ctype: str, length: int, extra: dict | None = None) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(length))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()

    def _json(self, code, data):
        b = json.dumps(data).encode()
        self._head(code, "application/json", len(b), {"X-Frame-Options": "DENY"})
        self.wfile.write(b)

    # --- GET -----------------------------------------------------------------
    def do_GET(self):
        if not self._ok():
            return self._json(403, {"error": "forbidden"})
        url = urlparse(self.path)
        if url.path in ("/", "/index.html"):
            b = page()
            self._head(200, "text/html; charset=utf-8", len(b),
                       {"X-Frame-Options": "DENY", "Content-Security-Policy": "frame-ancestors 'none'"})
            return self.wfile.write(b)
        if url.path == "/api/state":
            return self._json(200, self.state())
        if url.path == "/api/file":
            q = parse_qs(url.query)
            return self.send_tray_file(q.get("name", [""])[0], q.get("download", ["0"])[0] == "1")
        self._json(404, {"error": "not found"})

    def send_tray_file(self, name: str, download: bool) -> None:
        p = tray.item(name)
        if p is None or not p.is_file():
            return self._json(404, {"error": "no such file in the tray"})
        mime = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
        if download:
            ctype = "application/octet-stream"
        elif mime.startswith(INLINE):
            ctype = mime
        elif mime.startswith(TEXTY):
            ctype = "text/plain; charset=utf-8"           # markup shows as source, never runs
        else:
            ctype, download = "application/octet-stream", True
        disp = "attachment" if download else "inline"
        extra = {"Content-Disposition": f"{disp}; filename*=UTF-8''{urllib.parse.quote(p.name)}",
                 "Content-Security-Policy": "frame-ancestors 'self'" + ("" if mime == "application/pdf" else "; sandbox")}
        self._head(200, ctype, p.stat().st_size, extra)
        with p.open("rb") as f:
            while chunk := f.read(1 << 16):
                self.wfile.write(chunk)

    # --- POST ----------------------------------------------------------------
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
            if p == "/api/send-tabs":
                from . import tabs
                _, count = tabs.send(bool(data.get("all")))
                return self._json(200, {"ok": True, "count": count})
            if p == "/api/open-tabs":
                from . import tabs
                f = tray.item(str(data.get("name", "")))
                if f is None or not f.name.endswith(tray.TABS_SUFFIX):
                    return self._json(400, {"error": "not a tab set"})
                return self._json(200, {"ok": True, "count": tabs.reopen(f)})
            if p == "/api/open":
                return self.open_here(str(data.get("name", "")))
            if p == "/api/link":
                Syncthing().link(str(data["id"]).strip(), str(tray.tray_dir()), str(data.get("name", "")))
                return self._json(200, {"ok": True})
            if p == "/api/accept":
                name = Syncthing().accept(str(data["id"]).strip(), str(tray.tray_dir()))
                return self._json(200, {"ok": True, "peer": name})
            if p == "/api/pin":
                from . import pairing
                code = str(data.get("code", "")).strip()
                if not code:
                    return self._json(400, {"error": "enter a code"})
                st = Syncthing()
                peer = pairing.pair(code, st.my_id(), socket.gethostname(), float(data.get("timeout", 45)))
                if peer is None:
                    return self._json(200, {"ok": False, "error": "no peer found — use the same code on the other machine at the same time"})
                st.link(peer[0], str(tray.tray_dir()), peer[1])
                return self._json(200, {"ok": True, "peer": peer[1]})
        except (SyncthingError, KeyError, RuntimeError, OSError, ValueError) as e:
            return self._json(400, {"error": str(e)})
        self._json(404, {"error": "not found"})

    def open_here(self, name: str):
        """Open a tray item with this machine's default app. Folders open in the
        file manager; files only if they're documents/media — a peer-supplied
        script or .desktop file is never handed to xdg-open."""
        f = tray.item(name)
        if f is None:
            return self._json(404, {"error": "no such item in the tray"})
        if f.is_file():
            mime = mimetypes.guess_type(f.name)[0] or ""
            if not mime.startswith(OPENABLE) or os.access(f, os.X_OK):
                return self._json(400, {"error": "won't open that kind of file automatically — download it instead"})
        subprocess.Popen(["xdg-open", str(f)], env=_gui_env(), start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return self._json(200, {"ok": True})

    def state(self) -> dict:
        out = {"tray": tray.listing(), "id": "", "devices": [], "pending": [], "error": ""}
        try:
            st = Syncthing()
            out["id"], out["devices"] = st.others()
            out["pending"] = [{"id": d, "name": info.get("name") or d[:7]}
                              for d, info in st.pending_devices().items()]
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
