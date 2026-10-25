# browser-sync — move your OWN browser bookmarks and saved passwords between
# your two machines, without any live/cloud bookmark sync.
#
#   browser-sync                 export bookmarks, then import the other machine's
#   browser-sync export          write ~/Sync/browser/bookmarks-<host>.html from
#                                Firefox + Chromium (Syncthing carries it over)
#   browser-sync import [FILE…]  merge bookmark export(s) back into both browsers
#                                (default: every bookmarks-*.html in ~/Sync/browser
#                                 that isn't this machine's own)
#   browser-sync passwords       push browser-exported password CSVs into Bitwarden
#
# Why it works this way:
#   Bookmarks  — a plain Netscape HTML export is the one format every browser
#                reads and writes, so we never touch a live sync service. The
#                file rides the existing Syncthing ~/Sync folder to the other
#                machine; `import` unions it into whatever's there now.
#   Passwords  — Bitwarden is the password sync (its own encrypted vault, shared
#                by both machines once you sign in). This command only feeds it:
#                you export from each browser's own Passwords screen (a
#                deliberate click, the browser's own code writes the CSV), and
#                this hands that CSV to `bw import` and then shreds it. No
#                plaintext ever reaches the Sync folder, and this never reads a
#                browser's encrypted password store itself.
#
# Firefox must be CLOSED for an import (its HTML import replaces all bookmarks,
# so we import the union; if it's open we skip it and tell you). Chromium may
# stay open but you'll see the new bookmarks after its next restart.

import html
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = Path.home()
HOST = os.uname().nodename
SYNC_DIR = Path(os.environ.get("BROWSER_SYNC_DIR", HOME / "Sync" / "browser"))
# passwords never go near Sync — this is a local-only hand-off folder
PW_INBOX = HOME / ".local" / "share" / "browser-sync" / "passwords-in"

# The three roots every browser agrees on, in import order.
ROOTS = ("toolbar", "menu", "other")
ROOT_TITLE = {"toolbar": "Bookmarks Toolbar", "menu": "Bookmarks Menu", "other": "Other Bookmarks"}


# ── a tiny bookmark tree ────────────────────────────────────────────────────
class Folder:
    __slots__ = ("name", "folders", "links")

    def __init__(self, name=""):
        self.name = name
        self.folders = {}            # name -> Folder (merge by name)
        self.links = {}              # url  -> title (dedupe by url, keep first title)

    def folder(self, name):
        f = self.folders.get(name)
        if f is None:
            f = self.folders[name] = Folder(name)
        return f

    def add_link(self, url, title):
        if url and not url.startswith("place:") and url not in self.links:
            self.links[url] = title or url

    def path(self, parts):           # descend/create a nested path of folder names
        f = self
        for p in parts:
            f = f.folder(p)
        return f

    def merge(self, other):
        for url, title in other.links.items():
            self.add_link(url, title)
        for name, sub in other.folders.items():
            self.folder(name).merge(sub)

    def empty(self):
        return not self.links and all(f.empty() for f in self.folders.values())


def new_tree():
    return {r: Folder(ROOT_TITLE[r]) for r in ROOTS}


def merge_trees(dst, src):
    for r in ROOTS:
        dst[r].merge(src[r])


# ── Firefox: find profiles ──────────────────────────────────────────────────
def firefox_profiles():
    base = HOME / ".mozilla" / "firefox"
    ini = base / "profiles.ini"
    out = []
    if not ini.exists():
        return out
    cur = {}
    for line in ini.read_text(errors="replace").splitlines():
        line = line.strip()
        if line.startswith("["):
            if cur.get("Path"):
                out.append(cur)
            cur = {}
        elif "=" in line:
            k, v = line.split("=", 1)
            cur[k.strip()] = v.strip()
    if cur.get("Path"):
        out.append(cur)
    res = []
    for p in out:
        path = Path(p["Path"])
        if p.get("IsRelative", "1") == "1":
            path = base / p["Path"]
        res.append(path)
    # default-release first
    res.sort(key=lambda p: (0 if "default" in p.name else 1, p.name))
    return [p for p in res if p.exists()]


def firefox_running(profile):
    lock = profile / "lock"                      # symlink to <ip>:+<pid> while open
    parent = profile / ".parentlock"
    return lock.is_symlink() or lock.exists() or parent.exists()


