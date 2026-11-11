# site-push — publish a folder to its Neocities site.
#
#   site-push                  pick a folder from a menu, publish it
#   site-push DIR              publish DIR (or the git repo it's inside)
#   site-push --dry-run DIR    show what would change, change nothing
#   site-push --prune DIR      also delete site files that aren't in the folder (asks first)
#   site-push key SITE         set or replace SITE's API key
#   site-push sites            your sites, and which folders publish where
#
# Which site a folder goes to lives in a `.neocities` file at the repo root
# (made the first time you publish it; commit it — it holds no secrets):
#     site  = "mysite"            # → https://mysite.neocities.org
#     dir   = "public"            # what to publish, relative to the repo (default ".")
#     build = "npm run build"     # optional, runs before uploading
# API keys never touch the repo: they live in your keyring (the same one
# Proton VPN uses). Before uploading, the key is checked against Neocities to
# make sure it really belongs to that site — so a folder can't land on the
# wrong one. Only changed files are sent (compared by SHA-1), in a few
# sequential requests, as Neocities asks.
import getpass
import hashlib
import json
import os
import subprocess
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request
import uuid

API = os.environ.get("NEOCITIES_API", "https://neocities.org/api")
HOME = os.path.expanduser("~")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "neocities")
KEYDIR = os.path.join(CONF, "keys")                # fallback when there's no keyring
RECENT = os.path.join(CONF, "recent")
SEARCH = [os.path.join(HOME, "projects"), HOME]
GUESSES = ["public", "dist", "_site", "build", "site", "www", "docs", "out"]
BATCH_FILES, BATCH_BYTES = 40, 40 * 1024 * 1024
GUI = not sys.stdin.isatty() or os.environ.get("SITE_PUSH_GUI") == "1"


class Fail(Exception):
    pass


# ── talking to people ───────────────────────────────────────────────────────
def say(msg):
    print(msg, flush=True)


def notify(msg, urgent=False):
    subprocess.run(["notify-send", "-a", "Neocities", "-u", "critical" if urgent else "normal",
                    "-i", "web-browser", "Neocities", msg], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def dmenu(prompt, options=(), password=False):
    cmd = ["dmenu", "-i", "-l", "20", "-p", prompt] + (["-P"] if password else [])
    try:
        r = subprocess.run(cmd, input="\n".join(options), capture_output=True, text=True)
    except FileNotFoundError:
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def ask(prompt, options=(), password=False, default=None):
    if GUI:
        return dmenu(prompt, options, password)
    if options:
        for i, o in enumerate(options, 1):
            say(f"  {i}) {o}")
    a = getpass.getpass(prompt + " ") if password else input(prompt + (f" [{default}]" if default else "") + " ")
    a = a.strip() or (default or "")
    if options and a.isdigit() and 1 <= int(a) <= len(options):
        return options[int(a) - 1]
    return a or None


def confirm(question):
    a = ask(question + " (yes/no)", ["no", "yes"]) if GUI else ask(question + " [y/N]")
    return bool(a) and a.lower() in ("y", "yes")


# ── API ─────────────────────────────────────────────────────────────────────
def call(method, endpoint, key, params=None, files=None):
    url = f"{API}/{endpoint}"
    headers = {"Authorization": f"Bearer {key}", "User-Agent": "site-push (NixOS nix²)"}
    data = None
    if files is not None:
        boundary = uuid.uuid4().hex
        body = bytearray()
        for site_path, local in files:
            with open(local, "rb") as f:
                content = f.read()
            field = site_path.replace('"', "%22")
            body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{field}\"; "
                     f"filename=\"{os.path.basename(field)}\"\r\n"
                     "Content-Type: application/octet-stream\r\n\r\n").encode()
            body += content + b"\r\n"
        body += f"--{boundary}--\r\n".encode()
        data = bytes(body)
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif method == "POST":
        data = urllib.parse.urlencode(params or {}, doseq=True).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        try:
            body = json.load(e)
        except ValueError:
            body = {"message": f"HTTP {e.code}"}
        if e.code == 403:
            raise Fail("Neocities rejected the API key (it may have been regenerated) — run: site-push key SITE")
        return {"result": "error", **body}
    except urllib.error.URLError as e:
        raise Fail(f"couldn't reach Neocities: {e.reason}")


