# Your home server (the `homelab` module)

One parajynx desktop that also runs your own services 24/7, reachable from your phone, laptop and other
machines over **Tailscale**, and from nowhere else.

```
 phone / laptop / other desktop ──Tailscale (encrypted)──▶ live
                                                           ├─ Caddy :80  → git.home.arpa, cloud.home.arpa, …
                                                           ├─ Pi-hole :53 → answers those names, blocks ads
                                                           ├─ Gitea · Nextcloud · FreshRSS · SearXNG
                                                           ├─ Transmission ──only through──▶ Proton VPN
                                                           └─ Minecraft (Crafty), off until you turn it on
```

## What runs

| Service | Name (via the proxy) | Direct | Notes |
|---|---|---|---|
| Start page | `http://home.home.arpa` or `http://live/` | | Lists everything below |
| Pi-hole | `http://pihole.home.arpa` | `live:8053` | Ad-blocking DNS; no password (tailnet only) |
| Gitea | `http://git.home.arpa` | `live:3002`, ssh `live:2222` | Your git server |
| Nextcloud | `http://cloud.home.arpa` | `live:8091` | Calendar, contacts, files |
| FreshRSS | `http://rss.home.arpa` | `live:8090` | Works with phone RSS apps (API on) |
| Transmission | `http://torrent.home.arpa` | `live:9091` | Only through Proton VPN (kill switch) |
| SearXNG | `http://search.home.arpa` | `live:8888` | Private search |
| Minecraft panel | `http://minecraft.home.arpa` | `https://live:8443` | Crafty; **off by default** |

`live` stands for this machine's Tailscale name (its host name). Every one of these can be switched off in
`settings.local.nix`, e.g. `homelab.rss = false;` removes FreshRSS (its tile, name and menu entry go too).

The names work on the server itself as well: they're in its hosts file, pointing at itself, so they
never depend on DNS there. It still asks its own Pi-hole first for everything else (ad-blocking).

**Who can reach what:**
- **Web pages** are open only on the Tailscale interface. Add `homelab.lan = true;` to also open them to your home Wi-Fi.
- **Pi-hole's DNS port (53)** is open on the LAN, so your router can use it.
- **Minecraft game ports** (Java 25565–25575, Bedrock 19132/udp) are open to your home network and your tailnet. They don't go through a VPN or anything else.
- **The internet** reaches nothing, unless you forward a port on your router yourself.

## First-time setup

1. **Turn it on:** `mod on homelab` (rebuilds).
2. **Join Tailscale:** `sudo tailscale up`, sign in, then `tailscale ip -4` shows this machine's `100.x`
   address. Install the Tailscale app on your phone and laptop with the same account.
3. **Tailscale DNS (the important one).** login.tailscale.com/admin/dns → **Nameservers → Add nameserver →
   Custom** → the `100.x` address from step 2 → turn on **Override DNS servers**. Now every device on your
   tailnet:
   - uses Pi-hole (ads blocked on your phone, even on mobile data),
   - can open the `*.home.arpa` names.
   This machine itself is set not to use the tailnet's DNS, so it never asks itself in a loop.
4. **Passwords:** `homelab passwords`. They're made on this machine and never go into git.
5. **Gitea account:** `homelab git-admin`. It prints a first password, which you change at first login.
6. **Check:** `homelab status` lists every service, whether it's running, and whether the names resolve.

`homelab setup` prints these steps (and the BenOS / VPN / Minecraft ones) any time.

## Keep it locked down

Your tailnet is the only way in, so secure it: two-factor on your sign-in, approve new devices yourself,
and an access policy that gives friends Minecraft and nothing else. Step by step, with a policy to paste:
[TAILSCALE.md](TAILSCALE.md).

## Bridges: your home network and an exit node (optional)

Tailscale already connects your devices to this machine's services. Two more bridges, each one line in
`settings.local.nix` then `nixup`:

| Setting | What it does | Then |
|---|---|---|
| `homelab.lanSubnet = "192.168.1.0/24";` | Devices on your home network that can't run Tailscale (printer, router page, a Pi) become reachable from anywhere on your tailnet | Admin page → Machines → this machine → ⋯ → **Edit route settings** → tick the subnet |
| `homelab.exitNode = true;` | Your phone or laptop can send all its internet through home, e.g. on public Wi-Fi | Same page → tick **Use as exit node**; then on the phone: Tailscale → Exit node → this machine |

Find your home network's range with `ip -4 route | grep -v tailscale` (the line with `src`, e.g.
`192.168.1.0/24`). Remove a setting and `nixup` and the bridge is withdrawn: the flags are restated at
every boot. On Linux clients, accept routes with `sudo tailscale set --accept-routes`; phones do it
automatically.

## Names vs ports

