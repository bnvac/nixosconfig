"""devlink — link this machine to the other over Syncthing, and send anything
between them from one window.

  devlink pin <CODE>         type the same code on both machines → they link
  devlink id                 print this machine's Syncthing ID (paste on the other)
  devlink link <ID> [--name] add the peer + share the tray (the peer auto-accepts)
  devlink status             show linked devices and connection state
  devlink send <files...>    drop files into the shared tray (appear on the other)
  devlink send -t "text"     send a note;  -c  send the clipboard
  devlink auto               daemon: auto-accept new peers + notify on arrivals
  devlink ui [--port 7010]   the window (open http://127.0.0.1:7010, or --app)
  devlink screen             share THIS machine's whole screen (peer runs view)
  devlink view               open the other machine's screen in a window
"""

from __future__ import annotations

import argparse
import subprocess
import sys

from . import tray
from .syncthing import Syncthing, SyncthingError


def _notify(title: str, body: str = "") -> None:
    print(f"devlink: {title} {body}".rstrip(), file=sys.stderr)
    try:
        subprocess.run(["notify-send", "DeviceLink", f"{title}\n{body}".strip()], timeout=3)
    except (OSError, subprocess.SubprocessError):
        pass


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="devlink")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("id")
    pn = sub.add_parser("pin"); pn.add_argument("code"); pn.add_argument("--timeout", type=float, default=120.0)
    lk = sub.add_parser("link"); lk.add_argument("peer_id"); lk.add_argument("--name", default="")
    sub.add_parser("status")
    sd = sub.add_parser("send"); sd.add_argument("files", nargs="*")
    sd.add_argument("-t", "--text"); sd.add_argument("-c", "--clipboard", action="store_true")
    sub.add_parser("auto")
    ui = sub.add_parser("ui"); ui.add_argument("--port", type=int, default=7010)
    sub.add_parser("screen")
    sub.add_parser("view")
    args = ap.parse_args(argv)

    try:
        if args.cmd == "send":
            if args.clipboard:
                print(tray.send_clipboard())
            elif args.text:
                print(tray.send_text(args.text))
            elif args.files:
                for p in tray.send_files(args.files):
                    print(p)
            else:
                print("nothing to send (give files, -t TEXT, or -c)", file=sys.stderr); return 2
            return 0

        if args.cmd == "ui":
            from .ui import serve
            serve(args.port); return 0

        if args.cmd == "screen":
            from . import screen
            return screen.share()
        if args.cmd == "view":
            from . import screen
            return screen.view()

        st = Syncthing()
        path = str(tray.tray_dir())

        if args.cmd == "id":
            print(st.my_id()); return 0
        if args.cmd == "pin":
            import socket as _socket
            from . import pairing
            mine = st.my_id()
            print(f"searching for a machine using code … (same code on the other, Ctrl-C to stop)", file=sys.stderr)
            peer = pairing.pair(args.code, mine, _socket.gethostname(), args.timeout)
            if peer is None:
                print("devlink: no peer found with that code. Run `devlink pin <CODE>` on the other machine at the same time.", file=sys.stderr)
                return 1
            peer_id, peer_name = peer
            st.link(peer_id, path, peer_name)
            _notify("Linked", f"with {peer_name} ({peer_id[:7]})")
            print(f"linked with {peer_name} ({peer_id[:7]})")
            return 0
        if args.cmd == "link":
            st.link(args.peer_id, path, args.name)
            _notify("Linked", f"sharing {tray.FOLDER_LABEL if hasattr(tray,'FOLDER_LABEL') else 'DeviceLink'} with {args.name or args.peer_id[:7]}")
            return 0
        if args.cmd == "status":
            conns = st.connections().get("connections", {})
            print(f"this machine: {st.my_id()}")
            devs = [d for d in st.devices() if d["deviceID"] != st.my_id()]
            if not devs:
                print("no linked devices yet. On the other machine run `devlink id`,")
                print("then here:  devlink link <that-id>")
            for d in devs:
                c = conns.get(d["deviceID"], {})
                print(f"  {d['name']:<12} {'connected' if c.get('connected') else 'offline':<10} {d['deviceID'][:7]}")
            return 0
        if args.cmd == "auto":
            import threading
            def accept_loop():
                import time
                while True:
                    try:
                        for dev in st.accept_pending(path):
                            _notify("New device linked", dev[:7])
                    except SyncthingError:
                        pass
                    time.sleep(5)
            threading.Thread(target=accept_loop, daemon=True).start()
            tray.watch(lambda p: _notify("Received", p.name))
            return 0
    except (SyncthingError, FileNotFoundError, RuntimeError) as e:
        print(f"devlink: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
