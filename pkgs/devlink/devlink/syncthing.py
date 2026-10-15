"""Thin client for the local Syncthing REST API.

Reads the API key and GUI address straight out of Syncthing's own config.xml,
so nothing has to be configured twice. Everything is loopback.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

FOLDER_ID = "devlink"          # the shared tray folder's Syncthing id
FOLDER_LABEL = "DeviceLink"


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

    # --- writes --------------------------------------------------------
    def add_device(self, device_id: str, name: str = "") -> None:
        if any(d["deviceID"] == device_id for d in self.devices()):
            return
        self._req("POST", "/rest/config/devices", {
            "deviceID": device_id,
            "name": name or device_id[:7],
            "autoAcceptFolders": True,          # accept folders the peer shares
        })

    def ensure_tray_folder(self, path: str, share_with: list[str]) -> None:
        folders = self.folders()
        existing = next((f for f in folders if f["id"] == FOLDER_ID), None)
        want = sorted(set(share_with) | ({d["deviceID"] for d in existing["devices"]} if existing else set()))
        devices = [{"deviceID": d} for d in want]
        if existing is None:
            self._req("POST", "/rest/config/folders", {
                "id": FOLDER_ID, "label": FOLDER_LABEL, "path": path,
                "type": "sendreceive", "devices": devices, "fsWatcherEnabled": True,
            })
        else:
            existing["devices"] = devices
            existing["path"] = existing.get("path") or path
            self._req("PUT", f"/rest/config/folders/{FOLDER_ID}", existing)

    def link(self, peer_id: str, path: str, name: str = "") -> None:
        """Add the peer and share the tray folder with it (idempotent)."""
        self.add_device(peer_id, name)
        self.ensure_tray_folder(path, [peer_id])

    def accept_pending(self, path: str) -> list[str]:
        """Auto-accept any device trying to connect, and share the tray. Returns accepted IDs."""
        accepted = []
        for dev_id, info in self.pending_devices().items():
            self.add_device(dev_id, info.get("name", ""))
            self.ensure_tray_folder(path, [dev_id])
            accepted.append(dev_id)
        return accepted
