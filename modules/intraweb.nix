# intraweb — your own local-first neighborhood web (bnvac/intraweb).
#
# One static binary. `intraweb up` joins whatever LAN you're on: neighbors find
# each other in about a second (mDNS + UDP broadcast), visit each other's pages,
# share files and send each other signed mail. No server, no internet, no
# accounts — your identity is an Ed25519 key in ~/.intraweb that you can copy
# between machines. Dashboard at http://localhost:8420.
#
# This module runs `intraweb up` as a background user service so you're always
# in the neighborhood when your session is up. It announces presence on the
# current network; `systemctl --user disable --now intraweb` stops that, or set
# `intrawebAutostart = false` in settings.nix. Running a HUB (claims
# intranet.local on port 80) stays a deliberate manual step — `sudo intraweb up
# --hub --hub-name <name>` — since it needs the privileged port.
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  autostart = s.intrawebAutostart or true;
in
{
  environment.systemPackages = [ pkgs.intraweb ];

  systemd.user.services.intraweb = lib.mkIf autostart {
    description = "intraweb — join the neighborhood web on this LAN";
    wantedBy = [ "default.target" ];
    after = [ "network.target" ];
    # `intraweb up` is the whole daemon: dashboard, discovery, mail, file serving.
    serviceConfig = {
      ExecStart = "${pkgs.intraweb}/bin/intraweb up";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Ports (all on the LAN only — intraweb speaks to no one off the network):
  #   8420/tcp  dashboard + JSON API + mail delivery + file downloads
  #   8420/udp  UDP broadcast beacon (backup discovery where multicast is dropped)
  #   5353/udp  mDNS (_intraweb._tcp.local) — the primary discovery path
  #   8480-8489 `intraweb serve <folder>` publishes a folder on the next free port
  #   (port 80 is claimed only when you run a hub, by hand — not opened here)
  networking.firewall.allowedTCPPorts = [ 8420 ];
  networking.firewall.allowedTCPPortRanges = [ { from = 8480; to = 8489; } ];
  networking.firewall.allowedUDPPorts = [ 8420 5353 ];
}
