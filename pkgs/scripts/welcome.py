# welcome — parajynx's first-run setup, in a window.
#
# Opens by itself at your first login (and any time from the menu: System →
# Welcome / setup). Five steps, each optional:
#   1. what you'll use this machine for (modules: Gaming, Code, Electronics…)
#   2. Tailscale: sign in (your devices + home server, from anywhere)
#   3. the VPN: drop in a WireGuard config
#   4. backups: the passphrase, and a first backup
#   5. bring your files over from another machine's backup
# Then Apply: one terminal window saves your choices and rebuilds (you type
# your password once there).
#
# A small web page served on 127.0.0.1 only, opened as an app window. Every
# request must carry the random token in the page's address, so no website
# (or other user) can drive it.

import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DATA = json.loads(Path(os.environ["WELCOME_DATA"]).read_text())
TOKEN = secrets.token_urlsafe(24)
HOME = Path.home()
STATE = HOME / ".local/state/nix2"
PWFILE = HOME / ".config/restic/password"
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$")
last_seen = time.time()


def run(args, timeout=10):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)


def modules_on():
    try:
        return set(Path("/etc/nix2/modules").read_text().split())
    except OSError:
        return set()


def tailscale():
    code, out = run(["tailscale", "status", "--json"])
    try:
        st = json.loads(out) if out.startswith("{") else {}
    except ValueError:
        st = {}
    peers = sorted(
        (p.get("HostName") or "").lower()
        for p in (st.get("Peer") or {}).values()
        if p.get("HostName")
    )
    ips = (st.get("Self") or {}).get("TailscaleIPs") or []
    return {
        "state": st.get("BackendState", "NoState" if code else "Unknown"),
        "ip": next((i for i in ips if "." in i), ""),
        "peers": peers,
    }


def vpn():
    have, _ = run(["nmcli", "-g", "connection.uuid", "connection", "show", "id", "parajynx-vpn"])
    _, active = run(["nmcli", "-t", "-f", "NAME", "connection", "show", "--active"])
    return {"configured": have == 0, "connected": "parajynx-vpn" in active.split()}


def machines(server):
    if not server:
        return []
    try:
        with urllib.request.urlopen(f"http://{server}/backups.json", timeout=4) as r:
            return [m for m in json.load(r) if NAME_RE.match(m.get("name", ""))]
    except (OSError, ValueError):
        return []


def state():
    server = DATA.get("homelabServer", "")
    return {
        "name": DATA["name"],
        "hostname": DATA["hostname"],
        "modules": [dict(m, on=m["id"] in modules_on()) for m in DATA["modules"]],
        "tailscale": tailscale(),
        "vpn": vpn(),
        "backup": {"passphrase": PWFILE.exists() or Path("/run/secrets/restic-password").exists(),
                   "server": server, "repo": os.environ.get("BACKUP_REPO", "")},
        "machines": [m for m in machines(server) if m["name"] != DATA["hostname"]],
    }


def terminal(script, *args):
    """Run a shell script (with "$@" = args) in a terminal that waits for Enter."""
    body = script + '\necho; printf "Done. Press Enter to close. "; read -r _'
    subprocess.Popen(["st", "-t", "parajynx setup", "-e", "sh", "-c", body, "sh", *args],
                     start_new_session=True)


def tailscale_login():
    # `login`, not `up`: `up` refuses to run once other settings (the operator,
    # accept-routes…) are set unless every one of them is repeated.
    p = subprocess.Popen(["tailscale", "login", "--timeout=10m"],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         start_new_session=True)
    deadline = time.time() + 20
    while time.time() < deadline:
        line = p.stdout.readline()
        if not line:
            break
        m = re.search(r"https://login\.tailscale\.com/\S+", line)
        if m:
            subprocess.Popen(["xdg-open", m.group(0)], start_new_session=True)
            threading.Thread(target=p.wait, daemon=True).start()
            return {"url": m.group(0)}
    if p.poll() == 0 or tailscale()["state"] == "Running":
        return {"ok": True}
    return {"error": "Tailscale didn't give a sign-in link. Menu → Network & privacy → Tailscale tries in a terminal."}


def add_vpn(text):
    if "[Interface]" not in text or "PrivateKey" not in text:
        return {"error": "That isn't a WireGuard config (it should contain [Interface] and PrivateKey)."}
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "vpn.conf"
        f.write_text(text)
        f.chmod(0o600)
        code, out = run(["vpn", "add", str(f)], timeout=30)
    return {"ok": code == 0, "out": out}


