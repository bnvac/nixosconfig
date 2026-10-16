# QEMU/KVM virtualisation.
{ pkgs, ... }:
let s = import ../settings.nix;
in {
  virtualisation.libvirtd = {
    enable = true;
    qemu = { package = pkgs.qemu_kvm; runAsRoot = false; swtpm.enable = true; };
  };
  virtualisation.spiceUSBRedirection.enable = true;
  programs.virt-manager.enable = true;
  boot.extraModprobeConfig = "options kvm_intel nested=1\noptions kvm_amd nested=1";
  users.users.${s.username}.extraGroups = [ "libvirtd" "kvm" ];
  environment.systemPackages = with pkgs; [ qemu qemu_kvm OVMFFull virtiofsd spice-gtk virtio-win ];
}
