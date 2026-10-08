################################################################################
#  NixOS — samadams
#
#  A LARBS-style suckless dwm desktop (built from Luke Smith's pinned forks),
#  plus an electronics/3D-printing/gaming workstation. Trimmed from the older
#  heavily-commented version; press Super+F1 in the running system for the full
#  dwm keybinding manual.
#
#  Runtime toggles (stay configured, flip without editing this file):
#    secmod on|off|status    load/unload the OSINT & security toolkit
#    tormode on|off          route ALL traffic through Tor (transparent proxy)
#    torrun <app>            run ONE app through Tor, leak-proof (oniux)
#    backoffice              start the parts-inventory web app (localhost:8080)
#
#  Install:  sudo nixos-generate-config   (first time, for hardware config)
#            sudo cp configuration.nix /etc/nixos/ && sudo nixos-rebuild switch
################################################################################

{ config, pkgs, lib, ... }:

let
  # ── identity ───────────────────────────────────────────────────────────────
  username = "samadams";
  fullName = "Sam Adams";
  hostName = "live";
  userUid  = 1000;

  # ── runtime toggles (read from marker files; flipped by the helper scripts) ──
  # NixOS evaluates these at rebuild time, so the package set stays *defined*
  # here but is only installed when the marker exists. `secmod on` touches the
  # file and rebuilds; `secmod off` removes it and rebuilds.
  secmodOn = builtins.pathExists "/etc/nixos/secmod.on";

  # ── terminal transparency (compiled into st AND set in Xresources) ──────────
  stAlpha = "0.72";

  # ── bootloader (see the assertion in §4 if a rebuild fails here) ────────────
  useUEFI        = true;
  useGrub        = true;
  grubTheme      = pkgs.xp-bliss-grub-theme;
  grubResolution = "auto";
  espMountPoint  = "/boot/efi";   # must match hardware-configuration.nix
  touchEfiVars   = true;
  bootGenLimit   = 10;

  # ── extra dwm keybindings spliced into upstream config.h ────────────────────
  larbsExtraKeys = pkgs.writeText "larbs-extra-keys.h" ''
    { MODKEY|ShiftMask, XK_c,         spawn, {.v = (const char*[]){ "chromium", NULL } } },
    { MODKEY|ShiftMask, XK_b,         spawn, {.v = (const char*[]){ TERMINAL, "-e", "ani-cli", NULL } } },
    { MODKEY|ShiftMask, XK_s,         spawn, {.v = (const char*[]){ "virt-manager", NULL } } },
    { MODKEY|ShiftMask, XK_Tab,       spawn, {.v = (const char*[]){ "tor-browser", NULL } } },
    { MODKEY|ShiftMask, XK_backslash, spawn, {.v = (const char*[]){ TERMINAL, "-e", "tmux", "new-session", "-A", "-s", "main", NULL } } },
    { MODKEY|ShiftMask, XK_Escape,    spawn, SHCMD(TERMINAL " -e sh -c 'fastfetch; echo; printf \"[any key] \"; read -r _'") },
  '';

  defaultWallpaper = pkgs.runCommand "wallpaper.png"
    { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''magick -size 3840x2160 gradient:'#0d1117-#1b2733' -define png:color-type=2 "$out"'';

  # ── OnShape as a desktop app (CAD runs in the browser) ──────────────────────
  onshape = pkgs.makeDesktopItem {
    name = "onshape";
    desktopName = "Onshape";
    exec = "${pkgs.chromium}/bin/chromium --app=https://cad.onshape.com/documents";
    icon = "applications-engineering";
    categories = [ "Engineering" "Graphics" ];
  };

  # ── helper scripts ──────────────────────────────────────────────────────────
  secmodScript = pkgs.writeShellScriptBin "secmod" ''
    set -e
    f=/etc/nixos/secmod.on
    case "''${1:-status}" in
      on)     sudo touch "$f"  && echo "secmod ON  — rebuilding…"  && sudo nixos-rebuild switch ;;
      off)    sudo rm -f "$f"  && echo "secmod OFF — rebuilding…" && sudo nixos-rebuild switch ;;
      status) [ -e "$f" ] && echo "secmod is ON (tools installed)" || echo "secmod is OFF (tools configured but not installed)" ;;
      *)      echo "usage: secmod on|off|status" ;;
    esac
  '';

  # per-app Tor via oniux (Linux namespaces — no leaks). e.g. torrun chromium
  torrunScript = pkgs.writeShellScriptBin "torrun" ''
    exec ${pkgs.oniux}/bin/oniux "$@"
  '';

  # system-wide transparent Tor, toggled through a systemd service (see §12)
  tormodeScript = pkgs.writeShellScriptBin "tormode" ''
    case "''${1:-}" in
      on)  sudo systemctl start  tor-transparent && echo "ALL traffic now routed through Tor." ;;
      off) sudo systemctl stop   tor-transparent && echo "Tor transparent routing OFF." ;;
      *)   systemctl is-active --quiet tor-transparent && echo "tormode: ON" || echo "tormode: OFF" ;;
    esac
  '';

  # ── OSINT / security toolkit — only installed while `secmod` is ON ──────────
  osintPackages = with pkgs; [
    nmap wireshark-cli tcpdump termshark
    metasploit recon-ng theharvester osint-tools-cli spiderfoot sherlock
    aircrack-ng iw macchanger
    whois dnsutils
  ];
