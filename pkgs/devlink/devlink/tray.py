"""The shared tray: ~/DeviceLink. Sending = dropping a file in here; Syncthing
replicates it to the linked device within seconds. Receiving = watching for new
files and announcing them."""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path


def tray_dir() -> Path:
    return Path(os.environ.get("DEVLINK_DIR") or "~/DeviceLink").expanduser()


def _stamp() -> str:
    return time.strftime("%Y%m%d-%H%M%S")


def send_files(paths: list[str]) -> list[Path]:
    tray = tray_dir(); tray.mkdir(parents=True, exist_ok=True)
    out = []
    for p in paths:
        src = Path(p).expanduser()
        if not src.exists():
            raise FileNotFoundError(src)
        dst = tray / f"{_stamp()}_{src.name}"
        if src.is_dir():
            shutil.copytree(src, dst)
        else:
            shutil.copy2(src, dst)
        out.append(dst)
    return out


def send_text(text: str) -> Path:
    tray = tray_dir(); tray.mkdir(parents=True, exist_ok=True)
    dst = tray / f"{_stamp()}_note.txt"
    dst.write_text(text)
    return dst


def send_clipboard() -> Path:
    for argv in (["wl-paste"], ["xclip", "-selection", "clipboard", "-o"], ["xsel", "-b"]):
        if shutil.which(argv[0]):
            text = subprocess.run(argv, capture_output=True, text=True).stdout
            if text:
                return send_text(text)
    raise RuntimeError("clipboard is empty or no clipboard tool (wl-paste/xclip/xsel)")


def listing() -> list[dict]:
    tray = tray_dir()
    if not tray.exists():
        return []
    items = []
    for p in sorted(tray.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True):
        if p.name.startswith(".") or p.name == ".stfolder":
            continue
        items.append({"name": p.name, "size": p.stat().st_size if p.is_file() else 0,
                      "mtime": int(p.stat().st_mtime), "dir": p.is_dir()})
    return items


def watch(on_new) -> None:
    """Poll the tray; call on_new(path) for each file that appears."""
    tray = tray_dir(); tray.mkdir(parents=True, exist_ok=True)
    seen = {p.name for p in tray.iterdir()}
    while True:
        time.sleep(2)
        try:
            now = {p.name for p in tray.iterdir()}
        except FileNotFoundError:
            continue
        for name in sorted(now - seen):
            if not name.startswith(".") and name != ".stfolder":
                on_new(tray / name)
        seen = now
