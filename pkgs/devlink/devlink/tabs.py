"""Send your open Firefox tabs to the other machine, and reopen them there.

  devlink tabs          send the current Firefox window's tabs
  devlink tabs --all    send every window
On the other machine `devlink auto` notices the arrival and reopens them in a
new Firefox window ("got home — my work is already up").

Firefox keeps the live session in <profile>/sessionstore-backups/
recovery.jsonlz4 (rewritten every ~15 s while it runs): JSON, compressed as an
LZ4 *block* behind a "mozLz40\\0" header. Decoded here in pure Python so
devlink stays stdlib-only.
"""

from __future__ import annotations

import configparser
import json
import os
import socket
import struct
import subprocess
import time
from pathlib import Path

from . import tray

SUFFIX = ".tabs.json"
MAX_TABS = 300


# --- mozlz4 --------------------------------------------------------------------

def lz4_block(src: bytes, size: int) -> bytes:
    """Decompress one raw LZ4 block (the format inside .jsonlz4)."""
    dst = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1; lit += b
                if b != 255:
                    break
        dst += src[i:i + lit]; i += lit
        if i >= n:                       # the last sequence is literals only
            break
        off = src[i] | (src[i + 1] << 8); i += 2
        if off == 0 or off > len(dst):
            raise ValueError("corrupt lz4 block")
        ml = token & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1; ml += b
                if b != 255:
                    break
        ml += 4
        start = len(dst) - off
        if off >= ml:
            dst += dst[start:start + ml]
        else:                            # overlapping copy (run-length style)
            for k in range(ml):
                dst.append(dst[start + k])
    if len(dst) != size:
        raise ValueError(f"lz4: expected {size} bytes, got {len(dst)}")
    return bytes(dst)


def read_mozlz4(path: Path) -> dict:
    raw = path.read_bytes()
    if raw[:8] != b"mozLz40\0":
        raise ValueError(f"{path} isn't a mozlz4 file")
    (size,) = struct.unpack("<I", raw[8:12])
    return json.loads(lz4_block(raw[12:], size))


# --- finding the session -------------------------------------------------------

def _profile_dirs() -> list[Path]:
    out = []
    for base in (Path.home() / ".mozilla/firefox", Path.home() / ".config/mozilla/firefox"):
        ini = base / "profiles.ini"
        if not ini.exists():
            continue
        cp = configparser.RawConfigParser()
        cp.read(ini)
        def resolve(sec):
            p = cp.get(sec, "Path", fallback="")
            rel = cp.get(sec, "IsRelative", fallback="1") == "1"
            return (base / p) if rel else Path(p)
        # the profile this Firefox install actually uses comes first
        for sec in cp.sections():
            if sec.startswith("Install") and cp.get(sec, "Default", fallback=""):
                d = cp.get(sec, "Default")
                out.append(base / d if not os.path.isabs(d) else Path(d))
        for sec in cp.sections():
            if sec.startswith("Profile") and cp.get(sec, "Default", fallback="0") == "1":
                out.append(resolve(sec))
        out += [resolve(s) for s in cp.sections() if s.startswith("Profile")]
    seen, uniq = set(), []
    for p in out:
        if p not in seen and p.is_dir():
            seen.add(p); uniq.append(p)
    return uniq


def session_file() -> Path:
    for prof in _profile_dirs():
        for f in (prof / "sessionstore-backups/recovery.jsonlz4", prof / "sessionstore.jsonlz4"):
            if f.exists():
                return f
    raise RuntimeError("couldn't find a Firefox session — is Firefox set up on this machine?")


def _window_tabs(win: dict) -> list[dict]:
    tabs = []
    for t in win.get("tabs", []):
        entries = t.get("entries") or []
        if not entries:
            continue
        e = entries[max(0, min(len(entries), int(t.get("index") or len(entries))) - 1)]
        url = e.get("url", "")
        if url.startswith(("http://", "https://")):     # about:, file: etc. mean nothing elsewhere
            tabs.append({"url": url, "title": e.get("title") or url})
    return tabs


def current_tabs(all_windows: bool = False) -> list[list[dict]]:
    s = read_mozlz4(session_file())
    wins = s.get("windows") or []
    if not wins:
        raise RuntimeError("Firefox has no open windows to send.")
    if not all_windows:
        sel = int(s.get("selectedWindow") or 1)
        wins = [wins[sel - 1 if 0 < sel <= len(wins) else 0]]
    out = [t for t in (_window_tabs(w) for w in wins) if t]
    if not out:
        raise RuntimeError("no web pages open in that window.")
    return out


# --- send / open ---------------------------------------------------------------

def send(all_windows: bool = False) -> tuple[Path, int]:
    windows = current_tabs(all_windows)
    host = socket.gethostname()
    d = tray.tray_dir(); d.mkdir(parents=True, exist_ok=True)
    dest = d / f"{time.strftime('%Y%m%d-%H%M%S')}_{host}{SUFFIX}"
    dest.write_text(json.dumps({"from": host, "time": int(time.time()), "windows": windows}, indent=1))
    tray.note_sent(dest)
    return dest, sum(len(w) for w in windows)


def _gui_env() -> dict:
    """The user service may predate the X session: borrow DISPLAY from x-env."""
    env = dict(os.environ)
    if not env.get("DISPLAY"):
        f = Path(env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "x-env"
        try:
            for line in f.read_text().splitlines():
                k, _, v = line.partition("=")
                if k in ("DISPLAY", "XAUTHORITY") and v:
                    env[k] = v.strip().strip("'\"")
        except OSError:
            env["DISPLAY"] = ":0"
    return env


def load(path: Path) -> dict:
    data = json.loads(Path(path).read_text())
    wins = []
    for w in data.get("windows", []):
        urls = [t["url"] for t in w if isinstance(t, dict)
                and str(t.get("url", "")).startswith(("http://", "https://"))]
        if urls:
            wins.append(urls)
    data["windows"] = wins
    return data


def reopen(path: Path) -> int:
    """Open a received tab set in new Firefox window(s). Returns how many tabs."""
    data, opened = load(path), 0
    env = _gui_env()
    for urls in data["windows"]:
        urls = urls[:MAX_TABS - opened]
        if not urls:
            break
        argv = ["firefox", "--new-window", urls[0]]
        for u in urls[1:]:
            argv += ["--new-tab", u]
        subprocess.Popen(argv, env=env, start_new_session=True, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        opened += len(urls)
        time.sleep(1.5)                  # let each window appear before the next
    return opened
