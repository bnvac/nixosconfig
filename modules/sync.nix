# Syncthing — share files between the desktop and laptop, and sync Neb's state
# so the two Neb instances share config/facts.
#
# Two folders:
#   ~/Sync        general shared files (both machines)
#   ~/.config/neb-shared   Neb-to-Neb (settings + shared notes; see caveat)
#
# Pairing: set both IDs in settings.nix (syncIds) and it's fully declarative.
# Left blank, Syncthing still runs — pair by hand at http://127.0.0.1:8384.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  me = s.device;                    # "desktop" | "laptop"
  other = if me == "desktop" then "laptop" else "desktop";
  otherId = s.syncIds.${other} or "";
  havePeer = otherId != "";
  peers = lib.optionals havePeer [ other ];
in
{
  services.syncthing = {
    enable = true;
    user = s.username;
    dataDir = "/home/${s.username}";
    configDir = "/home/${s.username}/.config/syncthing";
    openDefaultPorts = true;
    overrideDevices = false;        # don't fight hand-pairing when IDs are blank
    overrideFolders = false;

    settings = {
      devices = lib.mkIf havePeer { ${other}.id = otherId; };
      folders = {
        "Sync" = {
          path = "/home/${s.username}/Sync";
          devices = peers;
        };
        "neb-shared" = {
          path = "/home/${s.username}/.config/neb-shared";
          devices = peers;
          # Neb's live SQLite db must NOT sync (concurrent writers corrupt it);
          # share config + any exported notes instead.
          ignorePerms = false;
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /home/${s.username}/Sync 0755 ${s.username} users -"
    "d /home/${s.username}/.config/neb-shared 0755 ${s.username} users -"
    "d /home/${s.username}/DeviceLink 0755 ${s.username} users -"
  ];

  # devlink PIN pairing shouts its device ID over link-local multicast
  # (239.255.77.77:58846, TTL 1) so `devlink pin <code>` on both machines can
  # find each other. Only this UDP port; the shout never leaves the LAN.
  networking.firewall.allowedUDPPorts = [ 58846 ];

  # ── devlink: link the two machines with a code, send anything between them ──
  # `devlink` manages its own Syncthing folder (~/DeviceLink) through the API.
  # Easiest linking: run `devlink pin <code>` (or type the code in the window)
  # on BOTH machines with the same code — they find each other on the LAN and
  # link, no IDs to copy. (Manual fallback: `devlink id` then `devlink link
  # <id>`.) Files dropped in ~/DeviceLink — or sent from the window — appear on
  # the other side.
  systemd.user.services.devlink = {
    description = "DeviceLink: auto-accept peers + notify on arrivals";
    wantedBy = [ "default.target" ];
    after = [ "syncthing.service" ];
    path = [ pkgs.libnotify ];
    serviceConfig = { ExecStart = "${pkgs.devlink}/bin/devlink auto"; Restart = "on-failure"; RestartSec = 5; };
  };
  systemd.user.services.devlink-ui = {
    description = "DeviceLink window backend";
    wantedBy = [ "default.target" ];
    serviceConfig = { ExecStart = "${pkgs.devlink}/bin/devlink ui --port 7010"; Restart = "on-failure"; RestartSec = 5; };
  };

  environment.systemPackages = [
    pkgs.devlink
    # opens the window (the ui service serves it)
    (pkgs.makeDesktopItem {
      name = "devlink"; desktopName = "DeviceLink";
      exec = "${pkgs.chromium}/bin/chromium --app=http://127.0.0.1:7010";
      icon = "network-transmit-receive"; categories = [ "Network" "Utility" ];
    })
    (pkgs.writeShellScriptBin "devlink-window" ''exec ${pkgs.chromium}/bin/chromium --app=http://127.0.0.1:7010'')
  ];
}
