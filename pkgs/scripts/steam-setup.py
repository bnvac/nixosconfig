# steam-setup — make Steam play Windows games out of the box.
#
# Turns on Steam Play (Proton) for every title — the "Enable Steam Play for
# all other titles" setting — so Windows-only games and apps (including
# Wallpaper Engine) install and run without a trip through the settings.
# Only touches Steam's config while Steam is closed, keeps a backup, and
# never changes a tool you already picked. Runs at login; safe to run again.
#
#   steam-setup              apply (Proton Experimental by default)
#   steam-setup TOOL         use another compat tool, e.g. GE-Proton
import os
import re
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
CANDIDATES = [os.path.join(HOME, ".local", "share", "Steam"), os.path.join(HOME, ".steam", "steam")]
TOOL = sys.argv[1] if len(sys.argv) > 1 else "proton_experimental"


def steam_running():
    return subprocess.run(["pgrep", "-x", "steam"], stdout=subprocess.DEVNULL).returncode == 0


# ── a tiny text-VDF reader/writer (Steam's config format) ───────────────────
TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])|//[^\n]*|\s+')


def parse(text):
    stack, cur, key = [], [], None          # objects are ordered lists of [key, value]
    for m in TOKEN.finditer(text):
        s, brace = m.group(1), m.group(2)
        if brace == "{":
            new = []
            cur.append([key, new]); stack.append(cur); cur, key = new, None
        elif brace == "}":
            cur = stack.pop()
        elif s is not None:
            if key is None:
                key = s
            else:
                cur.append([key, s]); key = None
    return cur


def dump(obj, depth=0):
    out = []
    for k, v in obj:
        tabs = "\t" * depth
        if isinstance(v, list):
            out.append(f'{tabs}"{k}"\n{tabs}{{\n{dump(v, depth + 1)}{tabs}}}\n')
        else:
            out.append(f'{tabs}"{k}"\t\t"{v}"\n')
    return "".join(out)


def child(obj, name, create=False):
    for kv in obj:
        if kv[0].lower() == name.lower() and isinstance(kv[1], list):
            return kv[1]
    if not create:
        return None
    new = []
    obj.append([name, new])
    return new


def main():
    root = next((r for r in CANDIDATES if os.path.isfile(os.path.join(r, "config", "config.vdf"))), None)
    if root is None:
        print("steam-setup: Steam hasn't been started yet — run Steam once, then this applies at next login.")
        return 0
    if steam_running():
        print("steam-setup: Steam is open; close it and run steam-setup (or just log in again).")
        return 0
    path = os.path.join(root, "config", "config.vdf")
    with open(path, encoding="utf-8", errors="replace") as f:
        data = parse(f.read())
    store = child(data, "InstallConfigStore")
    if store is None:
        print("steam-setup: unexpected config.vdf layout — leaving it alone.")
        return 1
    steam = child(child(child(store, "Software", True), "Valve", True), "Steam", True)
    mapping = child(steam, "CompatToolMapping", True)
    if child(mapping, "0") is not None:
        print("steam-setup: Steam Play for all titles is already set — nothing to do.")
        return 0
    mapping.insert(0, ["0", [["name", TOOL], ["config", ""], ["priority", "75"]]])
    shutil.copy2(path, path + ".bak")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(dump(data))
    os.replace(tmp, path)
    print(f"steam-setup: Steam Play is on for all titles ({TOOL}). Backup: {path}.bak")
    return 0


if __name__ == "__main__":
    sys.exit(main())
