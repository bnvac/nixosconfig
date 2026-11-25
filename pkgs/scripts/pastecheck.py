# pastecheck — why does pasting hang? Run it right after copying the thing
# that pastes slowly (Ctrl+C), BEFORE pasting.
#
# Ctrl+V asks the app you copied from for its richest format (web page HTML,
# pictures, formatted text); Ctrl+Shift+V asks only for plain text. If Ctrl+V
# hangs and Ctrl+Shift+V doesn't, the app you copied FROM is slow to hand over
# a rich format, or the app you paste INTO is slow to digest it (e.g.
# LibreOffice downloading every picture of a pasted web page). This shows
# which: who holds the clipboard, what it offers, and how long each format
# takes to arrive.
import ctypes
import os
import subprocess
import sys
import time

FORMATS_TO_TIME = ["UTF8_STRING", "text/html", "text/rtf", "image/png",
                   "text/uri-list", "application/x-openoffice-embed-source-xml;windows_formatname=\"Star Embed Source (XML)\""]


def owner():
    x = ctypes.cdll.LoadLibrary(os.environ.get("PASTECHECK_LIBX11", "libX11.so.6"))
    x.XOpenDisplay.restype = ctypes.c_void_p
    x.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    x.XInternAtom.restype = ctypes.c_ulong
    x.XGetSelectionOwner.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    x.XGetSelectionOwner.restype = ctypes.c_ulong
    d = x.XOpenDisplay(None)
    if not d:
        sys.exit("pastecheck: no X display (run it on the desktop).")
    return x.XGetSelectionOwner(d, x.XInternAtom(d, b"CLIPBOARD", 0))


def describe(win):
    if not win:
        return "nobody (the clipboard is empty)"
    def prop(name):
        r = subprocess.run(["xprop", "-id", hex(win), name], capture_output=True, text=True)
        out = r.stdout.strip()
        return out.split("=", 1)[1].strip() if "=" in out else ""
    pid = prop("_NET_WM_PID")
    cls = prop("WM_CLASS")
    name = ""
    if pid.isdigit():
        try:
            name = open(f"/proc/{pid}/comm").read().strip()
        except OSError:
            pass
    bits = [b for b in (cls, f"process {name} ({pid})" if name else "") if b]
    return f"window {hex(win)}" + (": " + ", ".join(bits) if bits else
                                   " (a hidden helper window; the app you copied from)")


def fetch(target, timeout=6.0):
    t = time.monotonic()
    try:
        r = subprocess.run(["xclip", "-o", "-selection", "clipboard", "-t", target],
                           capture_output=True, timeout=timeout)
        ok = r.returncode == 0
        size = len(r.stdout)
    except subprocess.TimeoutExpired:
        return timeout, False, 0, True
    return time.monotonic() - t, ok, size, False


def main():
    print("Clipboard held by:", describe(owner()))
    dt, ok, _, hung = fetch("TARGETS")
    if hung or not ok:
        print(f"It didn't even say what it offers ({'no answer in 6 s' if hung else 'refused'}).")
        print("→ The app you copied from is the problem: it's busy or frozen.")
        return 1
    offered = subprocess.run(["xclip", "-o", "-selection", "clipboard", "-t", "TARGETS"],
                             capture_output=True, text=True).stdout.split()
    print(f"Offers {len(offered)} formats (answered in {dt:.2f} s):", " ".join(offered[:14]),
          "…" if len(offered) > 14 else "")
    print()
    slow = []
    for t in FORMATS_TO_TIME:
        if t not in offered:
            continue
        dt, ok, size, hung = fetch(t)
        note = "NO ANSWER (timed out)" if hung else ("ok" if ok else "refused")
        print(f"  {t[:40]:40} {dt:5.2f} s  {size:>9} bytes  {note}")
        if hung or dt > 0.5:
            slow.append(t)
    print()
    if slow:
        print("Slow to hand over:", ", ".join(slow))
        print("→ The app you copied FROM is slow with rich formats. Ctrl+Shift+V (plain text)")
        print("  avoids it; or copy from somewhere else.")
    else:
        print("Every format arrived quickly, so the app you copied from isn't the problem.")
        print("→ The app you paste INTO is slow to digest the rich version (LibreOffice")
        print("  fetching pictures from a pasted web page is the classic). Ctrl+Shift+V there,")
        print("  or tell me which app and I'll tune it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