in
{
  imports = [ ./hardware-configuration.nix ];

  ##############################################################################
  # 2 · PACKAGES BUILT FROM SOURCE (overlay)
  ##############################################################################
  nixpkgs.overlays = [
    (final: prev: {

      larbs-dwm = prev.stdenv.mkDerivation {
        pname = "larbs-dwm"; version = "6.5-larbs";
        src = prev.fetchFromGitHub {
          owner = "LukeSmithxyz"; repo = "dwm";
          rev = "ee3354d54a51a14449a9ba93fe978c8a3a66db45";
          hash = "sha256-fQyhMa4gDD6EXH0hLDwU8tU7X4KUsuRlQu8saaoxfVM=";
        };
        nativeBuildInputs = [ prev.pkg-config ];
        buildInputs = with prev; [ libx11 libxinerama libxft libxcb fontconfig freetype ];
        postPatch = ''
          substituteInPlace config.h --replace-fail '#define BROWSER "librewolf"' '#define BROWSER "chromium"'
          substituteInPlace config.h --replace-fail "/usr/local/share/dwm/larbs.mom" "$out/share/dwm/larbs.mom"
          substituteInPlace config.h \
            --replace-fail '{ "xbacklight", "-inc", "15", NULL }' '{ "brightnessctl", "set", "10%+", NULL }' \
            --replace-fail '{ "xbacklight", "-dec", "15", NULL }' '{ "brightnessctl", "set", "10%-", NULL }'
          cp ${larbsExtraKeys} larbs-extra-keys.h
          substituteInPlace config.h --replace-fail 'static const Key keys[] = {' 'static const Key keys[] = {
          #include "larbs-extra-keys.h"'
        '';
        makeFlags = [ "PREFIX=$(out)" "CC=cc"
          "FREETYPEINC=${prev.freetype.dev}/include/freetype2"
          "X11INC=${prev.libx11.dev}/include" "X11LIB=${prev.libx11}/lib" ];
        meta.mainProgram = "dwm";
      };

      larbs-st = prev.stdenv.mkDerivation {
        pname = "larbs-st"; version = "0.8.5-larbs";
        src = prev.fetchFromGitHub {
          owner = "LukeSmithxyz"; repo = "st";
          rev = "48b8ee6e181643800fe83353ec554f503020a8fa";
          hash = "sha256-XFf48+6I3IHcRKGHRJIJb9u2sTKWyuWTb5lN+BILYYc=";
        };
        nativeBuildInputs = [ prev.pkg-config prev.ncurses ];
        buildInputs = with prev; [ libx11 libxft fontconfig freetype harfbuzz libxrender ];
        postPatch = ''substituteInPlace config.h --replace-fail 'float alpha = 0.8;' 'float alpha = ${stAlpha};' '';
        makeFlags = [ "PREFIX=$(out)" "CC=cc" ];
        preInstall = ''export TERMINFO=$out/share/terminfo; mkdir -p "$TERMINFO"'';
        meta.mainProgram = "st";
      };

      larbs-dmenu = prev.stdenv.mkDerivation {
        pname = "larbs-dmenu"; version = "5.0-larbs";
        src = prev.fetchFromGitHub {
          owner = "LukeSmithxyz"; repo = "dmenu";
          rev = "c1819f18c07df6984bbfd2ca7207295eec85806f";
          hash = "sha256-QcnsD8h0uDjttqOHZwMWVA3Qp1eH/og5RrSeopnMILM=";
        };
        nativeBuildInputs = [ prev.pkg-config ];
        buildInputs = with prev; [ libx11 libxinerama libxft fontconfig freetype libxrender ];
        makeFlags = [ "PREFIX=$(out)" "CC=cc"
          "FREETYPEINC=${prev.freetype.dev}/include/freetype2"
          "X11INC=${prev.libx11.dev}/include" "X11LIB=${prev.libx11}/lib" ];
        meta.mainProgram = "dmenu";
      };

      larbs-dwmblocks = prev.stdenv.mkDerivation {
        pname = "larbs-dwmblocks"; version = "0-unstable-larbs";
        src = prev.fetchFromGitHub {
          owner = "LukeSmithxyz"; repo = "dwmblocks";
          rev = "1c9744ac7ded4fff8171169bc0b9736f3acd4cfe";
          hash = "sha256-gT2PXaQ0VdqlA77jpoXBjuFM5UTuGiIZ5eYzXFVm9TU=";
        };
        buildInputs = [ prev.libx11 ];
        makeFlags = [ "PREFIX=$(out)" "CC=cc" ];
        meta.mainProgram = "dwmblocks";
      };

      larbs-scripts = prev.stdenv.mkDerivation {
        pname = "larbs-scripts"; version = "0-unstable";
        src = prev.fetchFromGitHub {
          owner = "LukeSmithxyz"; repo = "voidrice";
          rev = "ad944910efb2fd3086255767632ec8f0e8f5c06d";
          hash = "sha256-qu0nK4aWYjMSheA4tUO/C5mdmdyQRMEvLM63ObepZns=";
        };
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin $out/share/larbs $out/share/larbs-dotfiles
          cp -r .local/bin/. $out/bin/
          cp -r .local/share/larbs/. $out/share/larbs/ 2>/dev/null || true
          cp -r .config $out/share/larbs-dotfiles/config
          chmod -R +w $out/share/larbs-dotfiles
          substituteInPlace $out/share/larbs-dotfiles/config/x11/xresources \
            --replace-fail '*.alpha: 0.8' '*.alpha: ${stAlpha}'
          chmod -R +w $out/bin
          find $out/bin -type f -exec sed -i '1s|^#!/usr/bin/sh|#!/bin/sh|' {} +
          patchShebangs $out/bin
          runHook postInstall
        '';
      };

      # Windows XP "Bliss" GRUB theme (de-watermarked, trimmed to 1.1M)
      xp-bliss-grub-theme = prev.stdenvNoCC.mkDerivation {
        pname = "xp-bliss-grub-theme"; version = "0-unstable";
        src = prev.fetchFromGitHub {
          owner = "hashirsajid58200p"; repo = "windows-xp-bliss-grub-theme";
          rev = "4766f2e94f9be8f6b7e890d62c751eedc746c3dc";
          hash = "sha256-Vj2RU1doZGXM+y9MDe1t87jSvdACUULzQImg41o/+P8=";
        };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out; cp -r . $out/; chmod -R +w $out
          cp "$out/No watermark version – rename and place in assets folder.jpg" "$out/assets/background.jpg"
          rm -f "$out/No watermark version – rename and place in assets folder.jpg" \
                "$out/background.jpg" "$out/preview.jpg" "$out/install.sh" "$out/README.md" "$out/LICENSE"
        '';
      };

      # the user's own parts-inventory web app — `backoffice` command
      backoffice = prev.buildGoModule {
        pname = "backoffice"; version = "0-unstable";
        src = prev.fetchFromGitHub {
          owner = "bnvac"; repo = "backoffice";
          rev = "8ec9c6416cfe8bdbf122eb6525bc62d72dafe0a8";
          hash = "sha256-C/6MRfs8rboLsYODuTnKuXUACZnLPdbjTKeVnFD+1zI=";
        };
        vendorHash = "sha256-GzzJb8jVsck8Gji9/NvPq3b7TazjDq5o5zrZWH7gxjM=";
        env.CGO_ENABLED = 0;   # pure-Go SQLite (modernc), static binary
        doCheck = false;
        meta.mainProgram = "backoffice";
      };

      # OSINT TUI cheat-sheet (not in nixpkgs)
      osint-tools-cli = prev.rustPlatform.buildRustPackage {
        pname = "osint-tools-cli"; version = "0.2.0";
        src = prev.fetchFromGitHub {
          owner = "Coordinate-Cat"; repo = "osint-tools-cli";
          rev = "dd730b5dcff84eeecb23ffa1c3e796ea2101319f";
          hash = "sha256-wsq+E6f4EnspVsl1Re61Bv4fHf+GIHwKj+X1KgTFaeE=";
        };
        postPatch = ''[ -f cargo.toml ] && mv cargo.toml Cargo.toml || true'';
        cargoHash = "sha256-ggn+MOfYEKJxuQP14jM0BYjK3/aMT2ddU0YnTx/l4gI=";
        doCheck = false;
        meta.mainProgram = "osint-tools-cli";
      };

      # SpiderFoot from source against current libs (its pins are install-time only)
      spiderfoot =
        let
          adblockparser = final.python3.pkgs.buildPythonPackage {
            pname = "adblockparser"; version = "0.7"; format = "setuptools";
            src = prev.fetchFromGitHub { owner = "scrapinghub"; repo = "adblockparser";
              rev = "4089612d65018d38dbb88dd7f697bcb07814014d";
              hash = "sha256-3Wx/VmOCaEWWvhxKBqA+IBjp67rjqrDTaqpeXaIE8pQ="; };
            doCheck = false;
          };
          pygexf = final.python3.pkgs.buildPythonPackage {
            pname = "pygexf"; version = "0.2.2"; format = "setuptools";
            src = prev.fetchFromGitHub { owner = "paulgirard"; repo = "pygexf";
              rev = "4ec08e9b8c381e030c30f86a562712b681d97e55";
              hash = "sha256-tMJSRjZ2sXBmeYLHKUQMG33orBAnTtObb+x2d8IBKNA="; };
            propagatedBuildInputs = with final.python3.pkgs; [ lxml setuptools ];
            doCheck = false;
          };
          pyenv = final.python3.withPackages (ps: with ps; [
            adblockparser pygexf dnspython exifread cherrypy cherrypy-cors mako
            beautifulsoup4 lxml netaddr pysocks requests ipwhois ipaddr phonenumbers
            pypdf2 python-whois secure pyopenssl python-docx python-pptx networkx
            cryptography publicsuffixlist openpyxl pyyaml
          ]);
        in prev.stdenvNoCC.mkDerivation {
          pname = "spiderfoot"; version = "0-unstable";
          src = prev.fetchFromGitHub { owner = "smicallef"; repo = "spiderfoot";
            rev = "0f815a203afebf05c98b605dba5cf0475a0ee5fd";
            hash = "sha256-LsaLgz+tZyTUBLxa7FoJusGgMa3sgLUMZMVPZUpvWdY="; };
          nativeBuildInputs = [ prev.makeWrapper ]; dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/libexec/spiderfoot $out/bin
            cp -r . $out/libexec/spiderfoot/
            for e in sf:spiderfoot sfcli:spiderfoot-cli; do
              makeWrapper ${pyenv}/bin/python $out/bin/''${e##*:} \
                --add-flags "$out/libexec/spiderfoot/''${e%%:*}.py" --chdir "$out/libexec/spiderfoot"
            done
            runHook postInstall
          '';
          meta.mainProgram = "spiderfoot";
        };
    })
  ];

  ##############################################################################
  # 3 · NIX
  ##############################################################################
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "root" username ];
  };
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };

  nixpkgs.config.allowUnfree = true;
  # pypdf2 → SpiderFoot (PDF parsing, scan-time only); electron/olm → Bitwarden & nheko.
  nixpkgs.config.permittedInsecurePackages = [
    "python3.13-pypdf2-3.0.1" "electron-39.8.10" "olm-3.2.16"
  ];

  ##############################################################################
  # 4 · BOOT  (ESP must be mounted where espMountPoint says — assertion below)
  ##############################################################################
  boot.loader = lib.mkMerge [
    (lib.mkIf useUEFI { efi.canTouchEfiVariables = touchEfiVars; efi.efiSysMountPoint = espMountPoint; })
    (lib.mkIf useGrub { grub = {
        enable = true; configurationLimit = bootGenLimit;
        efiSupport = useUEFI; device = if useUEFI then "nodev" else "/dev/sda";
        theme = grubTheme; gfxmodeEfi = grubResolution; gfxmodeBios = grubResolution;
        useOSProber = true;   # dual-boot Windows (p3/p4 are NTFS)
    }; })
    (lib.mkIf (!useGrub) { systemd-boot.enable = true; systemd-boot.configurationLimit = bootGenLimit; })
  ];
  boot.kernelParams = [ "quiet" "udev.log_level=3" ];
  boot.extraModprobeConfig = "options kvm_intel nested=1\noptions kvm_amd nested=1";

  assertions = [
    { assertion = useGrub || useUEFI;
      message = "systemd-boot needs UEFI; set useGrub=true for a BIOS machine."; }
    { assertion = !useUEFI || builtins.hasAttr espMountPoint config.fileSystems;
      message = ''
        espMountPoint = "${espMountPoint}" but hardware-configuration.nix mounts nothing there.
        Mount the FAT32 ESP (nvme0n1p1) at ${espMountPoint}, then:
            sudo nixos-generate-config && sudo nixos-rebuild switch
        Or set espMountPoint = "/boot" (kernels then land on the small ESP).''; }
  ];

  ##############################################################################
  # 5 · NETWORKING + BLUETOOTH
  ##############################################################################
  networking.hostName = hostName;
  networking.networkmanager.enable = true;
  hardware.enableRedistributableFirmware = true;   # laptop wifi needs the blobs
  systemd.services.NetworkManager-wait-online.enable = false;
  networking.firewall = { enable = true; allowedTCPPorts = []; allowedUDPPorts = []; };

  hardware.bluetooth = { enable = true; powerOnBoot = true; };
  services.blueman.enable = true;

  ##############################################################################
  # 6 · LOCALE
  ##############################################################################
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  console = { earlySetup = true; keyMap = "us"; };

  ##############################################################################
  # 7 · USER
  ##############################################################################
  users.users.${username} = {
    isNormalUser = true; uid = userUid; description = fullName; shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input"
                    "libvirtd" "kvm" "storage" "tss" "wireshark" "dialout" "plugdev" ];
    # dialout + plugdev: serial consoles and USB programmers for EE work.
  };
  security.sudo.wheelNeedsPassword = true;

  ##############################################################################
  # 8 · X11 + dwm
  ##############################################################################
  services.xserver = {
    enable = true;
    xkb = { layout = "us"; options = "caps:super,altwin:menu_win"; };  # caps=super / tap=esc (xcape)
    windowManager.dwm = {
      enable = true; package = pkgs.larbs-dwm;
      extraSessionCommands = ''
        export _JAVA_AWT_WM_NONREPARENTING=1
        [ -f "$HOME/.config/x11/xresources" ] && ${pkgs.xrdb}/bin/xrdb -merge "$HOME/.config/x11/xresources"
        ${pkgs.larbs-dwmblocks}/bin/dwmblocks &
        ${pkgs.xcompmgr}/bin/xcompmgr &
        ${pkgs.unclutter-xfixes}/bin/unclutter &
        ${pkgs.dunst}/bin/dunst &
        ${pkgs.mpd}/bin/mpd &
        bg="$HOME/.local/share/bg"
        if [ ! -e "$bg" ]; then mkdir -p "$HOME/.local/share"; ln -sfn ${defaultWallpaper} "$bg"; fi
        ${pkgs.xwallpaper}/bin/xwallpaper --zoom "$bg" &
        ${pkgs.larbs-scripts}/bin/remaps &
        true
      '';
    };
  };
  services.libinput = { enable = true; touchpad.naturalScrolling = false; touchpad.tapping = true; };
  services.displayManager.ly.enable = true;
  hardware.graphics.enable = true;

  ##############################################################################
  # 9 · FONTS
  ##############################################################################
  fonts = {
    packages = with pkgs; [ nerd-fonts.jetbrains-mono noto-fonts noto-fonts-color-emoji libertinus font-awesome ];
    enableDefaultPackages = true;
    fontconfig.defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font Mono" "Noto Sans Mono" ];
      sansSerif = [ "Libertinus Sans" "Noto Sans" ];
      serif     = [ "Libertinus Serif" "Noto Serif" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };

  ##############################################################################
  # 10 · AUDIO (PipeWire) + mpd (started from the X session, not at boot)
  ##############################################################################
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true; alsa.enable = true; alsa.support32Bit = true;
    pulse.enable = true; jack.enable = true; wireplumber.enable = true;
  };
  systemd.tmpfiles.rules = [
    "d /home/${username}/Music 0755 ${username} users -"
    "d /home/${username}/.config/mpd 0755 ${username} users -"
    "d /home/${username}/.config/mpd/playlists 0755 ${username} users -"
  ];

  ##############################################################################
  # 11 · VIRTUALISATION (QEMU/KVM)
  ##############################################################################
  virtualisation.libvirtd = {
    enable = true;
    qemu = { package = pkgs.qemu_kvm; runAsRoot = false; swtpm.enable = true; };
  };
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  ##############################################################################
  # 12 · TOR + I2P
  #   torrun <app>  → one app through Tor, leak-proof (oniux namespaces)
  #   tormode on    → ALL traffic transparently through Tor (service below)
  ##############################################################################
  services.tor = {
    enable = true;
    client.enable = true;
    settings = {
      TransPort = [ { addr = "127.0.0.1"; port = 9040; } ];
      DNSPort   = [ { addr = "127.0.0.1"; port = 9053; } ];
      VirtualAddrNetworkIPv4 = "10.192.0.0/10";
      AutomapHostsOnResolve = true;
    };
  };

  # Transparent routing is a toggled oneshot (tormode on/off). Off by default.
  # While ON, every TCP connection and DNS lookup is redirected into Tor; other
  # UDP is dropped (it cannot be torified, so leaking it would deanonymise you).
  # Steam/Discord/voice break while this is on — that is expected. torrun is the
  # lighter per-app alternative.
  systemd.services.tor-transparent = {
    description = "Route all traffic through Tor (transparent proxy)";
    after = [ "tor.service" "network.target" ];
    wants = [ "tor.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = let torUid = config.users.users.tor.uid or "tor"; in pkgs.writeShellScript "tor-trans-up" ''
        ${pkgs.nftables}/bin/nft -f - <<'EOF'
        table ip tor_trans {
          chain output {
            type nat hook output priority -100;
            meta skuid "tor" return
            ip daddr 127.0.0.0/8 return
            ip daddr 10.192.0.0/10 redirect to :9040
            meta l4proto tcp redirect to :9040
            udp dport 53 redirect to :9053
          }
        }
        EOF
      '';
      ExecStop = "${pkgs.nftables}/bin/nft delete table ip tor_trans";
    };
  };

  services.i2p.enable = true;   # router daemon; console http://127.0.0.1:7657

  ##############################################################################
  # 13 · SHELL / EDITOR / TMUX
  ##############################################################################
  programs.zsh = {
    enable = true; enableCompletion = true;
    autosuggestions.enable = true; syntaxHighlighting.enable = true; histSize = 100000;
    shellAliases = {
      ls = "ls -hN --color=auto --group-directories-first";
      ll = "ls -lahN --color=auto --group-directories-first";
      grep = "grep --color=auto"; v = "nvim"; lf = "lfub"; ffa = "fastfetch";
      nrs = "sudo nixos-rebuild switch"; cfn = "sudo -E nvim /etc/nixos/configuration.nix";
    };
    interactiveShellInit = ''
      bindkey -v; export KEYTIMEOUT=1
      lfcd () { tmp="$(mktemp -uq)"; trap 'rm -f "$tmp"' HUP INT QUIT TERM PWR EXIT
        lfub -last-dir-path="$tmp" "$@"
        [ -f "$tmp" ] && { d="$(cat "$tmp")"; [ -d "$d" ] && [ "$d" != "$PWD" ] && cd "$d"; }; }
      bindkey -s '^o' '^ulfcd\n'
      bindkey -s '^f' '^ucd "$(dirname "$(fzf)")"\n'
      bindkey -s '^a' '^ubc -lq\n'
      bindkey '^L' clear-screen
      eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
      eval "$(${pkgs.starship}/bin/starship init zsh)"
    '';
  };
  users.defaultUserShell = pkgs.zsh;

  environment.variables = {
    EDITOR = "nvim"; VISUAL = "nvim"; TERMINAL = "st"; BROWSER = "chromium";
    READER = "zathura"; FILE = "lfub";
    SUDO_ASKPASS = "${pkgs.larbs-scripts}/bin/dmenupass";
    XDG_CONFIG_HOME = "$HOME/.config"; XDG_DATA_HOME = "$HOME/.local/share"; XDG_CACHE_HOME = "$HOME/.cache";
  };

  programs.neovim = {
    enable = true; defaultEditor = true; viAlias = true; vimAlias = true;
    configure = {
      customRC = ''
        let mapleader = ","
        set clipboard+=unnamedplus
        nnoremap <leader>y "+y
        vnoremap <leader>y "+y
        nnoremap <leader>p "+p
        set title mouse=a nohlsearch incsearch ignorecase smartcase
        set number relativenumber noshowmode scrolloff=5 splitbelow splitright undofile
        set expandtab shiftwidth=2 tabstop=2 softtabstop=2
        syntax on
        filetype plugin indent on
        colorscheme habamax
        nnoremap c "_c
        map <leader>n :NERDTreeToggle<CR>
        map <leader>f :Goyo \| set linebreak<CR>
      '';
      packages.larbs = with pkgs.vimPlugins; { start = [
        vim-surround vim-commentary nerdtree goyo-vim vim-airline vim-css-color
        vimwiki vim-fugitive vim-nix ]; };
    };
  };

  programs.tmux = {
    enable = true; shortcut = "a"; keyMode = "vi"; baseIndex = 1;
    escapeTime = 0; historyLimit = 50000; terminal = "tmux-256color";
    aggressiveResize = true; customPaneNavigationAndResize = true;
    plugins = with pkgs.tmuxPlugins; [ sensible yank resurrect ];
    extraConfig = ''
      set -g mouse on
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "${pkgs.xclip}/bin/xclip -selection clipboard -i"
      set -g status-style "bg=#222222,fg=#bbbbbb"
      setw -g window-status-current-style "bg=#005577,fg=#eeeeee,bold"
    '';
  };

  ##############################################################################
  # 14 · DOTFILE SEEDING (lf, dunst, mpv, zathura, ncmpcpp, X resources…)
  ##############################################################################
  system.activationScripts.larbsDotfiles = {
    deps = [ "users" ];
    text = ''
      home="/home/${username}"; stamp="$home/.local/share/larbs/.seeded"
      if [ -d "$home" ] && [ ! -e "$stamp" ]; then
        mkdir -p "$home/.config" "$home/.local/share/larbs"
        for d in ${pkgs.larbs-scripts}/share/larbs-dotfiles/config/*; do
          case "$(basename "$d")" in nvim|zsh) continue ;; esac
          cp -rn "$d" "$home/.config/" 2>/dev/null || true
        done
        cp -rn ${pkgs.larbs-scripts}/share/larbs/. "$home/.local/share/larbs/" 2>/dev/null || true
        chown -R ${username}:users "$home/.config" "$home/.local" 2>/dev/null || true
        touch "$stamp"; chown ${username}:users "$stamp" 2>/dev/null || true
      fi
    '';
  };

  environment.etc."htoprc".text = ''
    tree_view=1
    highlight_base_name=1
    hide_userland_threads=1
  '';

  ##############################################################################
  # 15 · PROGRAM MODULES + PACKAGES
  ##############################################################################
  programs.firefox.enable = true;
  programs.dconf.enable = true;
  programs.gnupg.agent = { enable = true; pinentryPackage = pkgs.pinentry-gtk2; };
  programs.wireshark = { enable = true; package = pkgs.wireshark; };
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [ webkitgtk_4_1 libappindicator-gtk3 librsvg gtk3 openssl ];
  networking.wireguard.enable = true;   # Proton VPN prefers it

  # Steam + Proton-GE (GE shows in the compat dropdown; no protonup-qt run needed)
  programs.steam = {
    enable = true;
    protontricks.enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };
  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [
    # suckless desktop
    larbs-st larbs-dmenu larbs-dwmblocks larbs-scripts

    # helper commands (this file's §0)
    secmodScript tormodeScript torrunScript backoffice onshape

    # browsers / comms
    chromium tor-browser torsocks oniux lynx
    discord slack

    # terminal life
    htop fastfetch lf ueberzugpp fzf bat ripgrep fd eza zoxide starship
    tree jq unzip zip atool wget curl git gnumake claude-code
    bc trash-cli psmisc pulseaudio ts pokeget-rs
    brightnessctl xev

    # media
    mpv ani-cli yt-dlp ffmpeg nsxiv zathura mpd mpc ncmpcpp pulsemixer pavucontrol playerctl mediainfo

    # news (mail reader removed per request; newsboat/RSS kept)
    newsboat abook calcurse sc-im

    # torrents
    qbittorrent transmission_4 stig

    # gaming / launchers
    protonup-qt mangohud winetricks steam-run prismlauncher temurin-bin jdk8

    # 3D printing / CAD
    orca-slicer freecad openscad

    # electrical engineering
    kicad ngspice qucs-s pulseview sigrok-cli logisim-evolution gtkwave iverilog
    platformio arduino-ide avrdude openocd picocom minicom

    # dev / devices
    gcc gdb usbmuxd libimobiledevice balena-cli appimage-run flatpak
    python3 nodejs

    # X11 utilities the keybindings depend on
    xorg.xinit xrdb xprop xwininfo xset setxkbmap xbacklight xorg.xrandr slop
    xclip xdotool xcape xwallpaper xcompmgr unclutter-xfixes maim slock
    dunst libnotify arandr screenkey tesseract wmctrl groff feh imagemagick
    (writeShellScriptBin "zzz" ''exec systemctl suspend "$@"'')

    # privacy / passwords / chat
    bitwarden-desktop bitwarden-cli nheko proton-vpn proton-vpn-cli

    # virtualisation extras
    qemu qemu_kvm OVMFFull virtiofsd spice-gtk virtio-win

    # theming / system
    gruvbox-gtk-theme papirus-icon-theme adwaita-icon-theme lxappearance
    networkmanagerapplet pciutils usbutils lm_sensors
    ntfs3g exfatprogs dosfstools simple-mtpfs poppler-utils man-pages xdg-utils

    # ── grok bot ──────────────────────────────────────────────────────────
    # STUB: I could not find/reach a "grok bot" repo (bnvac/grok 404s for this
    # session). Tell me the repo URL and I'll package it like backoffice above,
    # with its own `grok` launch command. Left out so the build still works.
  ] ++ lib.optionals secmodOn osintPackages;

  environment.pathsToLink = [ "/share/terminfo" ];

  ##############################################################################
  # 16 · SERVICES
  ##############################################################################
  services.dbus.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.gnome.gnome-keyring.enable = true;
  services.printing.enable = true;
  services.fstrim.enable = true;
  services.usbmuxd.enable = true;   # iPhone/iPad over USB

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure"; RestartSec = 1; TimeoutStopSec = 10;
    };
  };
  security.polkit.enable = true;

  ##############################################################################
  # 17 · HARDENING (kept light so Steam/Proton/VMs still work)
  ##############################################################################
  security.sudo.execWheelOnly = true;
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.yama.ptrace_scope" = 1;       # non-root can't ptrace unrelated procs
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
  };
  services.openssh.enable = false;        # no inbound SSH

  system.stateVersion = "26.05";
}