# ── Firefox: read bookmarks from places.sqlite ──────────────────────────────
FF_ROOT_GUID = {
    "toolbar_____": "toolbar",
    "menu________": "menu",
    "unfiled_____": "other",
    "mobile______": "other",
}


def read_firefox(profile, tree):
    db = profile / "places.sqlite"
    if not db.exists():
        return False
    with tempfile.TemporaryDirectory() as td:
        # copy the db (+ wal/shm) so we never touch the live file
        tmp = Path(td) / "places.sqlite"
        for suffix in ("", "-wal", "-shm"):
            s = Path(str(db) + suffix)
            if s.exists():
                shutil.copy2(s, str(tmp) + suffix)
        con = sqlite3.connect(f"file:{tmp}?mode=ro", uri=True)
        try:
            con.execute("PRAGMA query_only=1")
            rows = con.execute("""
                SELECT b.id, b.parent, b.type, b.title, p.url
                FROM moz_bookmarks b LEFT JOIN moz_places p ON p.id = b.fk
                ORDER BY b.parent, b.position
            """).fetchall()
            guid = dict(con.execute("SELECT id, guid FROM moz_bookmarks"))
        finally:
            con.close()

    children = {}
    meta = {}
    for bid, parent, btype, title, url in rows:
        children.setdefault(parent, []).append(bid)
        meta[bid] = (btype, title, url)

    # Map each bookmark to its parent so we can climb to its root folder.
    parent_of = {}
    for parent, kids in children.items():
        for c in kids:
            parent_of[c] = parent

    def root_key(bid):
        while bid is not None:
            g = guid.get(bid)
            if g in FF_ROOT_GUID:
                return FF_ROOT_GUID[g]
            bid = parent_of.get(bid)
        return None

    def folder_path(bid):                  # folder-name path from the root down to bid's parent
        names = []
        node = parent_of.get(bid)
        while node is not None and guid.get(node) not in FF_ROOT_GUID:
            btype, title, _ = meta.get(node, (None, None, None))
            if title:
                names.append(title)
            node = parent_of.get(node)
        names.reverse()
        return names

    for bid, (btype, title, url) in meta.items():
        if btype != 1 or not url:          # 1 = bookmark (2 = folder, 3 = separator)
            continue
        rk = root_key(bid)
        if rk is None:
            continue
        tree[rk].path(folder_path(bid)).add_link(url, title)
    return True


# ── Chromium: read/write Bookmarks JSON ─────────────────────────────────────
CHROMIUM_DIRS = [
    HOME / ".config" / "chromium",
    HOME / ".config" / "google-chrome",
    HOME / ".config" / "BraveSoftware" / "Brave-Browser",
]
CH_ROOT = {"bookmark_bar": "toolbar", "bookmark_menu": "menu", "other": "other", "synced": "other"}


def chromium_profile_dirs(base):
    if not base.exists():
        return []
    dirs = []
    for name in ("Default",):
        if (base / name / "Bookmarks").exists():
            dirs.append(base / name)
    for p in sorted(base.glob("Profile *")):
        if (p / "Bookmarks").exists():
            dirs.append(p)
    return dirs


def chromium_running(base):
    return (base / "SingletonLock").is_symlink() or (base / "SingletonLock").exists()


def _ch_walk(node, folder):
    for ch in node.get("children", []):
        if ch.get("type") == "folder":
            _ch_walk(ch, folder.folder(ch.get("name", "")))
        elif ch.get("type") == "url":
            folder.add_link(ch.get("url", ""), ch.get("name", ""))


def read_chromium(profile, tree):
    bm = profile / "Bookmarks"
    if not bm.exists():
        return False
    try:
        data = json.loads(bm.read_text(errors="replace"))
    except Exception:
        return False
    for key, node in data.get("roots", {}).items():
        rk = CH_ROOT.get(key)
        if rk and isinstance(node, dict):
            _ch_walk(node, tree[rk])
    return True


def _ch_node(folder, counter):
    counter[0] += 1
    out = {"type": "folder", "name": folder.name, "id": str(counter[0]), "children": []}
    for name, sub in folder.folders.items():
        out["children"].append(_ch_node(sub, counter))
    for url, title in folder.links.items():
        counter[0] += 1
        out["children"].append({"type": "url", "name": title, "id": str(counter[0]), "url": url})
    return out