def set_passphrase(pw):
    if PWFILE.exists():
        return {"ok": True, "existing": True}
    made = not pw
    if made:
        pw = secrets.token_urlsafe(18)
    PWFILE.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(PWFILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(pw)
    return {"ok": True, "generated": pw if made else None}


def apply(body):
    known = {m["id"] for m in DATA["modules"]}
    now_on = modules_on()
    args = []
    for mid, want in (body.get("modules") or {}).items():
        if mid in known and bool(want) != (mid in now_on):
            args += ["module", mid, "on" if want else "off"]
    server = (body.get("homelabServer") or "").strip()
    if server and server != DATA.get("homelabServer") and NAME_RE.match(server):
        args += ["server", server]
    if not args:
        return {"ok": True, "nothing": True}
    terminal(
        'echo "Saving your choices (your password, once):"\n'
        'while [ $# -gt 0 ]; do\n'
        '  case "$1" in\n'
        '    module) nix2-setup module "$2" "$3" || exit 1; shift 3 ;;\n'
        '    server) nix2-setup set homelabServer "$2" || exit 1; shift 2 ;;\n'
        '    *) shift ;;\n'
        '  esac\n'
        'done\n'
        'echo; echo "Installing (a few minutes the first time)…"; rebuild',
        *args,
    )
    return {"ok": True}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, obj, code=200, ctype="application/json"):
        data = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authed(self):
        global last_seen
        if secrets.compare_digest(self.headers.get("X-Token", ""), TOKEN):
            last_seen = time.time()
            return True
        self.reply({"error": "forbidden"}, 403)
        return False

    def do_GET(self):
        if self.path.split("?")[0] == "/":
            return self.reply(PAGE, ctype="text/html; charset=utf-8")
        if self.path == "/api/state" and self.authed():
            return self.reply(state())
        if not self.path.startswith("/api/"):
            self.reply({"error": "not found"}, 404)

    def do_POST(self):
        if not self.authed():
            return
        n = min(int(self.headers.get("Content-Length") or 0), 256 * 1024)
        raw = self.rfile.read(n) if n else b""
        try:
            body = json.loads(raw or b"{}")
        except ValueError:
            body = {}
        p = self.path
        if p == "/api/tailscale":
            return self.reply(tailscale_login())
        if p == "/api/vpn":
            return self.reply(add_vpn(body.get("config", "")))
        if p == "/api/passphrase":
            return self.reply(set_passphrase(body.get("passphrase", "")))
        if p == "/api/backup":
            subprocess.Popen(["backup", "now"], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return self.reply({"ok": True})
        if p == "/api/bring":
            m = body.get("machine", "")
            if not NAME_RE.match(m):
                return self.reply({"error": "bad name"}, 400)
            terminal('backup bring "$1"', m)
            return self.reply({"ok": True})
        if p == "/api/apply":
            return self.reply(apply(body))
        if p == "/api/done":
            STATE.mkdir(parents=True, exist_ok=True)
            (STATE / "welcomed").touch()
            self.reply({"ok": True})
            threading.Timer(0.5, lambda: os._exit(0)).start()
            return
        self.reply({"error": "not found"}, 404)


def main():
    if "--if-new" in sys.argv and (STATE / "welcomed").exists():
        return
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    url = f"http://127.0.0.1:{srv.server_address[1]}/?t={TOKEN}"
    browser = shutil.which("brave") or shutil.which("chromium")
    if browser:
        subprocess.Popen([browser, f"--app={url}", "--window-size=880,860"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.Popen(["xdg-open", url], start_new_session=True)
    print(f"welcome: {url}")

    def idle():   # nobody's looked for 30 minutes: stop
        while time.time() - last_seen < 1800:
            time.sleep(30)
        os._exit(0)
    threading.Thread(target=idle, daemon=True).start()
    srv.serve_forever()


C = DATA["colors"]
PAGE = ("""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Welcome to @@NAME@@</title>
<style>
:root{--bg:@@BG@@;--fg:@@FG@@;--dim:@@DIM@@;--acc:@@ACC@@;--card:color-mix(in srgb,var(--fg) 5%,var(--bg));
--line:color-mix(in srgb,var(--fg) 12%,var(--bg))}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);
font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:760px;margin:0 auto;padding:40px 24px 80px}
h1{font-size:30px;font-weight:600;margin:0 0 4px;letter-spacing:-.01em}
.sub{color:var(--dim);margin:0 0 28px}
section{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:20px 22px;margin:14px 0}
h2{font-size:17px;margin:0 0 4px;display:flex;align-items:center;gap:10px}
h2 .n{width:24px;height:24px;border-radius:50%;display:inline-grid;place-items:center;font-size:13px;
background:var(--line);color:var(--fg)}h2 .n.ok{background:var(--acc);color:var(--bg)}
p{margin:6px 0 12px;color:color-mix(in srgb,var(--fg) 80%,var(--bg))}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:8px}
label.mod{display:flex;gap:10px;align-items:flex-start;padding:10px 12px;border:1px solid var(--line);
border-radius:10px;cursor:pointer}label.mod:has(input:checked){border-color:var(--acc)}
label.mod b{display:block;font-weight:600}label.mod small{color:var(--dim)}
input[type=checkbox]{accent-color:var(--acc);margin-top:4px}
button{font:inherit;background:var(--acc);color:var(--bg);border:0;border-radius:9px;padding:9px 16px;
font-weight:600;cursor:pointer}button.ghost{background:transparent;color:var(--fg);border:1px solid var(--line)}
button:disabled{opacity:.5;cursor:default}
input[type=text],input[type=password],select{font:inherit;background:var(--bg);color:var(--fg);
border:1px solid var(--line);border-radius:9px;padding:8px 10px;min-width:240px}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
.status{color:var(--dim);font-size:14px}.good{color:var(--acc)}
.secret{font:600 18px ui-monospace,monospace;background:var(--bg);border:1px dashed var(--acc);
padding:10px 14px;border-radius:9px;display:inline-block;user-select:all}
.drop{border:1px dashed var(--line);border-radius:10px;padding:16px;text-align:center;color:var(--dim)}
.drop.over{border-color:var(--acc);color:var(--fg)}
footer{display:flex;justify-content:space-between;gap:10px;margin-top:22px}
</style></head><body><main>
<h1>Welcome to @@NAME@@</h1>
<p class="sub">A few choices and this machine is yours. Every step is optional, and you can come back any time: menu → System → Welcome / setup.</p>

<section><h2><span class="n" id="n1">1</span>What will you use it for?</h2>
<p>Turn on what you need; everything else stays off so the system stays small and fast.</p>
<div class="grid" id="mods"></div>
<div class="row" style="margin-top:12px"><span class="status">Saved and installed when you press <b>Apply</b> at the bottom.</span></div>
</section>

<section><h2><span class="n" id="n2">2</span>Tailscale: your devices, anywhere</h2>
<p>Connects this machine to your phone, other computers and home server, privately and from any network.</p>
<div class="row"><button id="tsbtn">Sign in to Tailscale</button><span class="status" id="ts"></span></div>
<div class="row" id="srvrow" style="margin-top:12px;display:none">
<span>Home server:</span><select id="srv"></select>
<span class="status">its services show in your menu, and this machine backs up to it</span></div>
</section>

<section><h2><span class="n" id="n3">3</span>VPN</h2>
<p>Optional, and off until you switch it on: menu → Network & privacy → VPN (or <code>vpn on</code>). When on it
connects by itself and steps aside on any network where it doesn't work, so it never costs you the internet. Get a WireGuard config from
your VPN account (Proton: account → Downloads → WireGuard configuration), then drop the file here.</p>
<div class="drop" id="drop">Drop the <b>.conf</b> file here, or <a href="#" id="pick" style="color:var(--acc)">choose it</a>
<input type="file" id="file" accept=".conf" hidden></div>
<p class="status" id="vpn"></p>
</section>

<section><h2><span class="n" id="n4">4</span>Backups</h2>
<p id="bkwhere"></p>
<div id="bkset"><p>Your backups are encrypted with a passphrase. Use the same one on all your machines.</p>
<div class="row"><input type="password" id="pw" placeholder="your backup passphrase">
<button id="pwbtn">Use it</button><button class="ghost" id="genbtn">Make one for me</button></div></div>
<div id="bkmade" style="display:none"><p>Your backup passphrase. <b>Save it in Proton Pass now:</b> without it nobody, not even you, can restore.</p>
<div class="secret" id="secret"></div></div>
<div class="row" id="bknow" style="display:none;margin-top:12px"><button id="nowbtn">Back up now</button>
<span class="status" id="bk"></span></div>
</section>

<section id="bring" style="display:none"><h2><span class="n" id="n5">5</span>Bring your files over</h2>
<p>Setting up a new or reinstalled computer? Copy your home folder and modules from another machine's backup.</p>
<div class="row"><select id="mach"></select><button id="bringbtn" class="ghost">Bring them over</button></div>
</section>

<footer><button class="ghost" id="later">Later</button><button id="apply">Apply</button></footer>
<p class="status" id="msg" style="text-align:right"></p>
</main>
<script>
const T=new URLSearchParams(location.search).get("t");
const $=id=>document.getElementById(id);
const api=(p,b)=>fetch(p,{method:b===undefined?"GET":"POST",headers:{"X-Token":T,"Content-Type":"application/json"},
  body:b===undefined?undefined:JSON.stringify(b)}).then(r=>r.json());
let S=null,choices={};
function ok(n,v){$("n"+n).classList.toggle("ok",!!v);if(v)$("n"+n).textContent="✓"}
async function refresh(){
  S=await api("/api/state");
  if(!$("mods").children.length){
    for(const m of S.modules){choices[m.id]=m.on;
      const l=document.createElement("label");l.className="mod";
      l.innerHTML=`<input type="checkbox" ${m.on?"checked":""}><span><b></b><small></small></span>`;
      l.querySelector("b").textContent=m.title;l.querySelector("small").textContent=m.desc;
      l.querySelector("input").onchange=e=>choices[m.id]=e.target.checked;$("mods").append(l);}
  }
  const ts=S.tailscale, on=ts.state==="Running";
  $("ts").innerHTML=on?`<span class="good">Connected</span> · ${ts.ip}`:"Not signed in yet";
  $("tsbtn").style.display=on?"none":"";ok(2,on);
  if(on&&ts.peers.length){$("srvrow").style.display="";
    if(!$("srv").options.length){$("srv").append(new Option("(none)",""));
      for(const p of ts.peers)$("srv").append(new Option(p,p));$("srv").value=S.backup.server||"";}}
  if(S.vpn.configured)$("vpn").innerHTML=S.vpn.connected?'<span class="good">VPN connected.</span>':"VPN set up (off until you switch it on).";
  ok(3,S.vpn.configured);
  $("bkwhere").textContent=S.backup.server?`Every day, your files go to your home server (${S.backup.server}) over Tailscale: encrypted, with 7 days, 4 weeks and 6 months of history.`
    :"Every day, to an external drive labelled BACKUP when it's plugged in (pick a home server above to back up there instead, from anywhere).";
  $("bkset").style.display=S.backup.passphrase?"none":"";$("bknow").style.display=S.backup.passphrase?"":"none";
  ok(4,S.backup.passphrase);
  if(S.machines.length){$("bring").style.display="";if(!$("mach").options.length)
    for(const m of S.machines)$("mach").append(new Option(`${m.name}  (last backup ${m.updated})`,m.name));}
  ok(1,true);
}
$("tsbtn").onclick=async()=>{$("tsbtn").disabled=true;$("ts").textContent="Opening the sign-in page…";
  const r=await api("/api/tailscale",{});$("tsbtn").disabled=false;
  $("ts").textContent=r.error||(r.url?"Finish signing in in the browser…":"");poll(60);};
function poll(n){if(n>0)setTimeout(async()=>{await refresh();if(S.tailscale.state!=="Running")poll(n-1)},3000)}
const drop=$("drop");$("pick").onclick=e=>{e.preventDefault();$("file").click()};
$("file").onchange=e=>sendVpn(e.target.files[0]);
drop.ondragover=e=>{e.preventDefault();drop.classList.add("over")};drop.ondragleave=()=>drop.classList.remove("over");
drop.ondrop=e=>{e.preventDefault();drop.classList.remove("over");sendVpn(e.dataTransfer.files[0])};
async function sendVpn(f){if(!f)return;$("vpn").textContent="Adding…";
  const r=await api("/api/vpn",{config:await f.text()});
  $("vpn").textContent=r.error||(r.ok?"Added (off). Switch it on: menu → Network & privacy → VPN. You can delete the downloaded file now.":r.out);refresh();}
async function pass(pw){const r=await api("/api/passphrase",{passphrase:pw});
  if(r.generated){$("secret").textContent=r.generated;$("bkmade").style.display=""}refresh();}
$("pwbtn").onclick=()=>{const v=$("pw").value.trim();if(v.length<8){alert("At least 8 characters.");return}pass(v)};
$("genbtn").onclick=()=>pass("");
$("nowbtn").onclick=async()=>{await api("/api/backup",{});$("bk").textContent="Backing up in the background; a notification says when it's done."};
$("bringbtn").onclick=()=>api("/api/bring",{machine:$("mach").value});
$("apply").onclick=async()=>{const r=await api("/api/apply",{modules:choices,homelabServer:$("srv").value||""});
  $("msg").textContent=r.nothing?"Nothing to change.":"A terminal opened: type your password there, and it installs.";
  await api("/api/done",{});};
$("later").onclick=async()=>{await api("/api/done",{});window.close()};
refresh();setInterval(refresh,15000);
</script></body></html>""".replace("@@NAME@@", DATA["name"]).replace("@@BG@@", C["background"])
        .replace("@@FG@@", C["text"]).replace("@@DIM@@", C["dim"]).replace("@@ACC@@", C["accent"])).encode()

if __name__ == "__main__":
    main()
