# Paper printers and scanners (3D printers are the `printing` module).
#
# Most printers and scanners from the last ten years need no driver at all:
# they announce themselves on the network (or over USB) and speak a standard
# protocol (IPP Everywhere / AirPrint, eSCL / WSD for scanning). This turns
# that on, plus the common drivers for older ones (HP, Brother, Canon, Epson,
# Samsung/Xerox and Gutenprint's long list).
#
#   Add a printer        menu → Devices → Printers & scanners → Add a printer
#                        (most network printers show up on their own)
#   Scan                 menu → Devices → Printers & scanners → Scan (Document Scanner)
#   Print queue          http://localhost:631
#
# Nothing runs until it's needed: CUPS starts the first time something prints.
{ pkgs, ... }:
let
  s = import ../settings.nix;
in
{
  services.printing = {
    enable = true;
    drivers = with pkgs; [ gutenprint hplip brlaser splix foo2zjs epson-escpr2 cnijfilter2 ];
  };
  # Printers and scanners on the network find each other by name (*.local).
  services.avahi = { enable = true; nssmdns4 = true; openFirewall = true; };
  # USB printers and scanners that speak IPP over USB (most since ~2015).
  services.ipp-usb.enable = true;

  # Scanners: driverless network/USB scanners (sane-airscan) plus HP's.
  hardware.sane = {
    enable = true;
    extraBackends = with pkgs; [ sane-airscan hplip ];
  };
  users.users.${s.username}.extraGroups = [ "scanner" "lp" ];

  programs.system-config-printer.enable = true;

  my.menu."Devices/Printers & scanners" = [
    { label = "Add a printer"; run = "system-config-printer"; }
    { label = "Scan a document"; run = "simple-scan"; }
    { label = "What's printing (the queue)"; run = "http://localhost:631/jobs"; mode = "url"; }
    { label = "Printers found on the network"; run = "lpstat -e; echo; avahi-browse -rt _ipp._tcp 2>/dev/null | grep -E 'hostname|txt' | head -20"; mode = "term"; }
  ];

  my.packages = with pkgs; [ simple-scan system-config-printer avahi ];
}
