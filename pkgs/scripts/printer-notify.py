# printer-notify — a desktop notification when a 3D print finishes or fails.
#
# Watches each Moonraker printer's print_stats over its HTTP API and pops a
# notify-send when the state changes. No dependency on the printer's web UI
# being open, and nothing is stored — it just reacts to state transitions.
#
# Printers come from $PRINTER_HOSTS (space-separated Moonraker base URLs) or the
# command line. The `printing` module sets PRINTER_HOSTS from settings.printers.
#
#   printer-notify                         # uses $PRINTER_HOSTS
#   printer-notify http://ender.local:7125 # or pass them directly

import json
import os
import subprocess
import sys
import time
import urllib.request

HOSTS = [h for h in os.environ.get("PRINTER_HOSTS", "").split() if h] or sys.argv[1:]
POLL = int(os.environ.get("PRINTER_POLL", "15"))


def notify(title, body, urgency="normal"):
    subprocess.run(
        ["notify-send", "-a", "Printer", "-u", urgency, "-i", "printer", title, body],
        check=False,
    )


def query(host):
    """(state, filename) from a Moonraker node, or raise on any problem."""
    url = host.rstrip("/") + "/printer/objects/query?print_stats"
    with urllib.request.urlopen(url, timeout=10) as r:
        data = json.load(r)
    ps = data["result"]["status"]["print_stats"]
    return ps.get("state", ""), ps.get("filename", "")


def short(host):
    return host.split("://", 1)[-1].split(":", 1)[0].split("/", 1)[0] or host


def main():
    if not HOSTS:
        print("printer-notify: no printers configured (settings.nix → printers).")
        return 0
    print(f"printer-notify: watching {', '.join(short(h) for h in HOSTS)}")
    last = {}
    while True:
        for h in HOSTS:
            try:
                state, filename = query(h)
            except Exception:
                continue                       # printer off / unreachable — try next round
            prev = last.get(h)
            last[h] = state
            if prev is None or state == prev:
                continue                       # first sighting, or nothing changed
            name = filename or "print"
            where = short(h)
            if state == "complete":
                notify("✅ Print finished", f"{name}\non {where}")
            elif state == "error":
                notify("❌ Print failed", f"{name}\non {where}", "critical")
            elif state == "cancelled":
                notify("⏹ Print cancelled", f"{name}\non {where}", "low")
            elif state == "printing" and prev in ("standby", "complete", "error", "cancelled", ""):
                notify("🖨 Print started", f"{name}\non {where}", "low")
        time.sleep(POLL)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
