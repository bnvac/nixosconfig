# samadams — modular NixOS

A LARBS-style dwm desktop plus an electronics / 3D-printing / gaming / AI
workstation, split into toggleable modules.

## Layout

```
configuration.nix     picks which modules are on (reads ./mods)
settings.nix          the few values you'd change (user, host, ESP, theme)
modules/core.nix      always on: boot, net, user, audio, shell, hardening, `mod`
modules/*.nix         one feature each — desktop, apps, ai, ee, gaming,
                      privacy, virt, osint, backoffice
pkgs/default.nix      everything built from source (dwm/st/dmenu, backoffice,
                      Grok Bot, SpiderFoot, the GRUB theme…)
mods/<name>           an empty marker file = that module is ON
```

## Install

It's a directory now, not one file — copy the whole thing:

```sh
sudo cp -r . /etc/nixos/
sudo nixos-rebuild switch
```

(First time, make sure `/etc/nixos/hardware-configuration.nix` exists —
`sudo nixos-generate-config` — and that the ESP is mounted where
`settings.nix` says. The build stops with instructions if it isn't.)

## Turning things on and off

```sh
mod list            # what's on / off
mod on osint        # enable a module + rebuild
mod off gaming      # disable + rebuild
```

An off module stays fully written in `modules/` — it's just not built. Default
on: desktop, apps, ai, ee, gaming, privacy, virt, backoffice. Default off: osint.

## Commands the modules add

| command | from | what |
|---|---|---|
| `mod` | core | the module toggle above |
| `backoffice` | backoffice | parts-inventory web app on :8080 |
| `grok-bot` / `grok` | ai | Grok Bot desktop app / xAI CLI |
| `torrun <app>` | privacy | one app through Tor, leak-proof (oniux) |
| `tormode on\|off` | privacy | ALL traffic through Tor (breaks voice/games) |

## Notes

- **Top bar** shows the clock (`date`), plus net/volume/battery. Edit the block
  list in `pkgs/default.nix` → `larbs-dwmblocks`.
- **Minecraft**: Prism Launcher (gaming module); Feather/Fabric install into it
  from Modrinth.
- **Onshape** is a Chromium app-mode desktop shortcut (it's web-only).
- **Wallpaper**: `setbg /path/to/image.png`.
