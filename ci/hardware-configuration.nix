# A stand-in for a real machine's hardware-configuration.nix, so CI can build
# the config without one. Never used on a real computer.
{ ... }: {
  fileSystems."/" = { device = "/dev/disk/by-label/hearth"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/ESP"; fsType = "vfat"; };
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" ];
  nixpkgs.hostPlatform = "x86_64-linux";
}
