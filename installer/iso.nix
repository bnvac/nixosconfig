# The Hearth installer USB: a small live system that runs `hearth-install`.
#
# Build it (about 1 GB):
#   nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage \
#     -I nixos-config=installer/iso.nix
# then write result/iso/hearth-installer.iso to a USB stick (Ventoy,
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
  hearth-install = pkgs.writeShellApplication {
    name = "hearth-install";
    runtimeInputs = with pkgs; [ systemd git curl parted dosfstools e2fsprogs cryptsetup util-linux gawk gnused gnugrep coreutils networkmanager ];
    text = builtins.readFile ./install.sh;
  };
in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  image.baseName = lib.mkForce "hearth-installer";
  isoImage.volumeID = "HEARTH";
  isoImage.appendToMenuLabel = " — Hearth installer";

  environment.etc."hearth-src".source = src;
  environment.systemPackages = [ hearth-install pkgs.git ];

  # Wi-Fi through NetworkManager (nmtui), not the minimal ISO's wpa_supplicant.
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;
  networking.hostName = "hearth-installer";
  boot.zfs.forceImportRoot = false;

  services.getty.helpLine = lib.mkForce ''

    Welcome to the Hearth installer.  To install, type:   hearth-install

    (Wi-Fi first? It asks. Everything on the disk you pick will be erased.)
  '';
  # Say it once more right at the prompt.
  programs.bash.interactiveShellInit = ''
    [ "$(tty)" = /dev/tty1 ] && printf '\n  Type \033[1mhearth-install\033[0m and press Enter to install Hearth.\n\n'
  '';
}
