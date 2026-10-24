"""devlink — link this machine to the other over Syncthing, and send anything
between them from one window.

  devlink pin <CODE>         type the same code on both machines → they link
  devlink id                 print this machine's Syncthing ID
  devlink link <ID> [--name] add the peer + share the tray; the peer then accepts
  devlink accept [ID]        accept a pending link request (never automatic)
  devlink status             linked devices, connection state, pending requests
  devlink send <files...>    drop files into the shared tray (appear on the other)
  devlink send -t "text"     send a note;  -c  send the clipboard
  devlink auto               daemon: notify on link requests + arrivals
  devlink ui [--port 7010]   the window (open http://127.0.0.1:7010, or --app)
  devlink screen             share THIS machine's whole screen (peer runs view)
  devlink view               open the other machine's screen in a window
"""

from __future__ import annotations

import argparse
import html
import socket
import subprocess
import sys
import threading
import time

from . import tray
from .syncthing import FOLDER_LABEL, Syncthing, SyncthingError


def _safe(name: object) -> str:
    """A device name the OTHER machine chose: printable characters only, capped,
    so it can't inject terminal escape sequences."""
    return "".join(ch for ch in str(name or "") if ch.isprintable())[:64] or "unnamed"


def _notify(title: str, body: str = "") -> None:
    print(f"devlink: {title} {body}".rstrip(), file=sys.stderr)
    try:   # dunst renders markup in the body, so escape it
        subprocess.run(["notify-send", "DeviceLink",
                        html.escape(f"{title}\n{body}".strip(), quote=False)], timeout=3)
    except (OSError, subprocess.SubprocessError):
        pass


def _accept(st: Syncthing, path: str, want: str | None) -> int:
    pending = st.pending_devices()
    if not pending:
        print("no pending link requests.")
        return 0
    if want:
        match = [d for d in pending if d.startswith(want.strip())]
    elif len(pending) == 1:
        match = list(pending)
    else:
        print("several machines are asking to link — pick one:")
        for d, info in pending.items():
            print(f"  devlink accept {d[:7]}    ({_safe(info.get('name'))})")
        return 2
    if len(match) != 1:
        print(f"no single pending request matches {want!r}.", file=sys.stderr)
        return 1
    name = st.accept(match[0], path)
    _notify("Linked", f"with {_safe(name)} ({match[0][:7]})")
    return 0


def _watch_requests(st: Syncthing) -> None:
    """Tell the user (once per device) that someone wants to link. Never accepts."""
    seen: set[str] = set()
    while True:
        try:
            for dev, info in st.pending_devices().items():
                if dev not in seen:
                    seen.add(dev)
                    _notify("Link request", f"{_safe(info.get('name') or dev[:7])} wants to link — "
                                            "`devlink accept`, or Accept in the DeviceLink window")
        except SyncthingError:
            pass
        time.sleep(5)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="devlink")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("id")
    pn = sub.add_parser("pin"); pn.add_argument("code"); pn.add_argument("--timeout", type=float, default=120.0)
    lk = sub.add_parser("link"); lk.add_argument("peer_id"); lk.add_argument("--name", default="")
    ac = sub.add_parser("accept"); ac.add_argument("peer_id", nargs="?")
    sub.add_parser("status")
    sd = sub.add_parser("send"); sd.add_argument("files", nargs="*")
    sd.add_argument("-t", "--text"); sd.add_argument("-c", "--clipboard", action="store_true")
    sub.add_parser("auto")
    ui = sub.add_parser("ui"); ui.add_argument("--port", type=int, default=7010)
    sub.add_parser("screen")
    sub.add_parser("view")
    args = ap.parse_args(argv)

    try:
        # --- commands that don't need the Syncthing API up front -------------
        if args.cmd == "send":
            if args.clipboard:
                print(tray.send_clipboard())
            elif args.text:
                print(tray.send_text(args.text))
            elif args.files:
                for p in tray.send_files(args.files):
                    print(p)
            else:
                print("nothing to send (give files, -t TEXT, or -c)", file=sys.stderr)
                return 2
            return 0
        if args.cmd == "ui":
            from .ui import serve
            serve(args.port)
            return 0
        if args.cmd in ("screen", "view"):
            from . import screen
            return screen.share() if args.cmd == "screen" else screen.view()

        st = Syncthing()
        path = str(tray.tray_dir())

        if args.cmd == "id":
            print(st.my_id())
            return 0
        if args.cmd == "pin":
            from . import pairing
            print("searching for a machine using that code… (same code on the other, Ctrl-C to stop)",
                  file=sys.stderr)
            peer = pairing.pair(args.code, st.my_id(), socket.gethostname(), args.timeout)
            if peer is None:
                print("devlink: no peer found with that code. Run `devlink pin <CODE>` on the "
                      "other machine at the same time.", file=sys.stderr)
                return 1
            peer_id, peer_name = peer[0], _safe(peer[1])
            st.link(peer_id, path, peer_name)
            _notify("Linked", f"with {peer_name} ({peer_id[:7]})")
            print(f"linked with {peer_name} ({peer_id[:7]})")
            return 0
        if args.cmd == "link":
            st.link(args.peer_id, path, args.name)
            _notify("Link sent", f"{FOLDER_LABEL} offered to {args.name or args.peer_id[:7]} — "
                                 "accept it on that machine (`devlink accept`)")
            return 0
        if args.cmd == "accept":
            return _accept(st, path, args.peer_id)
        if args.cmd == "status":
            me, peers = st.others()
            print(f"this machine: {me}")
            if not peers:
                print("no linked devices yet — run `devlink pin <code>` here and on the other machine.")
            for d in peers:
                print(f"  {_safe(d['name']):<12} {'connected' if d['connected'] else 'offline':<10} {d['id'][:7]}")
            for dev, info in st.pending_devices().items():
                print(f"  {_safe(info.get('name')):<12} {'WANTS TO LINK':<10} {dev[:7]}   → devlink accept {dev[:7]}")
            return 0
        if args.cmd == "auto":
            threading.Thread(target=_watch_requests, args=(st,), daemon=True).start()
            tray.watch(lambda p: _notify("Received", p.name))
            return 0
    except (SyncthingError, FileNotFoundError, RuntimeError) as e:
        print(f"devlink: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