def write_chromium(profile, tree):
    """Union `tree` into this profile's existing Bookmarks, in place."""
    bm = profile / "Bookmarks"
    existing = new_tree()
    read_chromium(profile, existing)
    merge_trees(existing, tree)

    try:
        data = json.loads(bm.read_text(errors="replace")) if bm.exists() else {}
    except Exception:
        data = {}
    roots = data.setdefault("roots", {})
    counter = [100]
    name_for = {"toolbar": "Bookmarks bar", "menu": "Bookmarks menu", "other": "Other bookmarks"}
    ckey = {"toolbar": "bookmark_bar", "menu": "bookmark_menu", "other": "other"}
    # fold menu into other for Chromium builds without a menu root
    if "bookmark_menu" not in roots:
        existing["other"].merge(existing["menu"])
        existing["menu"] = Folder(ROOT_TITLE["menu"])
    for rk in ROOTS:
        key = ckey[rk]
        if rk == "menu" and "bookmark_menu" not in roots:
            continue
        node = _ch_node(existing[rk], counter)
        node["name"] = name_for.get(rk, node["name"])
        roots[key] = node
    data.pop("checksum", None)           # Chromium recomputes it; a stale one is ignored
    if bm.exists():
        shutil.copy2(bm, bm.with_suffix(".bak"))
    tmp = bm.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.replace(tmp, bm)


# ── Netscape HTML (the export file) ─────────────────────────────────────────
def write_html(tree, path):
    out = [
        "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
        '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
        "<TITLE>Bookmarks</TITLE>",
        "<H1>Bookmarks</H1>",
        "<DL><p>",
    ]

    def emit(folder, depth, toolbar=False):
        pad = "    " * depth
        attr = ' PERSONAL_TOOLBAR_FOLDER="true"' if toolbar else ""
        out.append(f'{pad}<DT><H3{attr}>{html.escape(folder.name)}</H3>')
        out.append(f"{pad}<DL><p>")
        for sub in folder.folders.values():
            emit(sub, depth + 1)
        for url, title in folder.links.items():
            out.append(f'{pad}    <DT><A HREF="{html.escape(url, quote=True)}">{html.escape(title)}</A>')
        out.append(f"{pad}</DL><p>")

    emit(tree["toolbar"], 1, toolbar=True)
    emit(tree["menu"], 1)
    emit(tree["other"], 1)
    out.append("</DL><p>")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out) + "\n")


A_RE = re.compile(r'<A\s+[^>]*HREF="([^"]*)"[^>]*>(.*?)</A>', re.I | re.S)
H3_RE = re.compile(r'<H3([^>]*)>(.*?)</H3>', re.I | re.S)


def read_html(path):
    """Parse a Netscape export into a tree. Top-level H3s map to our roots by
    PERSONAL_TOOLBAR_FOLDER / name; anything else lands under 'other'."""
    text = Path(path).read_text(errors="replace")
    tree = new_tree()
    # token stream: folder-open (H3), list-open/close (DL), link (A)
    tokens = re.split(r'(?i)(<DL>|</DL>|<H3[^>]*>.*?</H3>|<A\s+[^>]*>.*?</A>)', text, flags=re.S)
    stack = [None]           # current Folder; None until first root chosen
    pending = None           # H3 just seen, becomes a folder on the next <DL>
    depth = 0
    for tok in tokens:
        if not tok:
            continue
        t = tok.strip()
        low = t.lower()
        if low.startswith("<h3"):
            m = H3_RE.search(t)
            if m:
                attrs, name = m.group(1), html.unescape(re.sub("<[^>]+>", "", m.group(2))).strip()
                pending = (attrs, name)
        elif low == "<dl>":
            depth += 1
            if depth == 1:
                stack = [None]
            elif pending is not None:
                attrs, name = pending
                parent = stack[-1]
                if parent is None:              # a top-level folder → pick a root
                    if "personal_toolbar_folder" in attrs.lower():
                        f = tree["toolbar"]
                    elif "menu" in name.lower():
                        f = tree["menu"]
                    elif "toolbar" in name.lower() or "bookmarks bar" in name.lower():
                        f = tree["toolbar"]
                    else:
                        f = tree["other"].folder(name) if name and name.lower() not in ("bookmarks", "other bookmarks") else tree["other"]
                else:
                    f = parent.folder(name)
                stack.append(f)
                pending = None
            else:
                stack.append(stack[-1] if stack[-1] is not None else tree["other"])
        elif low == "</dl>":
            depth -= 1
            if len(stack) > 1:
                stack.pop()
        elif low.startswith("<a"):
            m = A_RE.search(t)
            if m:
                url = html.unescape(m.group(1))
                title = html.unescape(re.sub("<[^>]+>", "", m.group(2))).strip()
                (stack[-1] or tree["other"]).add_link(url, title)
    return tree


