"""Thin client for the local Syncthing REST API.

Reads the API key and GUI address straight out of Syncthing's own config.xml,
so nothing has to be configured twice. Everything is loopback.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

FOLDER_ID = "devlink"          # the shared tray folder's Syncthing id
FOLDER_LABEL = "DeviceLink"
# More folders linking should create + share with the peer (Sync, neb-shared,
# backoffice, bookmarks…): whitespace-separated "id=/path" pairs, set by sync.nix.
FOLDERS_ENV = "DEVLINK_FOLDERS"


def extra_folders() -> list[tuple[str, str]]:
    out = []
    for pair in (os.environ.get(FOLDERS_ENV) or "").split():
        fid, sep, path = pair.partition("=")
        if sep and fid and path:
            out.append((fid, os.path.expanduser(path)))
    return out


class SyncthingError(RuntimeError):
    pass


def config_dir() -> Path:
    raw = os.environ.get("SYNCTHING_CONFIG") or "~/.config/syncthing"
    return Path(raw).expanduser()


def _read_config_xml() -> tuple[str, str]:
    """Return (api_key, gui_address) from Syncthing's config.xml."""
    xml = config_dir() / "config.xml"
    try:
        root = ET.fromstring(xml.read_text())
    except FileNotFoundError:
        raise SyncthingError(f"Syncthing config not found at {xml}. Is the sync module on and started once?")
    gui = root.find("gui")
    if gui is None:
        raise SyncthingError("no <gui> block in config.xml")
    key = (gui.findtext("apikey") or "").strip()
    addr = (gui.findtext("address") or "127.0.0.1:8384").strip()
    if not key:
        raise SyncthingError("Syncthing has no API key yet; start it once.")
    return key, addr


class Syncthing:
    def __init__(self) -> None:
        self.key, addr = _read_config_xml()
        self.base = f"http://{addr}"

    def _req(self, method: str, path: str, body: object | None = None) -> object:
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("X-API-Key", self.key)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                raw = r.read()
        except urllib.error.URLError as e:
            raise SyncthingError(f"Syncthing API unreachable ({self.base}): {e}")
        return json.loads(raw) if raw.strip() else None

    # --- reads ---------------------------------------------------------
    def my_id(self) -> str:
        return self._req("GET", "/rest/system/status")["myID"]

    def devices(self) -> list[dict]:
        return self._req("GET", "/rest/config/devices") or []

    def folders(self) -> list[dict]:
        return self._req("GET", "/rest/config/folders") or []

    def connections(self) -> dict:
        return self._req("GET", "/rest/system/connections") or {}

    def pending_devices(self) -> dict:
        try:
            return self._req("GET", "/rest/cluster/pending/devices") or {}
        except SyncthingError:
            return {}

    def others(self) -> tuple[str, list[dict]]:
        """(my id, [{id, name, connected}] for every other configured device).

        One call each for status/devices/connections, however many devices.
        """
        me = self.my_id()
        conns = self.connections().get("connections", {})
        return me, [
            {"id": d["deviceID"], "name": d.get("name") or d["deviceID"][:7],
             "connected": bool(conns.get(d["deviceID"], {}).get("connected"))}
            for d in self.devices() if d["deviceID"] != me
        ]

    def peer(self) -> tuple[str, str]:
        """Return (device_id, ip) of the connected linked peer, else raise.

        The ip is parsed from Syncthing's current connection address, so it's
        the address the two machines actually reached each other on (the LAN
        IP when they're on the same network).
        """
        me = self.my_id()
        conns = self.connections().get("connections", {})
        for d in self.devices():
            did = d["deviceID"]
            if did == me:
                continue
            c = conns.get(did, {})
            if c.get("connected"):
                addr = (c.get("address") or "").strip()      # "ip:port" / "[v6]:port"
                ip = addr.rsplit(":", 1)[0].strip("[]") if addr else ""
                return did, ip
        raise SyncthingError("the other machine isn't connected right now "
                             "(open DeviceLink / Syncthing and check it's online).")

    # --- writes --------------------------------------------------------
    def add_device(self, device_id: str, name: str = "") -> None:
        if any(d["deviceID"] == device_id for d in self.devices()):
            return
        self._req("POST", "/rest/config/devices", {
            "deviceID": device_id,
            "name": name or device_id[:7],
            "autoAcceptFolders": True,          # accept folders the peer shares
        })

    def ensure_folder(self, fid: str, path: str, share_with: list[str], label: str = "") -> None:
        """Create folder `fid` (or keep it) and make sure it's shared with these devices."""
        existing = next((f for f in self.folders() if f["id"] == fid), None)
        have = {d["deviceID"] for d in existing["devices"]} if existing else set()
        devices = [{"deviceID": d} for d in sorted(set(share_with) | have)]
        if existing is None:
            self._req("POST", "/rest/config/folders", {
                "id": fid, "label": label or fid, "path": path,
                "type": "sendreceive", "devices": devices, "fsWatcherEnabled": True,
            })
        elif set(share_with) - have:
            existing["devices"] = devices
            existing["path"] = existing.get("path") or path
            self._req("PUT", f"/rest/config/folders/{urllib.parse.quote(fid, safe='')}", existing)

    def ensure_tray_folder(self, path: str, share_with: list[str]) -> None:
        self.ensure_folder(FOLDER_ID, path, share_with, FOLDER_LABEL)

    def modified_by(self, name: str, folder: str = FOLDER_ID) -> str:
        """Short id of the device that last changed a file, or '' if unknown yet."""
        q = urllib.parse.urlencode({"folder": folder, "file": name})
        try:
            info = self._req("GET", f"/rest/db/file?{q}") or {}
        except (SyncthingError, ValueError):
            return ""
        return str((info.get("global") or {}).get("modifiedBy") or "")

    def link(self, peer_id: str, path: str, name: str = "") -> None:
        """Add the peer; share the tray and every folder in $DEVLINK_FOLDERS with it.

        Idempotent. These folders are created here, at runtime, rather than
        declared in NixOS: the NixOS module re-POSTs declared folders on every
        start, which would drop a peer added this way.
        """
        self.add_device(peer_id, name)
        self.ensure_tray_folder(path, [peer_id])
        for fid, fpath in extra_folders():
            self.ensure_folder(fid, fpath, [peer_id])

    def accept(self, device_id: str, path: str) -> str:
        """Accept ONE pending link request the user chose, and share the tray.

        Deliberately not automatic: anyone who learns this machine's ID can ask
        to connect, and the tray carries files and the screen-share password.
        """
        info = self.pending_devices().get(device_id)
        if info is None:
            raise SyncthingError(f"{device_id[:7]} isn't asking to link (anymore).")
        name = info.get("name") or device_id[:7]
        self.link(device_id, path, name)
        return name
