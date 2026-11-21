"""Your machines over Tailscale, so DeviceLink and Syncthing talk only inside
your tailnet (encrypted, from anywhere, nobody else's servers in between).

Everything here asks the local `tailscale` command; without Tailscale (not
installed, not signed in) every function returns nothing and DeviceLink falls
back to the local network.
"""

from __future__ import annotations

import ipaddress
import json
import os
import shutil
import subprocess

SYNC_PORT = 22000
_CGNAT = ipaddress.ip_network("100.64.0.0/10")     # every Tailscale IPv4 lives here


def enabled() -> bool:
    """Tailnet-only mode, set by NixOS (settings.syncOverTailscale)."""
    return os.environ.get("DEVLINK_TAILNET") == "1"


def is_tailnet_ip(ip: str) -> bool:
    try:
        return ipaddress.ip_address(ip) in _CGNAT
    except ValueError:
        return False


def _status() -> dict | None:
    exe = shutil.which("tailscale")
    if not exe:
        return None
    try:
        r = subprocess.run([exe, "status", "--json"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except ValueError:
        return None


def _v4(ips: list[str] | None) -> str | None:
    return next((ip for ip in ips or [] if is_tailnet_ip(ip)), None)


def my_ip() -> str | None:
    st = _status()
    return _v4((st or {}).get("Self", {}).get("TailscaleIPs")) if st else None


def peers() -> list[tuple[str, str]]:
    """[(host name, tailnet IPv4)] of your other machines that are online now."""
    st = _status()
    out = []
    for p in ((st or {}).get("Peer") or {}).values():
        ip = _v4(p.get("TailscaleIPs"))
        if ip and p.get("Online"):
            name = p.get("HostName") or (p.get("DNSName") or "").split(".")[0]
            out.append((name, ip))
    return out


def addresses(ip: str) -> list[str]:
    """How Syncthing should reach a machine: its tailnet address, nothing else."""
    return [f"tcp://{ip}:{SYNC_PORT}", f"quic://{ip}:{SYNC_PORT}"]


def retarget(st) -> list[str]:
    """Point linked machines that still say "dynamic" (paired before tailnet-only
    mode) at their tailnet address, matched by name. Returns the names changed.

    With discovery and relays off, "dynamic" would never find anyone, so this
    keeps existing links working after the switch."""
    by_name = {n.lower(): ip for n, ip in peers()}
    changed = []
    me = st.my_id()
    for d in st.devices():
        if d["deviceID"] == me or d.get("addresses") not in (["dynamic"], [], None):
            continue
        ip = by_name.get((d.get("name") or "").lower())
        if ip:
            st.set_addresses(d["deviceID"], addresses(ip))
            changed.append(d.get("name") or d["deviceID"][:7])
    return changed
