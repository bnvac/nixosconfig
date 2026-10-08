# Always on: nix, boot, network, user, audio, fonts, shell, hardening, `mod`.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;

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
