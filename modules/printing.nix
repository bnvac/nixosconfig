# 3D printing — control Klipper printers over the network.
#
# Two ways to run, depending on where Klipper lives:
#
# A) Printer already runs Klipper + Moonraker (its own Pi, or an Elegoo/Creality
#    board flashed with Klipper). This is the common case. You need nothing but:
#      - a browser to the printer's web UI (its Fluidd/Mainsail page)
#      - OrcaSlicer (in the `ee` module) to slice and send over the network
#      - printrun/pronterface for direct jog + G-code console
#    The one thing NixOS lacks by default is mDNS, so `printer.local` names
#    don't resolve over Ethernet — Avahi below fixes that.
#
# B) THIS machine hosts Klipper to drive a printer wired to it (USB/CAN/Ethernet
#    MCU). Uncomment the self-host block. It needs a printer.cfg for YOUR exact
#    printer, so it's left off until you drop one in /var/lib/moonraker.
{ pkgs, ... }:
{
  # mDNS: lets "printer.local" / "mainsail.local" resolve over Ethernet/Wi-Fi.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    printrun          # pronterface GUI + pronsole: direct jog, temps, G-code
    # orca-slicer is in the ee module; it sends prints to Moonraker over LAN
  ];

  # ── B) self-hosted Klipper stack (uncomment to drive a local printer) ──────
  # services.klipper = {
  #   enable = true;
  #   user = "samadams"; group = "users";
  #   settings = { };                 # or point at your printer.cfg
  # };
  # services.moonraker = {
  #   enable = true;
  #   user = "samadams";
  #   address = "0.0.0.0";            # reachable from other machines on the LAN
  #   settings.authorization = {
  #     cors_domains = [ "*.local" ];
  #     trusted_clients = [ "127.0.0.1" "192.168.0.0/16" "10.0.0.0/8" ];
  #   };
  # };
  # services.fluidd.enable = true;    # web UI at http://<this-host> (or mainsail)
  # networking.firewall.allowedTCPPorts = [ 80 7125 ];
}