The names (`git.home.arpa`) need step 3. Until then, or on a device that doesn't use Tailscale DNS, the
direct addresses (`http://live:3002`) always work. `home.arpa` is reserved for home networks, so the names
can never collide with a real website. Change it with `homelab.domain = "…";`. Turn the proxy off
completely with `homelab.proxy = false;`, and every link goes back to `live:port`.

## Your other desktops pick it up by themselves

Tailscale is on every parajynx machine already; sign each one in once (menu → Network & privacy →
"Tailscale: sign in", or `sudo tailscale up --accept-routes`). Then add to its `settings.local.nix`:

```nix
homelabServer = "live";
```

and rebuild. Its menu (**Super+Alt+d**, or Super+Alt+Space → Self-hosted) then lists all of this server's
services. A timer refreshes the list at login and every 30 minutes, so services you add later show up
without touching that machine. It uses the nice names when that machine can resolve them, otherwise
`live:port`. Refresh by hand with `homelab-discover`.

On the server itself the services are already in its own menu, plus a **Homelab** and a **Minecraft** menu.

## Your BenOS dashboard

Set `homelab.benos.url = "https://dash.bnvac.com";`, then follow `homelab setup` steps 5–6 (add the
server on BenOS's Lab page and paste the agent token into `/etc/benos-agent.env`). The agent then registers
every service on the Lab page with up/down and uptime. Minecraft is left off the health checks on purpose:
it's off most of the time and would always show red.

## Minecraft

| Do this | How |
|---|---|
| Turn on | `homelab minecraft on`, or menu → Minecraft → turn ON |
| Turn off | `homelab minecraft off` (saves worlds, up to 2 minutes) |
| Is it on? | `homelab minecraft status` |
| Control panel | `http://minecraft.home.arpa` (or `https://live:8443`, accept the certificate warning once) |
| First login | `homelab passwords` after the first start; change it in the panel |

It never starts at boot, and turning it on or off needs no password. The first start downloads the panel
(about 1 GB), so give it a few minutes.

**Make a server:** in the panel, **Create New Server** → pick the type:
- **Fabric** or **NeoForge/Forge** for mods,
- **Paper** for plugins (lighter, vanilla-compatible),
- **Vanilla** for plain Minecraft.
Pick the Minecraft version, give it RAM (4–6 GB is comfortable for a modded server), then Create.

**Add mods:**
1. In the server → **Files** → `mods/`, upload the `.jar` files. Use mods made for the same loader and
   Minecraft version: Modrinth and CurseForge show both.
2. Restart the server from the panel.
3. Players need the same mods on their side. Prism Launcher (already on parajynx) can install the matching
   pack in one click.

For a whole modpack, download its **server pack** zip and use **Import Server** → upload the zip.

**Who can join:**
- **Your home network:** this machine's LAN address with port `25565`.
- **Anywhere on your tailnet:** `live:25565`. Friends can join your tailnet as guests through a
  Tailscale share, which is free.
- **The public internet:** only if you forward port 25565 on your router to this machine. Then anyone can
  try to connect, so turn on the whitelist in the panel first.

**Keep it running:** in the panel, set a server to **start with Crafty** if you want it to come up every
time you turn Minecraft on. Set up **Backups** per server in the panel. Backups are saved under
`/var/lib/crafty/backups`.

## Torrents and Proton VPN

Transmission runs in its own network namespace whose only way out is a Proton WireGuard tunnel. If the VPN
is down, torrents have no internet at all; nothing falls back to your home IP. Setup is `homelab setup`
step 7 (download a WireGuard config from Proton with **NAT-PMP** on, from a P2P server).
`homelab vpn` shows the state, and you get a desktop notification whenever it goes up or down.

## Troubleshooting

| Problem | Try |
|---|---|
| `git.home.arpa` doesn't open | `live:3002` works? Then it's DNS: redo setup step 3, then toggle Tailscale off/on on that device |
| Nothing opens from the phone | Is the Tailscale app connected? `tailscale status` on the server |
| A service is down | `homelab status`, then `journalctl -u <name> -e` |
| Minecraft panel doesn't load | `homelab minecraft status`; the first start takes a few minutes; `journalctl -u docker-crafty -e` |
| Friends can't join Minecraft | Same version and mods? On your tailnet? Port 25565 in the server's settings? |
| Search returns little | `homelab search-test` lists which engines fail and why. Big engines block home IPs now and then; it usually clears within a day |
| Names don't open on the server itself | `getent hosts git.home.arpa` should print `127.0.0.1`. If it does but the browser fails, turn off Brave's Settings → Privacy → **Use secure DNS** |
| Torrents stuck | `homelab vpn`: if OFFLINE, check `/etc/homelab/protonvpn.conf` and `systemctl status torrent-netns` |

Everything is plain NixOS underneath: `modules/homelab.nix` is the whole server, one section per service.
