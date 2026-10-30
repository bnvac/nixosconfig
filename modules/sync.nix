# Syncthing between the desktop and laptop, plus DeviceLink on top of it.
#
# Shared folders (my.syncFolders — other modules add theirs, e.g. backoffice):
#   ~/Sync                       general shared files (browser bookmark exports
#                                live in ~/Sync/browser — see browser-sync below)
#   ~/.config/neb-shared         Neb-to-Neb notes (never his live SQLite db)
#
# Pairing: `devlink pin <code>` on both machines links them AND creates/shares
# every folder above. (Filling settings.syncIds instead makes it declarative.
# Without IDs the folders are deliberately NOT declared to NixOS: its module
# re-applies declared folders on every start, which would drop a peer added
# at runtime.)
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  home = "/home/${s.username}";
  other = if s.device == "desktop" then "laptop" else "desktop";
  otherId = s.syncIds.${other} or "";
  havePeer = otherId != "";
  folders = config.my.syncFolders;
  devlinkFolders = lib.concatStringsSep " " (lib.mapAttrsToList (id: path: "${id}=${path}") folders);
in
{
  my.syncFolders = {
    Sync = "${home}/Sync";
    neb-shared = "${home}/.config/neb-shared";
  };

  services.syncthing = {
    enable = true;
    user = s.username;
    dataDir = home;
    configDir = "${home}/.config/syncthing";
    openDefaultPorts = true;
    overrideDevices = false;        # don't fight pairing done at runtime
    overrideFolders = false;
    settings = lib.mkIf havePeer {
      devices.${other}.id = otherId;
      folders = lib.mapAttrs (_: path: { inherit path; devices = [ other ]; }) folders;
    };
  };

  systemd.tmpfiles.rules =
    map (p: "d ${p} 0755 ${s.username} users -") (lib.attrValues folders)
    ++ [ "d ${home}/DeviceLink 0755 ${s.username} users -" ];

  # devlink PIN pairing shouts its device ID over link-local multicast
  # (239.255.77.77:58846, TTL 1) so `devlink pin <code>` on both machines can
  # find each other. Only this UDP port; the shout never leaves the LAN.
  networking.firewall.allowedUDPPorts = [ 58846 ];
  # VNC for `devlink screen` / `devlink view`. Nothing listens here until you
  # actually share; while sharing, x11vnc is restricted to the linked peer's
  # subnet and a fresh per-session password (handed over via the sync folder).
  networking.firewall.allowedTCPPorts = [ 5900 ];

  # ── devlink: link the two machines with a code, send anything between them ──
  # `devlink pin <code>` (or the window) on BOTH machines with the same code
  # links them — nothing is ever accepted automatically. Files/text/tabs sent
  # from the window or `devlink send|tabs` appear on the other side; tab sets
  # reopen by themselves. `devlink screen` / `view` share a whole screen (VNC).
  # Both services ride the desktop session: they open windows and files there.
  environment.sessionVariables.DEVLINK_FOLDERS = devlinkFolders;
  systemd.user.services.devlink = {
    description = "DeviceLink: notify on link requests + arrivals, reopen tab sets";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "syncthing.service" "graphical-session.target" ];
    path = [ pkgs.libnotify "/run/current-system/sw" ];          # notify-send, firefox, xdg-open
    environment.DEVLINK_FOLDERS = devlinkFolders;
    serviceConfig = { ExecStart = "${pkgs.devlink}/bin/devlink auto"; Restart = "on-failure"; RestartSec = 5; };
  };
  systemd.user.services.devlink-ui = {
    description = "DeviceLink window backend";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    path = [ "/run/current-system/sw" ];
    environment.DEVLINK_FOLDERS = devlinkFolders;
    serviceConfig = { ExecStart = "${pkgs.devlink}/bin/devlink ui --port 7010"; Restart = "on-failure"; RestartSec = 5; };
  };
  # Bookmarks: no live sync service. At login (before the browsers start)
  # `browser-sync` writes this machine's bookmarks to ~/Sync/browser and merges
  # in whatever the other machine last exported there. Run it by hand too, or
  # from nixmenu. Passwords are NOT bookmarks — those stay in Bitwarden;
  # `browser-sync passwords` just feeds each browser's own export into it.
  systemd.user.services.browser-sync = {
    description = "Sync browser bookmarks via an export in ~/Sync";
    wantedBy = [ "graphical-session.target" ];
    after = [ "syncthing.service" ];
    path = [ "/run/current-system/sw" ];
    serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.browser-sync}/bin/browser-sync"; };
  };

  my.menu."Sync & devices" = [
    { label = "DeviceLink (send files)"; run = "devlink-window"; }
    { label = "Send my browser tabs to the other machine"; run = "devlink tabs"; }
    { label = "Share my screen (VNC)"; run = "devlink screen"; mode = "term"; }
    { label = "View other screen (VNC)"; run = "devlink view"; }
    { label = "Sync bookmarks"; run = "browser-sync"; mode = "term"; }
    { label = "Browser passwords → Bitwarden"; run = "browser-sync passwords"; mode = "term"; }
  ];
  my.selfhosted = { "DeviceLink" = "http://127.0.0.1:7010"; "Syncthing" = "http://127.0.0.1:8384"; };

  my.packages = [
    pkgs.devlink pkgs.browser-sync
    pkgs.x11vnc pkgs.tigervnc          # `devlink screen` / `devlink view`
    # opens the window (the ui service serves it)
    (pkgs.makeDesktopItem {
      name = "devlink"; desktopName = "DeviceLink";
      exec = "${pkgs.chromium}/bin/chromium --app=http://127.0.0.1:7010";
      icon = "network-transmit-receive"; categories = [ "Network" "Utility" ];
    })
    (pkgs.writeShellScriptBin "devlink-window" ''exec ${pkgs.chromium}/bin/chromium --app=http://127.0.0.1:7010'')
  ];
}
