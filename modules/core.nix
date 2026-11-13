# Always on: nix, boot, network, user, audio, fonts, shell, hardening, `mod`.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  removed = s.removePackages or [ ];
  share = { serve = false; from = ""; key = ""; } // (s.shareBuilds or { });
  picked = import ../picker.nix lib;     # same module list configuration.nix imports

  # ── Jarvis's note-to-self: regenerated from the live config every rebuild ──
  # Lands at /etc/jarvis/SYSTEM.md (and ~/SYSTEM.md). Written for an assistant
  # bot so it knows how this machine is wired without being told.
  jarvisDoc = pkgs.writeText "SYSTEM.md" ''
    # ${s.hostName} — system notes (auto-generated, do not hand-edit)

    Regenerated on every `nixos-rebuild`, so it always matches the running
    system. Source of truth is /etc/nixos (a module tree). Owner: ${s.fullName}
    (`${s.username}`), timezone ${s.timeZone}.

    ## Shape of the config
    - `/etc/nixos/configuration.nix` — picks modules: nix²'s defaults are the
      marker files in `/etc/nixos/mods/`, overridden by `modules.<name>` in
      settings.local.nix (`mod on|off` writes those).
    - `/etc/nixos/settings.nix` — every setting with its default (in git).
    - `/etc/nixos/settings.local.nix` — THIS machine's values (not in git):
      username, hostname, gpu, modules… Edit it, or `nix2-setup set KEY VALUE`.
    - `/etc/nixos/modules/<name>.nix` — one feature each. Off modules stay on
      disk, just unbuilt.
    - `/etc/nixos/pkgs/default.nix` — packages built from source (one overlay).

    ## Modules currently ON
    ${lib.concatMapStringsSep "\n" (m: "- ${m}") picked.on}

    (All modules: ${lib.concatStringsSep ", " picked.all})

    ## Commands this system adds
    - `mod list | mod on <name> | mod off <name>` — toggle a module + rebuild.
    - `backoffice` — opens the parts-inventory app (http://127.0.0.1:8080; it
      runs as a user service, data in ~/.local/share/backoffice). With the
      `sync` module its inventory hands off between the two machines as
      consistent snapshots (`backoffice-sync --status`); photos sync live.
    - `claude-code` — Claude Code.
    - `intraweb` (its own module) — a local-first neighborhood web on the LAN:
      it runs `intraweb up` as a user service at login, giving a dashboard on
      http://localhost:8420 where neighbors on the same Wi-Fi share pages,
      files, signed mail and channels — no server, no internet. Identity is an
      Ed25519 key in ~/.intraweb. `intraweb surf|ls|get|mail|say|doctor|id`;
      running a hub (`intranet.local`) is a manual `sudo intraweb up --hub`.
    - `backup` (its own module) — restic snapshots of ~ and /etc/nixos to the
      external drive in settings.backupRepo, on a daily timer that skips quietly
      when the drive is unplugged. `backup now`, `backup snapshots`, `backup
      restore latest --target DIR`. Password in ~/.config/restic/password or
      /run/secrets/restic-password; without it a restore is impossible.
    - The `power` module tunes the laptop's battery (TLP). The `secrets` module
      (off by default) keeps passwords/keys encrypted in secrets/ via sops-nix.
      3D-print done/failed notifications come from settings.printers.
    - `torrun <app>` — run one app through Tor (leak-proof). `tormode on|off|status`
      — route everything through Tor (privacy module). `tormode on` waits for
      Tor to connect and proves it via check.torproject.org; anything that
      can't go through Tor (IPv6, QUIC/UDP, LAN, Docker/VMs, a VPN) is refused,
      not leaked. The Tor daemon is OFF until then; Tor Browser and torrun
      bring their own. Proton VPN: `protonvpn-app` (GUI) / `protonvpn` (CLI);
      its login lives in gnome-keyring (unlocked at the ly login). Don't run
      tormode and the VPN at the same time.
    - **Neb** is the assistant (the `assistant` module). `neb` server runs on
      http://127.0.0.1:7000 (dashboard: switch brain, set API keys, allowlist).
      **Super+Alt+n** = `neb-voice`: listen → answer, shown only as a small
      corner notification (and spoken). **Super+Alt+Shift+n** = Neb's own
      workspace, tag 9, where his terminal lives; Enter on an empty line there
      talks out loud. Also `neb ask "..."`, `neb chat`, `neb tools`. On the
      desktop his brain is local Ollama (Vulkan GPU backend; default model
      qwen3.5:9b, thinking off for speed); on the laptop it's an API key. He can
      act on the desktop through `desk` (open apps/sites, list/focus/close
      windows, type, keys, volume, media, screenshots, lock); typing, key
      presses and closing windows ask for a yes first, and what he opens goes on
      his workspace. This file is Neb's machine context — he reads it via his
      read_system_notes tool.
    - `modtui` — a TUI for first-run onboarding, toggling modules, editing
      settings.nix, installing/choosing an AI model, and rebuilding.
    - **DeviceLink** (`sync` module) links this machine to the other over
      Syncthing. Easiest: `devlink pin <code>` with the same code on both. Or
      `devlink link <id>` here and `devlink accept` there — link requests are
      never accepted automatically. Send files/text
      between them from the window (`devlink-window`, port 7010) or by dropping
      into ~/DeviceLink. `devlink send FILE|-t TEXT|-c` from the shell.
      `devlink screen` shares this whole screen over VNC (peer-restricted,
      per-session password); the other machine runs `devlink view`.
      `devlink tabs` sends the open Firefox window's tabs; they reopen on the
      other machine by themselves. The window previews and opens tray files.
      Linking also shares ~/Sync (which carries the bookmark exports), Neb's
      shared notes and backoffice.
    - `setbg <image>` — set the wallpaper.
    - `rebuild` (alias `nrs`) — `nixos-rebuild switch` with a live progress display.
    - `nixup` — pull the config repo at /etc/nixos and rebuild (no re-cloning).
      Edits made in /etc/nixos are committed locally first ("My changes on
      <host>") by `nix2-pull` and rebased on top of the update; on a conflict
      it aborts and restores everything. `nix2-pull --mine` lists them.
    - `rebuild` applies the config and updates the user's own git apps
      (`update-mine`); it stays on the current NixOS package set so it's quick.
      `rebuild --upgrade` moves to the newest NixOS packages; a weekly
      idle-priority job (nixos-prebuild, settings.channelUpdates) fetches and
      pre-builds them so the next rebuild switches in seconds, and rolls the
      channel back if they don't build. `rebuild --no-update` only applies
      config (mod on/off use it). Git-built apps — the built-ins neb, backoffice,
      intraweb (pkgs/pins.json) plus anything in settings.gitApps (any repo,
      any git server; types rust/go/node/python/make/script/docker) — also
      update daily by themselves (settings.autoUpdateMine). `update-mine
      --status` shows what's pinned vs. upstream. A new commit that doesn't
      build is held back and the old version stays. pkgs/tracked.nix is the
      single source of truth for which commit each one builds.
    - `nixmenu` is data-driven: modules add entries via `my.menu`, web apps via
      `my.selfhosted`; settings.menu (order/hide/extra) and
      ~/.config/nixmenu/menu (no rebuild) customise it. Running Docker
      containers with a published port appear under Self-hosted.
    - Space: settings.removePackages drops an app from every module (all
      modules install through `my.packages`). `debloat` reports what's big
      and cleans (old generations, caches, logs, unused Docker images);
      `debloat remove|keep <name>` edits that list. Kernel is zen by default
      (settings.kernel); zram, earlyoom (never kills Steam/games) and ananicy keep
      it responsive.
    - `wallpapers` (Super+Alt+w): built-in wallpapers (pkgs.nix2-wallpapers,
      drawn at build time by pkgs/scripts/wallpapers-gen.py), pictures from
      ~/Pictures/wallpapers (setbg; fit in ~/.config/wallpapers/fit), or live
      Wallpaper Engine wallpapers from the Steam Workshop, played by the
      wallpaper-live user service (linux-wallpaperengine; choice saved in
      ~/.config/wallpapers/live). It runs one window per monitor (class
      linux-wallpaperengine, kept at the bottom by dwm) because picom hides
      anything drawn on the X root window, and sets XDG_SESSION_TYPE=x11,
      which linux-wallpaperengine needs and user services don't get.
    - `neofetch` = fastfetch with pkgs/fastfetch/config.jsonc (unless
      ~/.config/fastfetch/config.jsonc exists); /etc/nix2/modules lists the
      modules that are on. `lock` is xsecurelock: username + password.
      Steam is native; `steam-setup` (runs at login) turns on Steam Play for
      all titles so Windows games and Wallpaper Engine install.
    - `site-push [folder]` publishes a folder to Neocities: the site comes from a
      `.neocities` file at the repo root (site, dir, optional build); API keys
      live in the keyring (secret-tool, service=neocities site=NAME) and are
      verified against the site before uploading; only changed files (SHA-1)
      are sent. `site-push key SITE`, `site-push sites`, `--dry-run`, `--prune`.
    - The `platform` module: Docker (socket-activated, weekly prune), Flatpak +
      Flathub, AppImage, Distrobox, and the gitApps builds/services.
    - This machine's own functions live under **Super+Alt** (a namespace LARBS
      leaves alone): **Super+Alt+Space** opens `nixmenu` (every function here),
      **Super+Alt+F1** shows `mykeys` (the custom-keybind cheat sheet). Stock
      LARBS keys stay on Super+F1's manual; Super+Enter is the terminal.
    - `apps` (Super+Alt+a) — every installed app, by category.
    - `tidy` — cleans up: loose files at the top of ~ go to ~/Pictures
      (screenshots → Pictures/screenshots), ~/Videos (recordings →
      Videos/recordings), ~/Music, ~/Documents, everything else to Downloads;
      then Downloads is sorted into type folders. Content duplicates go to
      Downloads/Duplicates (never deleted); folders, dotfiles and SYSTEM.md are
      never touched. `--home`, `--downloads`, `--dry-run`, `--undo`.
    - Screenshots: Print (and settings.screenshotKey, for laptops whose key
      sends e.g. F10) = full screen, with Shift or Super+Alt+s = menu (area, window,
      clipboard-only, OCR text). `screenshot` saves to ~/Pictures/screenshots
      and copies to the clipboard; failures show a notification.
    - `lock` (Super+Alt+l) — lock screen; also on suspend and after 10 idle min.
    - `snow on|off|toggle` — the live falling snow over the snowy wallpaper.
    - `nix2` (pkgs/nix2, one Rust binary) holds this system's own tools:
      the menu (`nixmenu` is a link to it), `nix2 doctor` (system check with
      a fix for every problem; a weekly user timer runs `--notify`, which
      only speaks up when something's wrong), `nix2 rollback` (switch to an
      earlier system generation), `nix2 game start|end` (gamemode hooks:
      pause dunst, SIGSTOP the live wallpaper, stop snow — all restored on
      exit; state in $XDG_RUNTIME_DIR/nix2-game), `nix2 new` (project
      starter: shell.nix + .envrc + git in ~/projects) and `printer-notify`.
      `backup` writes ~/.local/state/backup/last-success for the doctor.
    - `nix2 serial` (pick a USB board by name → tio) and `nix2 new board|
      micropython` (PlatformIO / MicroPython projects with `just flash`). The
      `ee` module grants device access (udev: picotool, probe-rs, ST-Link,
      OpenOCD, sigrok, QMK, Vial/hidraw for the seat user, RTL-SDR, Flipper).
    - Python: python3/pip are pkgs.python-pip — `pip install x` outside a
      venv installs into ~/.local (no --user or --break-system-packages
      needed; ~/.local/bin is on PATH), and LD_LIBRARY_PATH gives wheels
      libstdc++/zlib/libGL/glib/X11. pipx and uv are in; nix-ld has the same
      libraries for downloaded binaries. venvs behave normally.
    - Builds (`devtools`): RUSTC_WRAPPER=sccache, CMake → ccache, Rust links
      with mold (env vars, so Nix's own builds are unaffected); zsh notifies
      when a command ran ≥30 s; `debloat junk` lists stale build folders.
    - Shared builds: settings.shareBuilds.serve runs harmonia (:5000, key in
      /var/lib/nix2/cache-key); other machines set shareBuilds.from + key
      (`nix2-setup share` prints them) and substitute from it first.
    - Clipboard history: clipmenud + `clipmenu` (Super+Alt+c). Night light:
      gammastep via services.redshift, location from settings.location;
      `nightlight` toggles it for the session.
    - `devtools` module: the coding toolkit (lazygit, gh/glab/tea, delta as the
      git pager, difftastic, direnv + nix-direnv, just, hyperfine, CMake/Ninja/
      clangd/gdb/valgrind, Meld, Zeal, Qalculate, sqlitebrowser); big apps only
      with settings.devExtras. Menu: "Code & engineering".
    - Browsers: Bitwarden holds the passwords in Firefox and Chromium (sign in
      once per browser). `browser-sync` moves bookmarks between the machines
      with no live sync service: it exports them to an HTML file in ~/Sync (so
      Syncthing carries it over) and merges the other machine's file back in,
      at login and on demand. `browser-sync passwords` pushes each browser's
      own password export into Bitwarden (which is what syncs them) and shreds
      the file; it never reads a browser's encrypted password store itself.
    - Files & drives (`desktop` module): Thunar is the GUI file manager
      (Super+Alt+e); `lf` stays the terminal one. Nothing mounts on its own —
      `drives` (Super+Alt+m, or Super+F9/F10) is a dmenu menu to mount, unlock
      (LUKS) and unmount drives via udisks2, no sudo; Thunar's sidebar does the
      same on click, and shows phones (MTP/iPhone) too. Mounts land in
      /run/media/${s.username}/<label>.

    ## To change the system (do this, not `nix profile install`)
    1. Edit the relevant file under /etc/nixos (a module, or settings.local.nix).
    2. `rebuild` (= `sudo nixos-rebuild switch` with progress). Rollback: pick
       an older generation at boot, or `sudo nixos-rebuild switch --rollback`.
    - Add a package: put it in the fitting module's `my.packages` (settings.removePackages strips any of them out).
    - Add a service: a NixOS `services.*` option in the fitting module.
    - Add software built from Git: a derivation in pkgs/default.nix (copy the
      `backoffice` block — it shows the fetchFromGitHub + hash pattern).

    ## Conventions / safety for an assistant acting here
    - This is declarative: nothing is "installed" imperatively. Change files,
      rebuild. Never edit /nix/store.
    - The firewall is on; SSH is off; `sudo` needs a password. Open ports come
      only from modules: `sync` (Syncthing 22000 + 21027/udp, devlink pairing
      58846/udp, VNC 5900 — nothing listens there until `devlink screen`) and
      `printing` (mDNS 5353/udp). Don't open more without asking.
    - Desktop is dwm (suckless); the status bar clock + commands are in
      pkgs/default.nix → larbs-dwmblocks. Press Super+F1 for the keybind manual.
    - 3D printers: control over the LAN (mDNS is on, so `*.local` resolves).
      See modules/printing.nix for the self-host Klipper option.
    - Before any outward-facing or irreversible action, confirm with ${s.username}.
  '';

  # A friendly TUI: first-run onboarding, module toggles, settings editing, and
  # installing/choosing an AI model. Run: modtui
  modtui = pkgs.writeShellScriptBin "modtui" ''
    export PATH=${lib.makeBinPath (with pkgs; [ gum coreutils gnused gnugrep curl jq ])}:/run/wrappers/bin:/run/current-system/sw/bin:$PATH
    dir=/etc/nixos

    # This machine's values live in settings.local.nix (nix2-setup reads and
    # writes it; settings.nix only holds the defaults).
    getset() { nix2-setup get "$1"; }
    setset() { sudo nix2-setup set "$1" "$2"; }
    modules() { for f in "$dir"/modules/*.nix; do n=$(basename "$f" .nix); [ "$n" = core ] || echo "$n"; done; }
    neb_dash() {
      if command -v xdg-open >/dev/null 2>&1; then xdg-open http://127.0.0.1:7000 >/dev/null 2>&1 &
      else gum style "Open http://127.0.0.1:7000 in a browser."; fi
    }

    toggle_modules() {
      mapfile -t mods < <(modules)
      mapfile -t pre < <(nix2-setup modules)
      sel=$(printf '%s\n' "''${mods[@]}" | gum choose --no-limit --height 20 \
            --header "Space = toggle a module on/off, Enter = apply" \
            $(printf -- '--selected=%s ' "''${pre[@]}")) || return
      for m in "''${mods[@]}"; do
        if printf '%s\n' "$sel" | grep -qx "$m"; then sudo nix2-setup module "$m" on
        else sudo nix2-setup module "$m" off; fi
      done
      gum confirm "Rebuild now to apply?" && rebuild --no-update
    }

    edit_settings() {
      while true; do
        f=$(gum choose --header "This machine's settings — pick one to change" \
          "device: $(getset device)" "gpu: $(getset gpu)" "hostName: $(getset hostName)" \
          "termOpacity: $(getset termOpacity)" "autoUpdate: $(getset autoUpdate)" \
          "useGrub: $(getset useGrub)" "Back") || return
        case "$f" in
          device:*)      v=$(gum choose desktop laptop) && setset device "\"$v\"" ;;
          gpu:*)         v=$(gum choose amd intel nvidia none) && setset gpu "\"$v\"" ;;
          hostName:*)    v=$(gum input --value "$(getset hostName)") && [ -n "$v" ] && setset hostName "\"$v\"" ;;
          termOpacity:*) v=$(gum input --prompt "0.0–1.0 > " --value "$(getset termOpacity)") && setset termOpacity "\"$v\"" ;;
          autoUpdate:*)  v=$(gum choose true false) && setset autoUpdate "$v" ;;
          useGrub:*)     v=$(gum choose true false) && setset useGrub "$v" ;;
          Back) return ;;
        esac
      done
    }

    ai_model() {
      if ! command -v ollama >/dev/null 2>&1; then
        gum style --border normal --padding "0 1" \
          "Local models need a GPU: the 'assistant' module on a desktop (or settings localAI = true)." \
          "Without one, Neb uses an API brain — set the key in Neb's dashboard."
        gum confirm "Open Neb's dashboard now?" && neb_dash
        return
      fi
      gum style --faint "Installed models:"; ollama list 2>/dev/null || true
      m=$(printf '%s\n' \
            "qwen3.5:9b   recommended: best with Neb's tools · 6.6 GB" \
            "qwen3.5:4b   fastest replies, still good · 3.3 GB" \
            "gemma4:12b   strong all-rounder, can see images · 7.7 GB" \
            "gemma4:e4b   small, quick Gemma · 6.6 GB" \
            "other…" \
          | gum choose --header "Install / update which model? (pick one smaller than your GPU's memory)") || return
      m=''${m%% *}
      [ "$m" = "other…" ] && m=$(gum input --placeholder "model[:tag], e.g. llama3.2")
      [ -n "$m" ] || return
      echo
      ollama pull "$m" || { gum style --foreground 1 "pull failed"; return; }   # ollama draws its own progress bar
      gum spin --title "warming $m up…" -- ollama run "$m" "Reply with one word: ready" || true
      ollama ps
      gum style --faint "PROCESSOR should say 100% GPU. If it says CPU, the GPU isn't being used — that's what makes replies slow."
      if gum confirm "Make Neb use $m as its brain?"; then
        curl -fsS -X POST http://127.0.0.1:7000/api/settings -H 'Content-Type: application/json' \
          -d "{\"provider\":\"ollama\",\"providers\":{\"ollama\":{\"model\":\"$m\",\"think\":false}}}" >/dev/null 2>&1 \
          && gum style --foreground 2 "Neb now uses $m." \
          || gum style --faint "Pulled. Set it as Neb's model in the dashboard if it didn't stick."
      fi
    }

    onboard() {
      gum style --border double --padding "1 2" --margin "1 0" \
        "Welcome. A few questions to set this machine up."
      sudo nix2-setup             # you, hostname, timezone, laptop/desktop, graphics
      gum confirm "Choose which modules are on?" && toggle_modules
      gum confirm "Set up an AI model / brain now?" && ai_model
      if command -v devlink >/dev/null 2>&1 && gum confirm "Link this machine to your other one now?"; then
        c=$(gum input --header "Make up a code; type the SAME one on the other machine" --placeholder "e.g. 4921")
        [ -n "$c" ] && devlink pin "$c"
      fi
      gum confirm "Rebuild now to apply everything?" && rebuild
      gum style --foreground 2 "Done. Super+Alt+Space = your menu · Super+Alt+F1 = your keys."
    }

    while true; do
      a=$(gum choose --header "nix control — $(getset hostName) [$(getset device)]" \
        "Onboarding (guided setup)" "Modules on/off" "Edit settings" "AI model" \
        "Update system (pull + rebuild)" "Rebuild now" "Open Neb dashboard" "Quit") || exit 0
      case "$a" in
        "Onboarding"*)        onboard ;;
        "Modules on/off")     toggle_modules ;;
        "Edit settings")      edit_settings ;;
        "AI model")           ai_model ;;
        "Update system"*)     nixup ;;
        "Rebuild now")        rebuild ;;
        "Open Neb dashboard") neb_dash ;;
        "Quit")               exit 0 ;;
      esac
    done
  '';

  # `mod` — modules on/off. Your choice goes in settings.local.nix
  # (modules.<name>), so updates never undo it; mods/ holds nix²'s defaults.
  mod = pkgs.writeShellScriptBin "mod" ''
    dir=/etc/nixos
    all() { for f in "$dir"/modules/*.nix; do n=$(basename "$f" .nix); [ "$n" = core ] || echo "$n"; done; }
    case "''${1:-list}" in
      list) on=$(nix2-setup modules)
            for n in $(all); do printf '%s\n' "$on" | grep -qx "$n" && echo "  on   $n" || echo "  off  $n"; done ;;
      on|off|default)
            [ -n "''${2:-}" ] || { echo "usage: mod $1 <name>"; exit 2; }
            sudo nix2-setup module "$2" "$1" && rebuild --no-update ;;
      *)    echo "usage: mod list | mod on <name> | mod off <name> | mod default <name>" ;;
    esac
  '';

  # `nixup` — pull the config repo at /etc/nixos and rebuild. No re-cloning:
  # your machine-local hardware-configuration.nix (untracked) is left alone.
  nixup = pkgs.writeShellScriptBin "nixup" ''
    # Tools the freshly pulled rebuild/update-mine scripts need (they're run
    # straight from the repo, see below).
    export PATH=${lib.makeBinPath (with pkgs; [ nix-output-monitor git jq util-linux gawk gnugrep gnused coreutils ])}:/run/wrappers/bin:/run/current-system/sw/bin:$PATH
    dir=/etc/nixos
    if [ ! -d "$dir/.git" ]; then
      echo "nixup: $dir isn't a git clone. Clone your config there once:"
      echo "  sudo git clone <your-repo-url> $dir   # keep hardware-configuration.nix"
      exit 1
    fi
    # Your own edits in $dir are committed locally first and kept on top of
    # the update; if they clash with it, nothing changes (see pull.sh).
    ${pkgs.nix2-pull}/bin/nix2-pull || exit 1
    echo ":: rebuilding …"
    # Run the rebuild script from the repo we just pulled, not the installed
    # one: the installed copy is from the PREVIOUS config, so a pull that
    # changes how updating works (like adding update-mine) would otherwise
    # only take effect one update later.
    bash "$dir/pkgs/scripts/rebuild.sh" "$@"
    echo ":: done — now on generation $(readlink /run/current-system | sed 's|.*-||')"
  '';
in
{
  imports = [ ../options.nix ];
  nixpkgs.overlays = [ (import ../pkgs) ];
  nixpkgs.config.allowUnfree = true;
  # Allow-list only; harmless when the package isn't installed. Kept here in one
  # place because nixpkgs.config doesn't reliably union this list across modules.
  #   pypdf2 → SpiderFoot (osint)   electron/olm → Bitwarden & nheko (privacy)
  nixpkgs.config.permittedInsecurePackages = [
    "python3.13-pypdf2-3.0.1" "electron-39.8.10" "olm-3.2.16"
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Dedupe the store on a weekly timer (nix.optimise below) instead of while
    # downloading — hashing every file mid-update made updates crawl.
    auto-optimise-store = false;
    # Faster downloads: more parallel fetches and a bigger buffer, so a
    # quick connection isn't throttled by "download buffer is full".
    max-substitution-jobs = 32;
    http-connections = 64;
    download-buffer-size = 268435456;
    trusted-users = [ "root" s.username ];
  };

  # ── Shared builds (settings.shareBuilds) ───────────────────────────────────
  # One machine (serve = true) offers everything it has built to your home
  # network; the others (from + key) download from it before the internet, so
  # your own apps and anything else it already built never compile twice.
  # Signed with this machine's own key, so the others accept only its builds.
  # (It shares /nix/store: software only — nix² keeps no secrets there.)
  services.harmonia.cache = lib.mkIf share.serve {
    enable = true;
    signKeyPaths = [ "/var/lib/nix2/cache-key" ];
  };
  systemd.services.nix2-cache-key = lib.mkIf share.serve {
    description = "Make the signing key for shared builds";
    wantedBy = [ "harmonia.service" ];
    before = [ "harmonia.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; StateDirectory = "nix2"; };
    script = ''
      k=/var/lib/nix2/cache-key
      [ -s "$k" ] || ${config.nix.package}/bin/nix-store --generate-binary-cache-key \
        "${s.hostName}-nix2-1" "$k" "$k.pub"
      chmod 600 "$k"; chmod 644 "$k.pub"
    '';
  };
  networking.firewall.allowedTCPPorts = lib.mkIf share.serve [ 5000 ];
  nix.settings.extra-substituters = lib.mkIf (share.from != "") [ share.from ];
  nix.settings.extra-trusted-public-keys = lib.mkIf (share.key != "") [ share.key ];
  # Off your home network the other machine isn't there: give up on it fast.
  nix.settings.connect-timeout = 5;
  nix.settings.fallback = true;
  # Machines find each other by name (<hostname>.local).
  services.avahi = lib.mkIf (share.serve || share.from != "") {
    enable = true; nssmdns4 = true;
    publish = { enable = true; addresses = true; };
  };
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 14d"; };
  nix.optimise = { automatic = true; dates = [ "weekly" ]; };
  # Store maintenance and the weekly pre-build never compete with you.
  systemd.services.nix-gc.serviceConfig = { Nice = 19; IOSchedulingClass = "idle"; CPUSchedulingPolicy = "idle"; };
  systemd.services.nix-optimise.serviceConfig = { Nice = 19; IOSchedulingClass = "idle"; CPUSchedulingPolicy = "idle"; };

  # Weekly, in the background: fetch the newest NixOS packages and pre-build
  # this whole system with them (idle priority — you won't notice it). Nothing
  # switches; the next `rebuild`/`nixup` just finds it all ready and takes
  # seconds. If the new set doesn't build, the channel is rolled back so your
  # next rebuild can't break. settings.channelUpdates = "never" turns it off.
  systemd.services.nixos-prebuild = lib.mkIf ((s.channelUpdates or "weekly") != "never") {
    description = "Pre-build the system on the newest NixOS packages";
    wants = [ "network-online.target" ]; after = [ "network-online.target" ];
    path = [ config.nix.package config.system.build.nixos-rebuild pkgs.git pkgs.coreutils ];
    environment.HOME = "/root";
    serviceConfig = {
      Type = "oneshot";
      Nice = 19; IOSchedulingClass = "idle"; CPUSchedulingPolicy = "idle";
      StateDirectory = "nixos-prebuild";
      WorkingDirectory = "/var/lib/nixos-prebuild";     # its `result` link keeps the pre-build from being GC'd
    };
    script = ''
      nix-channel --update
      if nixos-rebuild build; then
        echo "nixos-prebuild: ready — the next rebuild switches to it in seconds."
      else
        echo "nixos-prebuild: the new packages don't build with this config; rolled the channel back."
        nix-channel --rollback
        exit 1
      fi
    '';
  };
  systemd.timers.nixos-prebuild = lib.mkIf ((s.channelUpdates or "weekly") != "never") {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = s.channelUpdates or "weekly"; Persistent = true; RandomizedDelaySec = "2h"; };
  };

  # ── lean + responsive (settings: kernel, removePackages) ─────────────────
  # zen kernel: tuned for desktop latency (input, audio, frame pacing).
  boot.kernelPackages = {
    zen = pkgs.linuxPackages_zen;
    latest = pkgs.linuxPackages_latest;
    lts = pkgs.linuxPackages;
  }.${s.kernel or "zen"} or (throw "settings.kernel should be \"zen\", \"latest\" or \"lts\"");
  zramSwap.enable = true;                         # compressed RAM swap: no stalls under memory pressure
  # Out of memory: earlyoom only steps in when RAM *and* swap are almost gone
  # (systemd-oomd used to act on memory *pressure*, which games hit every time
  # they load or compile shaders — it could kill a game or Steam mid-load). It
  # never picks Steam, gamescope or the desktop, and prefers a browser tab.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 4;
    freeSwapThreshold = 5;
    enableNotifications = true;
    extraArgs = [
      "--avoid" "^(steam|steamwebhelper|gamescope|gamescope-wl|Xorg|dwm|pipewire|wireplumber)$"
      "--prefer" "^(chromium|Web Content|electron)$"
    ];
  };
  services.ananicy = {                            # keeps foreground apps snappy, background stuff niced
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
  };
  boot.tmp.cleanOnBoot = true;
  services.journald.extraConfig = "SystemMaxUse=200M\nMaxRetentionSec=1month";
  # No HTML docs / info pages / NixOS manual build (man pages stay).
  documentation.doc.enable = false;
  documentation.info.enable = false;
  documentation.nixos.enable = false;
  environment.defaultPackages = [ ];              # drops the perl/rsync/strace NixOS adds by default

  # ── boot ───────────────────────────────────────────────────────────────────
  boot.loader = lib.mkMerge [
    { efi.canTouchEfiVariables = true; efi.efiSysMountPoint = s.espMountPoint; }
    (lib.mkIf s.useGrub { grub = {
      enable = true; efiSupport = true; device = "nodev"; configurationLimit = 10;
      useOSProber = true;                      # dual-boot Windows
      theme = pkgs.xp-bliss-grub-theme; gfxmodeEfi = "auto";
    }; })
    (lib.mkIf (!s.useGrub) { systemd-boot = { enable = true; configurationLimit = 10; }; })
  ];
  boot.kernelParams = [ "quiet" "udev.log_level=3" ];
  assertions = [{
    assertion = s.hasLocal;
    message = ''
      This machine has no settings.local.nix yet (your username, hostname,
      graphics…). Make it with:  sudo nix2-setup
      (or: sudo bash /etc/nixos/pkgs/scripts/setup.sh), then rebuild.'';
  } {
    assertion = builtins.hasAttr s.espMountPoint config.fileSystems;
    message = ''
      Your settings say the EFI partition is at ${s.espMountPoint}, but
      hardware-configuration.nix mounts nothing there. Set espMountPoint in
      settings.local.nix to where it's mounted (`findmnt -t vfat` shows it),
      then rebuild.'';
  }];

  # ── network / bluetooth / locale ───────────────────────────────────────────
  networking.hostName = s.hostName;
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  hardware.enableRedistributableFirmware = true;          # laptop wifi blobs
  systemd.services.NetworkManager-wait-online.enable = false;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true;   # battery % for mice/keyboards/headsets
  };                                        # (the blueman GUI lives in desktop.nix)
  time.timeZone = s.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";

  # ── user ───────────────────────────────────────────────────────────────────
  users.users.${s.username} = {
    isNormalUser = true; uid = 1000; description = s.fullName; shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" "dialout" "plugdev" ];
  };

  # ── audio / fonts ──────────────────────────────────────────────────────────
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = { enable = true; alsa.enable = true; alsa.support32Bit = true;
                        pulse.enable = true; wireplumber.enable = true; };
  fonts.packages = with pkgs; [ nerd-fonts.jetbrains-mono noto-fonts noto-fonts-color-emoji ];
  fonts.fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font Mono" ];

  # ── shell / editor ─────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true; autosuggestions.enable = true; syntaxHighlighting.enable = true;
    shellAliases = { v = "nvim"; nrs = "rebuild"; ll = "ls -lah --color=auto"; };
    interactiveShellInit = ''
      bindkey -v; export KEYTIMEOUT=1
      setopt interactivecomments   # `cmd  # note` works when pasted, like in bash
      eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
      eval "$(${pkgs.starship}/bin/starship init zsh)"
    '';
  };
  programs.neovim = {
    enable = true; defaultEditor = true; viAlias = true; vimAlias = true;
    configure.customRC = ''
      set clipboard+=unnamedplus number relativenumber mouse=a undofile
      set expandtab shiftwidth=2 tabstop=2
      colorscheme habamax
    '';
  };
  programs.tmux = { enable = true; shortcut = "a"; keyMode = "vi"; baseIndex = 1;
                    escapeTime = 0; extraConfig = "set -g mouse on"; };

  # Packages. The core tools below always stay. Everything the modules add
  # (my.packages) goes through settings.removePackages first, so one list
  # there strips an app out of every module — `debloat` shows what's big and
  # `debloat remove <name>` adds to that list.
  environment.systemPackages = with pkgs; [
    mod modtui nixup nix2-pull rebuild update-mine debloat nix2 nix2-setup git curl wget htop jq zoxide starship
  ] ++ lib.filter (p: !(lib.elem (lib.getName p) removed)) config.my.packages;
  my.packages = with pkgs; [
    fastfetch-id neofetch fzf ripgrep fd bat eza tree unzip zip psmisc usbutils pciutils
    gcc gnumake                  # build tools — `debloat remove gcc-wrapper gnumake` if you never compile
    python-pip pipx uv           # Python: `pip install x` just works (see python-pip in pkgs/default.nix)
  ];
  # pip/pipx put commands in ~/.local/bin; prebuilt programs (and Pythons uv
  # downloads) find the usual Linux libraries through nix-ld.
  environment.localBinInPath = true;
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = pkgs.python-pip.wheelLibs;
  warnings = map (n: "settings.removePackages: \"${n}\" isn't installed by any module — `debloat list` shows the names")
    (lib.filter (n: !(lib.elem n (map lib.getName config.my.packages))) removed);
  environment.etc."debloat/packages".text =
    lib.concatMapStrings (p: lib.getName p + "\n") (lib.unique config.my.packages);

  # Which modules are on, for fastfetch's "modules" line.
  environment.etc."nix2/modules".text = lib.concatStringsSep "\n" picked.on + "\n";

  my.menu."System" = lib.mkBefore [
    { label = "Setup / modules (TUI)"; run = "modtui"; mode = "term"; }
    { label = "Update system (pull + rebuild)"; run = "nixup"; mode = "term"; }
    { label = "Full upgrade (newest NixOS packages)"; run = "rebuild --upgrade"; mode = "term"; }
    { label = "Update my git apps"; run = "update-mine --switch"; mode = "term"; }
    { label = "Free up space (debloat)"; run = "debloat"; mode = "term"; }
    { label = "System check (what's broken + how to fix it)"; run = "nix2 doctor"; mode = "term"; }
    { label = "Roll back to an earlier version"; run = "nix2 rollback"; mode = "term"; }
  ];

  # Weekly system check: a notification only if something needs a look
  # (failed services, a nearly full disk, no recent backup, missing Steam
  # graphics libraries…). Run it yourself any time: `nix2 doctor`.
  systemd.user.services.nix2-doctor = {
    description = "Weekly system check";
    serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.nix2}/bin/nix2 doctor --notify"; SuccessExitStatus = [ 1 ]; };
  };
  systemd.user.timers.nix2-doctor = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "weekly"; Persistent = true; RandomizedDelaySec = "2h"; };
  };

  # Your home folders (settings.homeFolders), created on boot if missing —
  # never clobbered or removed. Nested paths work too ("projects/work").
  systemd.tmpfiles.rules = map (d: "d /home/${s.username}/${d} 0755 ${s.username} users -")
    (s.homeFolders or [ "projects" "notes" "junk" ]);

  # Optional weekly auto-update (settings.autoUpdate). Runs as root, so no sudo:
  # pulls /etc/nixos (your own edits kept, like nixup) and rebuilds. Skips
  # this run if the update clashes with your edits (the journal says which file).
  systemd.services.nix-auto-update = lib.mkIf s.autoUpdate {
    description = "Pull /etc/nixos and rebuild";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.git pkgs.nix config.system.build.nixos-rebuild ];
    script = ''
      cd /etc/nixos || exit 0
      [ -d .git ] || exit 0
      ${pkgs.nix2-pull}/bin/nix2-pull --quiet || exit 0   # keeps your edits; a clash = skip this week
      nixos-rebuild switch
    '';
  };
  systemd.timers.nix-auto-update = lib.mkIf s.autoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "weekly"; Persistent = true; RandomizedDelaySec = "1h"; };
  };

  # Your own packages (pkgs/pins.json: neb, backoffice, intraweb) follow their
  # GitHub repos. `rebuild` runs update-mine first; this daily timer runs
  # `update-mine --switch`: it pins any newer commit that builds and switches
  # only if something changed. settings.autoUpdateMine = false turns it off.
  systemd.services.update-mine = lib.mkIf (s.autoUpdateMine or true) {
    description = "Update the user's own packages to their latest commits";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.git config.nix.package config.system.build.nixos-rebuild ];
    environment.HOME = "/root";
    serviceConfig.Type = "oneshot";
    script = "${pkgs.update-mine}/bin/update-mine --switch";
  };
  systemd.timers.update-mine = lib.mkIf (s.autoUpdateMine or true) {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "1h"; };
  };

  services.fstrim.enable = true;
  services.openssh.enable = false;

  # Jarvis's note-to-self, placed system-wide and in the user's home each rebuild.
  environment.etc."jarvis/SYSTEM.md".source = jarvisDoc;
  system.activationScripts.jarvisDoc = {
    deps = [ "users" ];   # the home must exist before we write into it
    text = ''
      if [ -d /home/${s.username} ]; then
        install -Dm644 ${jarvisDoc} /home/${s.username}/SYSTEM.md
        chown ${s.username}:users /home/${s.username}/SYSTEM.md
      fi
    '';
  };

  # ── hardening (light enough that Steam/Proton/VMs still work) ──────────────
  security.sudo.execWheelOnly = true;
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.yama.ptrace_scope" = 1;
    "net.ipv4.conf.all.rp_filter" = 2;            # loose: strict breaks WireGuard VPNs (Proton)
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
  };

  system.stateVersion = "26.05";
}
