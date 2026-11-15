# Power management. Mostly for the laptop (settings.device = "laptop"): on the
# desktop this is a near no-op (just upower for battery-aware UPS/peripherals).
#
# TLP does the real work on battery: a power-saving CPU governor and energy
# policy on battery, full performance on AC, and USB autosuspend. It replaces
# GNOME's power-profiles-daemon, so that one is forced off to avoid a clash.
# The governor/energy-policy settings below are generic and work on any laptop.
# settings.batteryLimit = 80 stops charging at 80% (starts again below 75%):
# a battery kept off 100% lasts years longer. `tlp-stat -b` shows whether
# this laptop supports it. settings.fingerprint turns on the reader.
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  isLaptop = s.device == "laptop";
  limit = s.batteryLimit or null;
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
    } // lib.optionalAttrs (limit != null) {
      START_CHARGE_THRESH_BAT0 = limit - 5;  STOP_CHARGE_THRESH_BAT0 = limit;
      START_CHARGE_THRESH_BAT1 = limit - 5;  STOP_CHARGE_THRESH_BAT1 = limit;
    };
  };
  assertions = [{
    assertion = limit == null || (builtins.isInt limit && limit >= 50 && limit <= 100);
    message = "settings.batteryLimit = ${toString limit}: a whole number from 50 to 100 (or null for no limit).";
  }];

  # Fingerprint reader (settings.fingerprint): unlock, log in and sudo with a
  # finger as well as the password. Enrol one with: fprintd-enroll
  services.fprintd.enable = s.fingerprint or false;

  my.packages = lib.mkIf isLaptop [ pkgs.powertop ];
}
