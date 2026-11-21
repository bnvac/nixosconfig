"""PIN pairing: type the same short code on both machines and they link,
with no long IDs to copy.

How it works: each machine shouts its Syncthing device ID onto the local
network over link-local multicast (239.255.77.77, TTL 1 — it never leaves
the LAN), and sends the same shout straight to each of your other machines
on Tailscale, so pairing works from anywhere, not only on the same Wi-Fi.
Each shout also says the sender's Tailscale address, which is what the link
then uses. The shout carries an HMAC of (device-id, nonce) keyed by the PIN.
A peer only accepts a shout whose HMAC verifies under the same PIN, so only
a machine that knows the code can be linked, and the HMAC is bound to the
sender's own ID — replaying someone else's shout can't get an attacker's
device added. The PIN itself never goes on the wire.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import socket
import struct
import time

from . import tailnet

MCAST_GRP = "239.255.77.77"     # admin-scoped, link-local
MCAST_PORT = 58846
_SALT = b"devlink-pin-v1"


def _key(pin: str) -> bytes:
    # stretch the short PIN a little; it only has to resist a LAN eavesdropper
    return hashlib.pbkdf2_hmac("sha256", pin.strip().encode(), _SALT, 50_000)


def _mac(key: bytes, device_id: str, nonce: str) -> str:
    return hmac.new(key, f"{device_id}|{nonce}".encode(), hashlib.sha256).hexdigest()


def _sender() -> socket.socket:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
    return s


def _receiver() -> socket.socket:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        try:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except OSError:
            pass
    s.bind(("", MCAST_PORT))
    mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    s.settimeout(1.0)
    return s


def pair(pin: str, my_id: str, my_name: str, timeout: float = 120.0):
    """Broadcast under `pin` and listen for a peer doing the same.

    Returns (peer_id, peer_name, tailnet_ip or "") once a peer that proves the same PIN is
    heard, or None on timeout. Keeps shouting a few seconds after a match so
    the peer is sure to hear us too.
    """
    key = _key(pin)
    nonce = os.urandom(8).hex()
    my_ts = tailnet.my_ip()
    hello = json.dumps({
        "v": 1, "id": my_id, "name": my_name, "ts": my_ts,
        "nonce": nonce, "mac": _mac(key, my_id, nonce),
    }).encode()
    targets: list[str] = []
    next_peers = 0.0

    snd, rcv = _sender(), _receiver()
    found = None
    grace_until = None
    next_send = 0.0
    deadline = time.monotonic() + timeout
    try:
        while True:
            now = time.monotonic()
            if found is None and now > deadline:
                return None
            if grace_until is not None and now > grace_until:
                return found
            if now >= next_peers:                       # machines come online while we wait
                targets = [ip for _, ip in tailnet.peers()]
                next_peers = now + 10
            if now >= next_send:
                for dest in ([] if tailnet.enabled() else [MCAST_GRP]) + targets:
                    try:
                        snd.sendto(hello, (dest, MCAST_PORT))
                    except OSError:
                        pass
                next_send = now + 1.5

            try:
                raw, addr = rcv.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                continue
            try:
                msg = json.loads(raw)
                pid, pnonce, pmac = str(msg["id"]), str(msg["nonce"]), str(msg["mac"])
            except (ValueError, KeyError, TypeError):
                continue
            if pid == my_id:
                continue                      # that's our own shout echoed back
            if not hmac.compare_digest(pmac, _mac(key, pid, pnonce)):
                continue                      # wrong PIN (or forged) — ignore
            if found is None:
                # Where to reach it: the Tailscale address it announced, else the one it came from.
                ts = str(msg.get("ts") or "")
                via = ts if tailnet.is_tailnet_ip(ts) else (addr[0] if tailnet.is_tailnet_ip(addr[0]) else "")
                found = (pid, str(msg.get("name", pid[:7])), via)
                grace_until = time.monotonic() + 4.0   # keep shouting so peer hears us
    finally:
        snd.close()
        rcv.close()
