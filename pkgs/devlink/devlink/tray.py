"""The shared tray: ~/DeviceLink. Sending = dropping a file in here; Syncthing
replicates it to the linked device within seconds. Receiving is noticed by
`devlink auto` (see __main__), which asks Syncthing who made each new file so
your own sends aren't announced back to you."""

from __future__ import annotations

import json
import mimetypes
import os
import shutil
import subprocess
import time
from pathlib import Path

TABS_SUFFIX = ".tabs.json"


def tray_dir() -> Path:
    return Path(os.environ.get("DEVLINK_DIR") or "~/DeviceLink").expanduser()


def _stamp() -> str:
    return time.strftime("%Y%m%d-%H%M%S")


# --- what this machine sent (so arrivals of our own files stay quiet) ---------

def _sent_log() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME") or "~/.cache").expanduser() / "devlink" / "sent"


def note_sent(*paths: Path) -> None:
    log = _sent_log()
    log.parent.mkdir(parents=True, exist_ok=True)
    names = (log.read_text().splitlines() if log.exists() else []) + [p.name for p in paths]
    log.write_text("\n".join(names[-500:]) + "\n")


def sent_names() -> set[str]:
    try:
        return set(_sent_log().read_text().splitlines())
    except OSError:
        return set()


# --- sending ---------------------------------------------------------------------

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
    note_sent(*out)
    return out


def send_text(text: str) -> Path:
    tray = tray_dir(); tray.mkdir(parents=True, exist_ok=True)
    dst = tray / f"{_stamp()}_note.txt"
    dst.write_text(text)
    note_sent(dst)
    return dst


def send_clipboard() -> Path:
    for argv in (["wl-paste"], ["xclip", "-selection", "clipboard", "-o"], ["xsel", "-b"]):
        if shutil.which(argv[0]):
            text = subprocess.run(argv, capture_output=True, text=True).stdout
            if text:
                return send_text(text)
    raise RuntimeError("clipboard is empty or no clipboard tool (wl-paste/xclip/xsel)")


# --- reading ---------------------------------------------------------------------

def item(name: str) -> Path | None:
    """A top-level tray entry by name — never anything outside the tray."""
    root = tray_dir().resolve()
    if not name or name.startswith(".") or "/" in name or name in ("..", "."):
        return None
    p = root / name
    return p if p.exists() and p.resolve().parent == root else None


def listing() -> list[dict]:
    tray = tray_dir()
    if not tray.exists():
        return []
    items = []
    for p in sorted(tray.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True):
        if p.name.startswith("."):
            continue
        it = {"name": p.name, "size": p.stat().st_size if p.is_file() else 0,
              "mtime": int(p.stat().st_mtime), "dir": p.is_dir(),
              "mime": "" if p.is_dir() else (mimetypes.guess_type(p.name)[0] or "")}
        if p.name.endswith(TABS_SUFFIX):
            try:
                d = json.loads(p.read_text())
                it["tabs"] = sum(len(w) for w in d.get("windows", []))
                it["from"] = str(d.get("from", ""))
            except (OSError, ValueError):
                pass
        items.append(it)
    return items
