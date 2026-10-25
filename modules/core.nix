# Always on: nix, boot, network, user, audio, fonts, shell, hardening, `mod`.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
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
    - `/etc/nixos/configuration.nix` — picks modules by reading `/etc/nixos/mods/`.
    - `/etc/nixos/settings.nix` — user/host/ESP/theme knobs.
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
    - `torrun <app>` — run one app through Tor (leak-proof). `tormode on|off` —
      route everything through Tor (only if the `privacy` module is on). The
      Tor daemon is OFF until `tormode on`; Tor Browser and torrun bring their own.
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
    - This machine's own functions live under **Super+Alt** (a namespace LARBS
      leaves alone): **Super+Alt+Space** opens `nixmenu` (every function here),
      **Super+Alt+F1** shows `mykeys` (the custom-keybind cheat sheet). Stock
      LARBS keys stay on Super+F1's manual; Super+Enter is the terminal.
    - `apps` (Super+Alt+a) — every installed app, by category.
    - `tidy-downloads` — sorts ~/Downloads into folders by type; content
      duplicates go to Downloads/Duplicates (never deleted); `--undo` reverts.
    - `lock` (Super+Alt+l) — lock screen; also on suspend and after 10 idle min.
    - `snow on|off|toggle` — the live falling snow over the snowy wallpaper.
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
    1. Edit the relevant file under /etc/nixos (a module, or settings.nix).
    2. `rebuild` (= `sudo nixos-rebuild switch` with progress). Rollback: pick
       an older generation at boot, or `sudo nixos-rebuild switch --rollback`.
    - Add a package: put it in the fitting module's `environment.systemPackages`.
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
    dir=/etc/nixos; set=$dir/settings.nix

    # read a `key = value;` out of settings.nix (quotes optional)
    getset() { sed -n "s/.*\\b$1 = \"\\?\\([^\";]*\\)\"\\?;.*/\\1/p" "$set" | head -1; }
    # replace the value up to the FIRST ; (so inline comments survive)
    setset() { sudo sed -i "s|\\($1 = \\)[^;]*;|\\1$2;|" "$set"; }
    modules() { for f in "$dir"/modules/*.nix; do n=$(basename "$f" .nix); [ "$n" = core ] || echo "$n"; done; }
    neb_dash() {
      if command -v xdg-open >/dev/null 2>&1; then xdg-open http://127.0.0.1:7000 >/dev/null 2>&1 &
      else gum style "Open http://127.0.0.1:7000 in a browser."; fi
    }

    toggle_modules() {
      mapfile -t mods < <(modules)
      pre=(); for m in "''${mods[@]}"; do [ -e "$dir/mods/$m" ] && pre+=("$m"); done
      sel=$(printf '%s\n' "''${mods[@]}" | gum choose --no-limit --height 20 \
            --header "Space = toggle a module on/off, Enter = apply" \
            $(printf -- '--selected=%s ' "''${pre[@]}")) || return
      for m in "''${mods[@]}"; do
        if printf '%s\n' "$sel" | grep -qx "$m"; then sudo mkdir -p "$dir/mods" && sudo touch "$dir/mods/$m"
        else sudo rm -f "$dir/mods/$m"; fi
      done
      gum confirm "Rebuild now to apply?" && rebuild
    }

    edit_settings() {
      while true; do
        f=$(gum choose --header "settings.nix — pick a value to change" \
          "device: $(getset device)" "hostName: $(getset hostName)" \
          "termOpacity: $(getset termOpacity)" "autoUpdate: $(getset autoUpdate)" \
          "useGrub: $(getset useGrub)" "Back") || return
        case "$f" in
          device:*)      v=$(gum choose desktop laptop) && setset device "\"$v\"" ;;
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
          "Local models run on the desktop (settings device=desktop + the 'assistant' module)." \
          "On the laptop, Neb uses an API brain — set the key in Neb's dashboard."
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
          | gum choose --header "Install / update which model? (all of these fit the 12 GB card)") || return
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
      v=$(gum choose desktop laptop --header "Which machine is this?") && setset device "\"$v\""
      h=$(gum input --header "Hostname" --value "$(getset hostName)") && [ -n "$h" ] && setset hostName "\"$h\""
      gum confirm "Choose which modules are on?" && toggle_modules
      gum confirm "Set up an AI model / brain now?" && ai_model
      if gum confirm "Link this machine to your other one now?" && command -v devlink >/dev/null 2>&1; then
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

  mod = pkgs.writeShellScriptBin "mod" ''
    dir=/etc/nixos; m="$dir/mods"
    all() { for f in "$dir"/modules/*.nix; do n=$(basename "$f" .nix); [ "$n" = core ] || echo "$n"; done; }
    case "''${1:-list}" in
      list) for n in $(all); do [ -e "$m/$n" ] && echo "  on   $n" || echo "  off  $n"; done ;;
      on|off) [ -n "''${2:-}" ] && [ -f "$dir/modules/$2.nix" ] && [ "$2" != core ] \
                || { echo "no module '$2' (try: mod list)"; exit 1; } ;;&
      on)   sudo mkdir -p "$m" && sudo touch "$m/$2" && rebuild ;;
      off)  sudo rm -f "$m/$2" && rebuild ;;
      *)    echo "usage: mod list | mod on <name> | mod off <name>" ;;
    esac
  '';

  # `nixup` — pull the config repo at /etc/nixos and rebuild. No re-cloning:
  # your machine-local hardware-configuration.nix (untracked) is left alone.
  nixup = pkgs.writeShellScriptBin "nixup" ''
    export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH
    dir=/etc/nixos
    if [ ! -d "$dir/.git" ]; then
      echo "nixup: $dir isn't a git clone. Clone your config there once:"
      echo "  sudo git clone <your-repo-url> $dir   # keep hardware-configuration.nix"
      exit 1
    fi
    echo ":: pulling $dir …"
    sudo git -C "$dir" pull --ff-only || { echo "nixup: pull failed (local changes? uncommitted edits?)"; exit 1; }
    echo ":: rebuilding …"
    rebuild
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
    auto-optimise-store = true;
    trusted-users = [ "root" s.username ];
  };
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };

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
    assertion = builtins.hasAttr s.espMountPoint config.fileSystems;
    message = ''
      settings.nix says the ESP is at ${s.espMountPoint}, but hardware-configuration.nix
      mounts nothing there. Mount the FAT32 ESP (nvme0n1p1) at ${s.espMountPoint}, then
      run `sudo nixos-generate-config` and rebuild.'';
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

  environment.systemPackages = with pkgs; [
    mod modtui nixup rebuild git curl wget htop fastfetch fzf ripgrep fd bat eza zoxide starship
    tree jq unzip zip gcc gnumake python3 psmisc usbutils pciutils
  ];

  # A few scratch directories, created on boot if missing (never clobbered).
  systemd.tmpfiles.rules = [
    "d /home/${s.username}/projects 0755 ${s.username} users -"
    "d /home/${s.username}/notes    0755 ${s.username} users -"
    "d /home/${s.username}/junk     0755 ${s.username} users -"
  ];

  # Optional weekly auto-update (settings.autoUpdate). Runs as root, so no sudo:
  # pulls /etc/nixos and rebuilds. Skips quietly if the pull can't fast-forward.
  systemd.services.nix-auto-update = lib.mkIf s.autoUpdate {
    description = "Pull /etc/nixos and rebuild";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.git pkgs.nix config.system.build.nixos-rebuild ];
    script = ''
      cd /etc/nixos || exit 0
      [ -d .git ] || exit 0
      git pull --ff-only || exit 0
      nixos-rebuild switch
    '';
  };
  systemd.timers.nix-auto-update = lib.mkIf s.autoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "weekly"; Persistent = true; RandomizedDelaySec = "1h"; };
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
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
  };

  system.stateVersion = "26.05";
}
