# The nix² installer USB: a small live system that runs `nix2-install`.
#
# Build it (about 1 GB):
#   nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage \
#     -I nixos-config=installer/iso.nix
# then write result/iso/nix2-installer.iso to a USB stick (Ventoy,
# balenaEtcher, GNOME Disks, or: sudo dd if=… of=/dev/sdX bs=4M status=progress).
# GitHub builds it for every release (.github/workflows/iso.yml).
{ config, pkgs, lib, modulesPath, ... }:
let
  # This repo as it is, minus build output and anything machine-specific.
  src = lib.cleanSourceWith {
    src = lib.cleanSource ../.;
    filter = path: _type:
      let n = baseNameOf path; in
      !(builtins.elem n [ "target" "result" "settings.local.nix" "hardware-configuration.nix" "pins.local.json" ]);
  };
  nix2-install = pkgs.writeShellApplication {
    name = "nix2-install";
    runtimeInputs = with pkgs; [ systemd git curl parted dosfstools e2fsprogs cryptsetup util-linux gawk gnused gnugrep coreutils networkmanager ckbcomp kbd ];
    runtimeEnv.NIX2_XKB = "${pkgs.xkeyboard_config}/share/X11/xkb";   # the keyboard layouts it can switch to
    text = builtins.readFile ./install.sh;
  };
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  image.baseName = lib.mkForce "nix2-installer";
  isoImage.volumeID = "NIX2";
  isoImage.appendToMenuLabel = " — nix² installer";

  environment.etc."nix2-src".source = src;
  environment.systemPackages = [ nix2-install pkgs.git ];

  # Wi-Fi through NetworkManager (nmtui), not the minimal ISO's wpa_supplicant.
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;
  networking.hostName = "nix2-installer";
  boot.zfs.forceImportRoot = false;

  services.getty.helpLine = lib.mkForce ''

    Welcome to the nix² installer.  To install, type:   nix2-install

    (Wi-Fi first? It asks. Everything on the disk you pick will be erased.)
  '';
  # Say it once more right at the prompt.
  programs.bash.interactiveShellInit = ''
    [ "$(tty)" = /dev/tty1 ] && printf '\n  Type \033[1mnix2-install\033[0m and press Enter to install nix².\n\n'
  '';
}
