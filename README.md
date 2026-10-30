# samadams — modular NixOS

A LARBS-style dwm desktop plus an electronics / 3D-printing / gaming / AI
workstation, split into toggleable modules. One config for two machines (a
desktop with an RX 6750 XT, and a laptop) — `settings.nix` says which is which.

## Layout

```
configuration.nix     imports core + every module that's switched on
picker.nix            works out which modules exist / are on (reads ./mods)
options.nix           shared options (my.syncFolders: what syncs between machines)
settings.nix          the few values you'd change (user, host, device, ESP, look)
modules/core.nix      always on: boot, net, user, audio, shell, hardening,
                      mod / modtui / nixup, and the SYSTEM.md note for Neb
modules/*.nix         one feature each (table below)
pkgs/default.nix      everything built from source (dwm/st/dmenu, Neb,
                      backoffice, devlink, SpiderFoot, GRUB theme, …)
pkgs/pins.json        which commit of YOUR repos (neb, backoffice, intraweb) to
                      build; `update-mine` keeps them current (pins.local.json)
pkgs/tracked.nix      which commit every git-built app uses (built-ins + settings.gitApps)
pkgs/gitapps.nix      how a gitApp of each type is built
pkgs/devlink/         the DeviceLink app (stdlib-only Python)
pkgs/scripts/         the small tools (apps, desk, lock, snow, rebuild, backoffice-sync…)
mods/<name>           an empty marker file = that module is ON
```

## Install

Clone it to `/etc/nixos` so `nixup` can update it later with a `git pull`:

```sh
sudo nixos-generate-config            # writes hardware-configuration.nix (keep it)
sudo mv /etc/nixos /etc/nixos.orig
sudo git clone https://github.com/bnvac/nixosconfig /etc/nixos
sudo cp /etc/nixos.orig/hardware-configuration.nix /etc/nixos/
sudo nixos-rebuild switch
```

Then run `modtui` → **Onboarding**: picks desktop/laptop, hostname, modules, an
AI model, and pairs the two machines. The build stops with instructions if the
ESP isn't mounted where `settings.nix` says.

## Modules

| module | what |
|---|---|
| desktop | dwm/st/dmenu/dwmblocks (LARBS), picom, snowy live wallpaper, lock screen, Thunar + drives, apps menu, Bluetooth GUI |
| apps | LibreOffice, browsers (+ Bitwarden), Discord/Slack, media, Calibre, torrents + Stremio, Onshape |
| assistant | Neb (voice assistant, desktop actions, own workspace) + Ollama (Vulkan) / Open-WebUI on the desktop |
| ai | Claude Code |
| sync | Syncthing between the machines, DeviceLink, bookmark export/import |
| ee | KiCad, EDA tools, OrcaSlicer (has Elegoo profiles), FreeCAD |
| printing | mDNS + printrun for Klipper printers on the LAN |
| gaming | Steam + Proton-GE, Prism Launcher |
| privacy | Tor (Tor Browser, per-app, system-wide — off until you turn it on), Proton VPN, I2P, Bitwarden, nheko |
| virt | QEMU/KVM + virt-manager |
| backoffice | the parts-inventory web app, synced between machines |
| intraweb | your own local-first neighborhood web on the LAN (no server, no internet) |
| platform | Docker, Flatpak/Flathub, AppImage, Distrobox, and apps built from any git repo (`gitApps`) |
| backups | daily restic snapshots of home + config to an external drive |
| power | laptop battery/thermal tuning (TLP); near no-op on the desktop |
| secrets | keep passwords/keys out of git with sops-nix — **off by default** |
| osint | security / OSINT toolkit — **off by default** |

```sh
mod list            # what's on / off
mod on osint        # enable + rebuild
mod off gaming      # disable + rebuild (the module stays written, just unbuilt)
```

## Commands

| command | what |
|---|---|
| `modtui` | TUI: onboarding, modules, settings, AI model (with download bar), update |
| `rebuild` (`nrs`) | update the channel + your own packages, then `nixos-rebuild switch` with a live progress bar (`--no-update` to skip updating) |
| `update-mine` | move your git-built apps (neb, backoffice, intraweb + `gitApps`) to their latest commit, only if it builds; runs daily too. `--status` to just look |
| `debloat` | what's using space, and clean it; `debloat remove <app>` drops an app from every module, or uninstalls a Flatpak by id (`org.gimp.GIMP`) and trims runtimes nothing else uses |
| `nixup` | `git pull` /etc/nixos + rebuild (`autoUpdate = true` does it weekly) |
| `nixmenu` | this system's actions by category — **Super+Alt+Space**. Add/hide/reorder in `settings.nix` → `menu`, or `~/.config/nixmenu/menu` (no rebuild) |
| `mykeys` | your keybind cheat sheet — **Super+Alt+F1** |
| `apps` | every app, by category — **Super+Alt+a** |
| `audio` | pick output/mic device (speakers, headset, Bluetooth, HDMI), volume, mute — **Super+Alt+v** |
| `drives` | mount / unlock / unmount drives, never automatic — **Super+Alt+m** |
| `tidy-downloads` | sort ~/Downloads into folders, catch duplicates (`--undo`) |
| `lock` | lock screen — **Super+Alt+l** (also on suspend / 10 idle min) |
| `snow on\|off` | the live falling snow |
| `thunar` | GUI file manager — **Super+Alt+e** (`lf` is still Super+r) |
| `dash` | the menu's Self-hosted section (your web apps + running Docker containers) — **Super+Alt+d** |
| `neb-voice` | talk to Neb, answer in a corner notification — **Super+Alt+n** |
| `neb-space` | Neb's workspace (tag 9) + his terminal — **Super+Alt+Shift+n** |
| `devlink …` | `pin` to pair, `send`, `tabs` (your browser tabs → the other machine), `screen` / `view` |
| `backoffice-sync` | inventory hand-off between machines (`--status`) |
| `browser-sync` | export bookmarks to ~/Sync + merge the other machine's back (runs at login too) |
| `browser-sync passwords` | push each browser's own password export into Bitwarden |
| `torrun <app>` / `tormode on\|off\|status` | one app / everything through Tor (`status` proves it via check.torproject.org) |
| `protonvpn-app` / `protonvpn` | Proton VPN (app / CLI) |
| `backoffice` | parts-inventory web app on :8080 |
| `intraweb` | neighborhood web on the LAN; dashboard on :8420 (runs at login) |
| `backup` | restic snapshot to the external drive; `backup now`, `backup snapshots`, `backup restore …` |