# ── collect / apply ─────────────────────────────────────────────────────────
def collect_local():
    tree = new_tree()
    src = []
    for prof in firefox_profiles():
        if read_firefox(prof, tree):
            src.append(f"Firefox ({prof.name})")
    for base in CHROMIUM_DIRS:
        for prof in chromium_profile_dirs(base):
            if read_chromium(prof, tree):
                src.append(f"{base.name}/{prof.name}")
    return tree, src


def count(tree):
    def c(f):
        return len(f.links) + sum(c(s) for s in f.folders.values())
    return sum(c(tree[r]) for r in ROOTS)


def signature(tree):
    """A stable fingerprint of a tree's (root, url) set, to tell whether a
    merge would actually change a browser — so login re-runs stay no-ops."""
    out = []

    def walk(f, rk):
        for url in f.links:
            out.append((rk, url))
        for sub in f.folders.values():
            walk(sub, rk)

    for rk in ROOTS:
        walk(tree[rk], rk)
    return frozenset(out)


def do_export():
    tree, src = collect_local()
    if not src:
        print("browser-sync: found no Firefox or Chromium bookmarks to export.")
        return 1
    out = SYNC_DIR / f"bookmarks-{HOST}.html"
    write_html(tree, out)
    print(f"browser-sync: exported {count(tree)} bookmarks from {', '.join(src)}")
    print(f"             → {out}  (Syncthing will carry it to the other machine)")
    return 0


def do_import(files):
    if not files:
        if not SYNC_DIR.exists():
            print(f"browser-sync: nothing to import — {SYNC_DIR} doesn't exist yet.")
            print("             Run `browser-sync export` on your other machine first.")
            return 1
        files = [p for p in sorted(SYNC_DIR.glob("bookmarks-*.html"))
                 if p.name != f"bookmarks-{HOST}.html"]
    files = [Path(f) for f in files]
    files = [f for f in files if f.exists()]
    if not files:
        print("browser-sync: no bookmark export files to import.")
        return 1

    incoming = new_tree()
    for f in files:
        merge_trees(incoming, read_html(f))
    print(f"browser-sync: importing {count(incoming)} bookmarks from {', '.join(f.name for f in files)}")

    # Chromium: merge straight into its JSON (reuses existing, adds the new).
    done = []
    for base in CHROMIUM_DIRS:
        profs = chromium_profile_dirs(base)
        if profs and chromium_running(base):
            print(f"  · {base.name}: open — new bookmarks appear after you restart it; merging anyway")
        for prof in profs:
            existing = new_tree()
            read_chromium(prof, existing)
            union = new_tree()
            merge_trees(union, existing)
            merge_trees(union, incoming)
            if signature(union) == signature(existing):
                continue                       # nothing new for this profile
            write_chromium(prof, incoming)
            done.append(f"{base.name}/{prof.name}")

    # Firefox: its HTML import REPLACES everything, so import current ∪ incoming.
    for prof in firefox_profiles():
        current = new_tree()
        read_firefox(prof, current)
        union = new_tree()
        merge_trees(union, current)
        merge_trees(union, incoming)
        if signature(union) == signature(current):
            continue                           # already has it all — don't churn
        if firefox_running(prof):
            print(f"  · Firefox ({prof.name}): open — skipped. Close Firefox and re-run to import.")
            continue
        html_path = prof / "bookmarks.html"
        if html_path.exists():
            shutil.copy2(html_path, html_path.with_suffix(".html.bak"))
        write_html(union, html_path)
        set_ff_import_pref(prof)
        done.append(f"Firefox ({prof.name})")

    if done:
        print(f"browser-sync: merged into {', '.join(done)}")
    else:
        print("             everything was already in sync.")
    return 0


