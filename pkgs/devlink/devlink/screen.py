"""Whole-screen sharing between the two linked machines, over the LAN (VNC).

  devlink screen   share THIS machine's screen; the other runs `devlink view`
  devlink view     open the other machine's screen in a window

Security: only the linked peer can connect. x11vnc is restricted to the peer's
LAN subnet and guarded by a fresh random password generated for each session.
The password is handed to the peer through the DeviceLink sync folder — which
is shared only with that one machine — so there is nothing to type. The VNC
port is listened on only while you are actually sharing; nothing runs otherwise.
"""

from __future__ import annotations

import os
import secrets
import shutil
import string
import subprocess
from pathlib import Path

from . import tray
from .syncthing import Syncthing, SyncthingError

PORT = 5900
CTL = ".devlink-screen"          # synced control dir (hidden; skipped by the tray UI)


def _need(binary: str) -> str:
    if not shutil.which(binary):
        raise RuntimeError(f"{binary} not found — is the `sync` module on and rebuilt?")
    return binary


def _ctl_dir() -> Path:
    d = tray.tray_dir() / CTL
    d.mkdir(parents=True, exist_ok=True)
    return d


def _cache_dir() -> Path:
    d = Path(os.environ.get("XDG_CACHE_HOME") or "~/.cache").expanduser() / "devlink"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _display() -> str:
    return os.environ.get("DISPLAY") or ":0"


def _mkpass() -> str:
    # classic VNC auth is limited to 8 characters
    return "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(8))


def _allow(ip: str) -> str | None:
    """Restrict to the peer's /24 (forgiving if the exact IP/port shifts).

    Only for IPv4; for anything else we fall back to password-only.
    """
    parts = ip.split(".")
    if len(parts) == 4 and all(p.isdigit() for p in parts):
        return ".".join(parts[:3]) + "."
    return None


def share() -> int:
    _need("x11vnc")
    st = Syncthing()
    me = st.my_id()
    peer_id, peer_ip = st.peer()

    pw = _mkpass()
    pwfile = _cache_dir() / "vnc.auth"                       # obfuscated, local only
    subprocess.run(["x11vnc", "-storepasswd", pw, str(pwfile)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    handoff = _ctl_dir() / f"pass-{me[:7]}.txt"              # plaintext, synced to peer only
    handoff.write_text(pw)

    argv = ["x11vnc", "-display", _display(), "-rfbauth", str(pwfile),
            "-rfbport", str(PORT), "-forever", "-shared", "-noxdamage", "-quiet"]
    allow = _allow(peer_ip)
    if allow:
        argv += ["-allow", allow]

    print(f":: sharing this screen with {peer_id[:7]} "
          f"({'subnet ' + allow + '0/24' if allow else 'password only'}).")
    print(":: on the other machine run:  devlink view")
    print(":: Ctrl-C here to stop sharing.")
    try:
        subprocess.run(argv)
    except KeyboardInterrupt:
        pass
    finally:
        for f in (handoff, pwfile):
            try:
                f.unlink()
            except OSError:
                pass
        print(":: stopped sharing.")
    return 0


def view() -> int:
    import time
    _need("vncviewer")
    _need("x11vnc")
    st = Syncthing()
    peer_id, peer_ip = st.peer()
    if not peer_ip:
        raise RuntimeError("couldn't find the other machine's address.")

    handoff = _ctl_dir() / f"pass-{peer_id[:7]}.txt"
    pw = None
    for _ in range(20):                                      # wait for the password to sync in
        if handoff.exists():
            pw = handoff.read_text().strip()
            if pw:
                break
        time.sleep(1)
    if not pw:
        raise RuntimeError("no screen offered yet — run `devlink screen` on the other machine first.")

    vauth = _cache_dir() / "vnc.view.auth"
    subprocess.run(["x11vnc", "-storepasswd", pw, str(vauth)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f":: connecting to {peer_id[:7]} at {peer_ip} …")
    os.execvp("vncviewer", ["vncviewer", "-passwd", str(vauth), f"{peer_ip}:0"])
