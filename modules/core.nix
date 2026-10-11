# Always on: nix, boot, network, user, audio, fonts, shell, hardening, `mod`.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;

  # which feature modules are switched on (same marker files the picker reads)
  allModules = lib.pipe (builtins.readDir ../modules) [
    builtins.attrNames
    (map (f: lib.removeSuffix ".nix" f))
    (builtins.filter (m: m != "core"))
  ];
  enabledModules = builtins.filter (m: builtins.pathExists (../mods + "/${m}")) allModules;

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
    ${lib.concatMapStringsSep "\n" (m: "- ${m}") enabledModules}

    (Available but possibly off: ${lib.concatStringsSep ", " allModules})

    ## Commands this system adds
    - `mod list | mod on <name> | mod off <name>` — toggle a module + rebuild.
    - `backoffice` — parts-inventory web app, http://localhost:8080.
    - `grok` — xAI coding CLI.  `claude-code` — Claude Code.
    - `torrun <app>` — run one app through Tor (leak-proof). `tormode on|off` —
      route everything through Tor (only if the `privacy` module is on).
    - `jarvis` (keybind: Super+Shift+backtick) — push-to-talk voice assistant:
      speak, it transcribes (whisper), asks the local model (ollama, with THIS
      file as context), and speaks back (piper). Needs the `assistant` module
      on and a model pulled (`ollama pull llama3.1`).
    - `setbg <image>` — set the wallpaper.
    - `nrs` — `sudo nixos-rebuild switch`.

    ## To change the system (do this, not `nix profile install`)
    1. Edit the relevant file under /etc/nixos (a module, or settings.nix).
    2. `sudo nixos-rebuild switch`. Rollback: pick an older generation at boot,
       or `sudo nixos-rebuild switch --rollback`.
    - Add a package: put it in the fitting module's `environment.systemPackages`.
    - Add a service: a NixOS `services.*` option in the fitting module.
    - Add software built from Git: a derivation in pkgs/default.nix (copy the
      `backoffice` block — it shows the fetchFromGitHub + hash pattern).

    ## Conventions / safety for an assistant acting here
    - This is declarative: nothing is "installed" imperatively. Change files,
      rebuild. Never edit /nix/store.
    - The firewall is on with no open ports; SSH is off. `sudo` needs a password.
    - Desktop is dwm (suckless); the status bar clock + commands are in
      pkgs/default.nix → larbs-dwmblocks. Press Super+F1 for the keybind manual.
    - 3D printers: control over the LAN (mDNS is on, so `*.local` resolves).
      See modules/printing.nix for the self-host Klipper option.
    - Before any outward-facing or irreversible action, confirm with ${s.username}.
  '';

  mod = pkgs.writeShellScriptBin "mod" ''
    dir=/etc/nixos; m="$dir/mods"
    all() { for f in "$dir"/modules/*.nix; do n=$(basename "$f" .nix); [ "$n" = core ] || echo "$n"; done; }
    case "''${1:-list}" in
      list) for n in $(all); do [ -e "$m/$n" ] && echo "  on   $n" || echo "  off  $n"; done ;;
      on)   [ -f "$dir/modules/$2.nix" ] || { echo "no module '$2'"; exit 1; }
            sudo mkdir -p "$m" && sudo touch "$m/$2" && sudo nixos-rebuild switch ;;
      off)  sudo rm -f "$m/$2" && sudo nixos-rebuild switch ;;
      *)    echo "usage: mod list | mod on <name> | mod off <name>" ;;
    esac
  '';
in
{
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
  hardware.bluetooth = { enable = true; powerOnBoot = true; };
  services.blueman.enable = true;
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
    shellAliases = { v = "nvim"; nrs = "sudo nixos-rebuild switch"; ll = "ls -lah --color=auto"; };
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
    mod git curl wget htop fastfetch fzf ripgrep fd bat eza zoxide starship
    tree jq unzip zip gcc gnumake python3 psmisc usbutils pciutils xclip
  ];

  services.fstrim.enable = true;
  services.openssh.enable = false;

  # Jarvis's note-to-self, placed system-wide and in the user's home each rebuild.
  environment.etc."jarvis/SYSTEM.md".source = jarvisDoc;
  system.activationScripts.jarvisDoc.text = ''
    install -Dm644 ${jarvisDoc} /home/${s.username}/SYSTEM.md
    chown ${s.username}:users /home/${s.username}/SYSTEM.md
  '';

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
