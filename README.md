# samadams — modular NixOS

A LARBS-style dwm desktop plus an electronics / 3D-printing / gaming / AI
workstation, split into toggleable modules. One config for two machines (a
desktop with an RX 6750 XT, and a laptop) — `settings.nix` says which is which.

## Layout

```
configuration.nix     imports core + every module that's switched on
picker.nix            works out which modules exist / are on (reads ./mods)
settings.nix          the few values you'd change (user, host, device, ESP, look)
modules/core.nix      always on: boot, net, user, audio, shell, hardening,
                      mod / modtui / nixup, and the SYSTEM.md note for Neb
modules/*.nix         one feature each (table below)
pkgs/default.nix      everything built from source (dwm/st/dmenu, Neb,
                      backoffice, devlink, SpiderFoot, GRUB theme, …)
pkgs/devlink/         the DeviceLink app (stdlib-only Python)
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
| desktop | dwm/st/dmenu/dwmblocks (LARBS), picom, Thunar + drives, Bluetooth GUI |
| apps | browsers, Discord/Slack, media, Calibre, torrents + Stremio, Onshape |
| assistant | Neb (voice assistant) + local Ollama/Open-WebUI on the desktop |
| ai | Claude Code |
| sync | Syncthing between the machines + DeviceLink |
| ee | KiCad, EDA tools, OrcaSlicer, Elegoo Slicer, FreeCAD |
| printing | mDNS + printrun for Klipper printers on the LAN |
| gaming | Steam + Proton-GE, Prism Launcher |
| privacy | Tor (per-app + system-wide), I2P, Bitwarden, nheko, Proton VPN |
| virt | QEMU/KVM + virt-manager |
| backoffice | the parts-inventory web app |
| osint | security / OSINT toolkit — **off by default** |

```sh
mod list            # what's on / off
mod on osint        # enable + rebuild
mod off gaming      # disable + rebuild (the module stays written, just unbuilt)
```

## Commands

| command | what |
|---|---|
| `modtui` | TUI: onboarding, modules, settings, AI model, update |
| `nixup` | `git pull` /etc/nixos + rebuild (`autoUpdate = true` does it weekly) |
| `nixmenu` | dmenu of everything here — **Super+Alt+Space** |
| `mykeys` | your keybind cheat sheet — **Super+Alt+F1** |
| `drives` | mount / unlock / unmount drives, never automatic — **Super+Alt+m** |
| `thunar` | GUI file manager — **Super+Alt+e** (`lf` is still Super+r) |
| `dash` | open a self-hosted dashboard — **Super+Alt+d** |
| `neb …` | the assistant — **Super+Space** to talk |
| `devlink …` | `pin` to pair, `send`, `screen` / `view` to share a screen |
| `elegoo-slicer` | Elegoo Slicer (fetches its AppImage on first run) |
| `torrun <app>` / `tormode on\|off` | one app / everything through Tor |
| `backoffice` | parts-inventory web app on :8080 |

## Notes

- **Drives**: nothing mounts by itself. `drives`, or click the drive in Thunar's
  sidebar — both use udisks2 as you (no sudo), mount under
  `/run/media/samadams/<label>`, and handle LUKS. Phones show up in Thunar.
- **Top bar**: clock + net/volume/battery — `pkgs/default.nix` → `larbs-dwmblocks`.
- **Terminal transparency**: `termOpacity` in settings; fullscreen is always opaque.
- **Minecraft**: Prism Launcher; Feather/Fabric install into it from Modrinth.
- **Wallpaper**: `setbg /path/to/image.png`.