# ── keys: keyring first, a 0600 file if there's no keyring ──────────────────
def get_key(site):
    try:
        r = subprocess.run(["secret-tool", "lookup", "service", "neocities", "site", site],
                           capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    try:
        with open(os.path.join(KEYDIR, site), encoding="utf-8") as f:
            return f.read().strip() or None
    except OSError:
        return None


def save_key(site, key):
    try:
        r = subprocess.run(["secret-tool", "store", f"--label=Neocities: {site}", "service", "neocities", "site", site],
                           input=key, text=True, capture_output=True, timeout=10)
        if r.returncode == 0:
            return "your keyring"
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    os.makedirs(KEYDIR, mode=0o700, exist_ok=True)
    path = os.path.join(KEYDIR, site)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(key + "\n")
    return path


def whose(key):
    r = call("GET", "info", key)
    if r.get("result") != "success":
        raise Fail(f"Neocities: {r.get('message', 'unknown error')}")
    return r["info"]


def ensure_key(site, replace=False):
    key = None if replace else get_key(site)
    while True:
        if key is None:
            say(f"Paste the API key for {site}: neocities.org → Settings → {site} → API key.")
            key = ask(f"API key for {site}:", password=True)
            if not key:
                raise Fail("no API key given")
            fresh = True
        else:
            fresh = False
        info = whose(key)
        if info["sitename"].lower() != site.lower():
            msg = f"that key belongs to '{info['sitename']}', not '{site}'"
            if not fresh:
                raise Fail(msg + " — run: site-push key " + site)
            say(msg + " — try again.")
            key = None
            continue
        if fresh:
            say(f"Saved the key for {site} in {save_key(site, key)}.")
        return key, info


# ── which folder, which site ────────────────────────────────────────────────
def repo_root(path):
    r = subprocess.run(["git", "-C", path, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else os.path.abspath(path)


def read_conf(root):
    p = os.path.join(root, ".neocities")
    if not os.path.isfile(p):
        return None
    try:
        with open(p, "rb") as f:
            c = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        raise Fail(f"{p} isn't valid: {e}")
    if not c.get("site"):
        raise Fail(f"{p} needs a line like: site = \"mysite\"")
    return c


def known_sites():
    sites = set()
    if os.path.isdir(KEYDIR):
        sites.update(os.listdir(KEYDIR))
    try:
        r = subprocess.run(["secret-tool", "search", "--all", "service", "neocities"],
                           capture_output=True, text=True, timeout=10)
        for line in (r.stdout + r.stderr).splitlines():
            if line.strip().startswith("attribute.site = "):
                sites.add(line.split("=", 1)[1].strip())
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return sorted(sites)


def first_time(root):
    say(f"{root} isn't linked to a Neocities site yet.")
    sites = known_sites()
    site = ask("Which Neocities site? (the name in name.neocities.org)", sites)
    if not site:
        raise Fail("no site chosen")
    site = site.strip().lower().removesuffix(".neocities.org")
    opts = ["."] + [g for g in GUESSES if os.path.isdir(os.path.join(root, g))]
    sub = ask("Which folder is the website? ('.' = the whole repo)", opts, default=".") or "."
    with open(os.path.join(root, ".neocities"), "w", encoding="utf-8") as f:
        f.write(f'# Where `site-push` publishes this folder. No secrets here — commit it.\n'
                f'site = "{site}"\ndir = "{sub}"\n# build = "npm run build"   # optional, runs first\n')
    say(f"Saved {root}/.neocities (site = {site}, dir = {sub}).")
    return {"site": site, "dir": sub}


def remember(root):
    os.makedirs(CONF, exist_ok=True)
    rows = [root]
    try:
        with open(RECENT, encoding="utf-8") as f:
            rows += [r.strip() for r in f if r.strip() and r.strip() != root]
    except OSError:
        pass
    with open(RECENT, "w", encoding="utf-8") as f:
        f.write("\n".join(rows[:20]) + "\n")


def candidates():
    """Linked folders first (recent, then found), then other git repos."""
    linked, repos, seen = [], [], set()
    try:
        with open(RECENT, encoding="utf-8") as f:
            for r in f:
                r = r.strip()
                if r and os.path.isfile(os.path.join(r, ".neocities")) and r not in seen:
                    linked.append(r); seen.add(r)
    except OSError:
        pass
    for base in SEARCH:
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            d = os.path.join(base, name)
            if name.startswith(".") or not os.path.isdir(d) or d in seen:
                continue
            if os.path.isfile(os.path.join(d, ".neocities")):
                linked.append(d); seen.add(d)
            elif os.path.isdir(os.path.join(d, ".git")):
                repos.append(d); seen.add(d)
    return linked, repos


def pick_folder():
    linked, repos = candidates()
    rows, where = [], {}
    for d in linked:
        try:
            label = f"{read_conf(d)['site']}.neocities.org  ←  {d.replace(HOME, '~')}"
        except Fail:
            label = d.replace(HOME, "~")
        rows.append(label); where[label] = d
    for d in repos:
        label = f"(not linked yet)  {d.replace(HOME, '~')}"
        rows.append(label); where[label] = d
    other = "Choose another folder…"
    rows.append(other)
    sel = ask("Publish which folder to Neocities?", rows)
    if not sel:
        return None
    if sel == other:
        try:
            r = subprocess.run(["zenity", "--file-selection", "--directory", "--title=Folder to publish"],
                               capture_output=True, text=True)
            return r.stdout.strip() or None
        except FileNotFoundError:
            return ask("Folder path:")
    return where.get(sel, os.path.expanduser(sel))


# ── the publish itself ──────────────────────────────────────────────────────
def local_files(top):
    out = {}
    for dirpath, dirnames, filenames in os.walk(top):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith(".") and d != "node_modules")
        for name in sorted(filenames):
            if name.startswith(".") or name.endswith(("~", ".swp")):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, top).replace(os.sep, "/")
            h = hashlib.sha1()
            with open(full, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
            out[rel] = (full, h.hexdigest(), os.path.getsize(full))
    return out


def batches(items):
    cur, size = [], 0
    for path, (full, _h, n) in items:
        if cur and (len(cur) >= BATCH_FILES or size + n > BATCH_BYTES):
            yield cur
            cur, size = [], 0
        cur.append((path, full)); size += n
    if cur:
        yield cur


def upload(key, batch):
    """Upload a batch; if Neocities refuses it (one bad file fails the lot),
    retry one by one so the good files still go and the bad ones get named."""
    r = call("POST", "upload", key, files=batch)
    if r.get("result") == "success":
        return len(batch), []
    if len(batch) == 1:
        return 0, [(batch[0][0], r.get("message", "rejected"))]
    done, bad = 0, []
    for one in batch:
        d, b = upload(key, [one])
        done += d; bad += b
    return done, bad


def publish(path, dry=False, prune=False):
    root = repo_root(path)
    conf = read_conf(root) or first_time(root)
    site = conf["site"]
    top = os.path.normpath(os.path.join(root, conf.get("dir", ".")))
    if not os.path.isdir(top):
        raise Fail(f"{top} doesn't exist (dir = \"{conf.get('dir')}\" in {root}/.neocities)")
    if conf.get("build") and not dry:
        say(f":: building: {conf['build']}")
        if subprocess.run(conf["build"], shell=True, cwd=root).returncode != 0:
            raise Fail("the build command failed — nothing was published")
    key, info = ensure_key(site)
    url = f"https://{info['domain']}" if info.get("domain") else f"https://{site}.neocities.org"
    say(f":: {top.replace(HOME, '~')}  →  {url}")

    mine = local_files(top)
    r = call("GET", "list", key)
    if r.get("result") != "success":
        raise Fail(f"couldn't list the site: {r.get('message')}")
    theirs = {f["path"]: f.get("sha1_hash") for f in r["files"] if not f.get("is_directory")}
    changed = sorted((p, v) for p, v in mine.items() if theirs.get(p) != v[1])
    gone = sorted(p for p in theirs if p not in mine and p != "index.html")
    say(f"   {len(mine)} files here, {len(changed)} new or changed"
        + (f", {len(gone)} only on the site" if gone else "") + ".")
    if dry:
        for p, _ in changed:
            say(f"   + {p}")
        for p in gone:
            say(f"   {'- ' if prune else '  (kept) '}{p}")
        return
    sent, bad = 0, []
    for b in batches(changed):
        d, x = upload(key, b)
        sent += d; bad += x
        say(f"   uploaded {sent}/{len(changed)}")
    removed = 0
    if prune and gone:
        for p in gone[:15]:
            say(f"   - {p}")
        if len(gone) > 15:
            say(f"   … and {len(gone) - 15} more")
        if confirm(f"Delete these {len(gone)} files from {site}? This can't be undone"):
            r = call("POST", "delete", key, params={"filenames[]": gone})
            if r.get("result") == "success":
                removed = len(gone)
            else:
                say(f"   delete failed: {r.get('message')}")
    remember(root)
    for p, why in bad:
        say(f"   ✗ {p}: {why}")
    summary = (f"Published {sent} file{'s' if sent != 1 else ''} to {url}" if sent else f"{url} was already up to date")
    if removed:
        summary += f", removed {removed}"
    if bad:
        summary += f" — {len(bad)} file(s) refused (see terminal)"
    say(summary)
    notify(summary, urgent=bool(bad))


def list_sites():
    linked, _ = candidates()
    sites = known_sites()
    say("Sites with a saved key: " + (", ".join(sites) if sites else "none yet"))
    for d in linked:
        try:
            c = read_conf(d)
            say(f"  {c['site']}.neocities.org  ←  {d.replace(HOME, '~')}/{c.get('dir', '.')}")
        except Fail as e:
            say(f"  ? {d}: {e}")


def main(argv):
    dry = "--dry-run" in argv
    prune = "--prune" in argv
    args = [a for a in argv if a not in ("--dry-run", "--prune")]
    if args and args[0] in ("-h", "--help", "help"):
        with open(__file__, encoding="utf-8") as f:
            for line in f:
                if not line.startswith("#"):
                    break
                if line.startswith("#!"):
                    continue
                print(line[2:].rstrip())
        return 0
    try:
        if args and args[0] == "key":
            if len(args) < 2:
                raise Fail("usage: site-push key SITE")
            ensure_key(args[1].lower().removesuffix(".neocities.org"), replace=True)
            return 0
        if args and args[0] == "sites":
            list_sites()
            return 0
        path = args[0] if args else pick_folder()
        if not path:
            return 0
        publish(os.path.expanduser(path), dry=dry, prune=prune)
        return 0
    except Fail as e:
        say(f"site-push: {e}")
        notify(str(e), urgent=True)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