## Notes

- **Speed & space**: zen kernel (`settings.kernel`), compressed RAM swap, and
  automatic de-prioritising of background work keep it snappy; no HTML docs
  are built, the journal is capped, old generations go after 14 days. Every
  module installs through one list, so `removePackages = [ "discord" ];` (or
  `debloat remove discord`) drops an app everywhere.
- **Your apps from git**: add `name = { repo = "owner/repo"; type = "rust"; };`
  (or `url = "https://…"` for any git server) under `gitApps` in `settings.nix`.
  Types: rust, go, node, python, make, script, docker. `update-mine` keeps them
  on their newest commit and only switches to one that builds. The same works
  to point neb/backoffice/intraweb at a fork. Forking this whole config? Clone
  your fork to /etc/nixos and `nixup` pulls from it.
- **Tor**: `tormode on` waits until Tor has connected and shows the exit IP.
  While it's on, anything that can't go through Tor — IPv6, QUIC, your LAN,
  Docker, a VPN — is refused instantly instead of leaking or hanging.
- **Proton VPN**: open it from the menu (Network & privacy) and sign in once;
  the login is kept in your keyring, which unlocks when you log in. Turn the
  VPN off before `tormode on`.

- **Keys**: Super+Enter is the terminal and Super+Space is stock again; everything
  of yours is under Super+Alt (`mykeys` lists it).
- **Neb**: on the desktop his brain is Ollama on the GPU via Vulkan (ROCm doesn't
  support the 6750 XT and silently fell back to the CPU). Default model
  `qwen3.5:9b` with thinking off; `modtui` → AI model to pick another. He can act
  on the desktop through `desk`; typing, keys and closing windows ask first.
- **Passwords/bookmarks**: Bitwarden is pre-installed in Firefox and Chromium —
  sign in once per browser; it's the password vault and syncs itself. Bookmarks
  move with `browser-sync`: no live sync service, it just exports them to an
  HTML file in `~/Sync` (Syncthing carries it over) and merges the other
  machine's file back, at login and whenever you run it. To pull in your
  browser-saved passwords, export them from each browser's own Passwords screen
  and run `browser-sync passwords` — it imports the CSV into Bitwarden and
  shreds it. It never touches a browser's encrypted password store itself, and
  no password ever lands in the Sync folder.
- **Neighborhood (intraweb)**: joins the LAN's neighborhood web at login — a
  dashboard on `:8420`, with pages, files, signed mail and channels, no server
  and no internet. Your identity is a key in `~/.intraweb`; copy that folder to
  stay yourself on another machine. nixmenu → **Neighborhood** opens it. To host
  a hub (claims `intranet.local`), run `sudo intraweb up --hub` by hand.
- **Backups**: the `backups` module takes daily restic snapshots of `~` and
  `/etc/nixos` to the drive at `backupRepo` (settings). Set it up once — plug in
  the drive, put a passphrase in `~/.config/restic/password` (or use the
  `secrets` module), run `backup now`. It skips quietly with a reminder when the
  drive isn't plugged in, so the daily timer never nags with failures. **Keep a
  copy of the passphrase** — without it the backup can't be restored.
- **Secrets**: off by default. `mod on secrets` sets up sops-nix so passwords
  and keys live encrypted in `secrets/` (safe to commit) and decrypt to
  `/run/secrets/*` with a machine-local age key that never enters git. See
  `secrets/README.md`.
- **Power (laptop)**: the `power` module runs TLP — powersave governor on
  battery, performance on AC, USB autosuspend. On the desktop it does almost
  nothing. `powertop` is there for a look at what's drawing power.
- **3D printers**: list your printers' Moonraker URLs in `settings.printers` and
  you get a desktop notification when a print finishes or fails.
- **Drives**: nothing mounts by itself. `drives`, or click the drive in Thunar's
  sidebar — both use udisks2 as you (no sudo), mount under
  `/run/media/samadams/<label>`, and handle LUKS. Phones show up in Thunar.
- **Top bar**: clock + net/volume/battery — `pkgs/default.nix` → `larbs-dwmblocks`.
- **Terminal transparency**: `termOpacity` in settings; fullscreen is always opaque.
- **Minecraft**: Prism Launcher; Feather/Fabric install into it from Modrinth.
- **Wallpaper**: a snowy night with live snow by default; `setbg /path/to/image.png`
  to change it, `snow off` (or `liveSnow = false`) to stop the snow.
