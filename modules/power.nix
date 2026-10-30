# Power management. Mostly for the laptop (settings.device = "laptop"): on the
# desktop this is a near no-op (just upower for battery-aware UPS/peripherals).
#
# TLP does the real work on battery: a power-saving CPU governor and energy
# policy on battery, full performance on AC, and USB autosuspend. It replaces
# GNOME's power-profiles-daemon, so that one is forced off to avoid a clash.
# The governor/energy-policy settings below are generic and work on any laptop.
# (Battery charge-limit thresholds aren't set here — they depend on specific
#  vendor kernel support and this laptop isn't a ThinkPad; if you ever want them
#  on a supported machine, `tlp-stat -b` shows whether the hardware allows it.)
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  isLaptop = s.device == "laptop";
in
{
  services.upower.enable = true;
  powerManagement.enable = true;

  # TLP and power-profiles-daemon both manage power and must not both run.
  services.power-profiles-daemon.enable = lib.mkForce false;

  services.thermald.enable = lib.mkIf isLaptop true;   # Intel thermal daemon

  services.tlp = lib.mkIf isLaptop {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "low-power";

      # Spin down idle USB devices, but never the keyboard/mouse receiver.
      USB_AUTOSUSPEND = 1;
      USB_EXCLUDE_WWAN = 1;
    };
  };

  my.packages = lib.mkIf isLaptop [ pkgs.powertop ];
}