FF_PREF = 'user_pref("browser.places.importBookmarksHTML", true);'


def set_ff_import_pref(profile):
    """Tell Firefox to import profile/bookmarks.html once on next launch. Firefox
    resets the pref to false after it imports, so this only fires once."""
    prefs = profile / "prefs.js"
    lines = []
    if prefs.exists():
        lines = [ln for ln in prefs.read_text(errors="replace").splitlines()
                 if "browser.places.importBookmarksHTML" not in ln]
    lines.append(FF_PREF)
    tmp = prefs.with_suffix(".js.tmp")
    tmp.write_text("\n".join(lines) + "\n")
    os.replace(tmp, prefs)


# ── passwords → Bitwarden ────────────────────────────────────────────────────
EXPORT_HELP = """How to export your saved passwords from each browser (do this once
per machine; it's the browser's own export, which is why it asks for your
login/OS password):

  Firefox    menu ≡ → Passwords → ··· (top-right) → Export Logins…
  Chromium   ⋮ → Settings → Autofill and passwords → Google Password Manager
             → Settings → Export passwords

Save each CSV into:  {inbox}
then run:  browser-sync passwords

It imports them into Bitwarden (your vault, synced to both machines) and
shreds the CSV. The CSV is only ever on this disk, never in the Sync folder.
"""


def have(cmd):
    return shutil.which(cmd) is not None


def bw_logged_in():
    try:
        out = subprocess.run(["bw", "status"], capture_output=True, text=True, timeout=30).stdout
        return json.loads(out or "{}").get("status") not in (None, "unauthenticated")
    except Exception:
        return False


def shred(path):
    try:
        size = path.stat().st_size
        with open(path, "r+b") as f:
            f.write(os.urandom(size))
            f.flush()
            os.fsync(f.fileno())
    except Exception:
        pass
    try:
        path.unlink()
    except Exception:
        pass


def guess_format(path):
    head = ""
    try:
        head = path.read_text(errors="replace").splitlines()[0].lower()
    except Exception:
        pass
    # Firefox export header has httpRealm/formActionOrigin/guid; Chromium's is
    # name,url,username,password[,note].
    if "httprealm" in head or "formactionorigin" in head or "guid" in head:
        return "firefoxcsv"
    return "chromecsv"


def do_passwords():
    PW_INBOX.mkdir(parents=True, exist_ok=True)
    help_text = EXPORT_HELP.format(inbox=PW_INBOX)
    if not have("bw"):
        print("browser-sync: the Bitwarden CLI (bw) isn't installed.")
        return 1
    csvs = sorted(PW_INBOX.glob("*.csv"))
    if not csvs:
        print(help_text)
        return 0
    if not bw_logged_in():
        print("browser-sync: Bitwarden is locked or not logged in. Run:")
        print("    bw login        # first time only")
        print("    export BW_SESSION=$(bw unlock --raw)")
        print("then re-run `browser-sync passwords`.")
        return 1
    ok = 0
    for csv in csvs:
        fmt = guess_format(csv)
        print(f"browser-sync: importing {csv.name} into Bitwarden as {fmt}…")
        r = subprocess.run(["bw", "import", fmt, str(csv)], capture_output=True, text=True)
        if r.returncode == 0:
            shred(csv)
            ok += 1
            print(f"             done, shredded {csv.name}")
        else:
            print(f"             FAILED: {r.stderr.strip() or r.stdout.strip()}")
            print(f"             left {csv.name} in place so you can retry.")
    if ok:
        subprocess.run(["bw", "sync"], capture_output=True, text=True)
        print(f"browser-sync: imported {ok} file(s) and synced your vault.")
    return 0


# ── main ─────────────────────────────────────────────────────────────────────
def main(argv):
    cmd = argv[0] if argv else "sync"
    if cmd in ("-h", "--help", "help"):
        print(__doc__.strip())
        return 0
    if cmd == "export":
        return do_export()
    if cmd == "import":
        return do_import(argv[1:])
    if cmd in ("passwords", "pw"):
        return do_passwords()
    if cmd in ("bookmarks", "sync"):
        rc = do_export()
        do_import([])
        return rc
    print(f"browser-sync: unknown command '{cmd}'. Try: export | import | passwords")
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
