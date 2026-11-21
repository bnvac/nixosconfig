# Syncthing between your machines (two or more), plus DeviceLink on top of it.
#
# Shared folders (my.syncFolders — other modules add theirs, e.g. backoffice):
#   ~/Sync                       general shared files (browser bookmark exports
#                                live in ~/Sync/browser — see browser-sync below)
#   ~/.config/neb-shared         Neb-to-Neb notes (never his live SQLite db)
#
# Pairing: `devlink pin <code>` on both machines links them AND creates/shares
# every folder above; a third machine: pin it with each of the others.
# (Filling settings.syncDevices instead makes it declarative.
# Without IDs the folders are deliberately NOT declared to NixOS: its module
# re-applies declared folders on every start, which would drop a peer added
# at runtime.)
#
# Over Tailscale only (settings.syncOverTailscale, on by default): Syncthing,
# pairing and screen sharing are reachable on the Tailscale interface and
# nowhere else; Syncthing's public discovery and relay servers are off, so
# your files only ever travel inside your tailnet, encrypted, from anywhere.
# Machines are reached at their Tailscale address (pairing records it; links
# made before are moved over by `devlink auto`). Sign every machine in to
# Tailscale once (menu → Network & privacy).
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  tailnetOnly = s.syncOverTailscale or true;
  home = "/home/${s.username}";
  # Every other machine with an ID: settings.syncDevices (any number, by host
  # name) plus the older two-machine settings.syncIds (by device type).
  # This machine is left out by its own host name / device type.
  otherDevice = if s.device == "desktop" then "laptop" else "desktop";
  legacy = lib.optionalAttrs ((s.syncIds.${otherDevice} or "") != "") { ${otherDevice} = s.syncIds.${otherDevice}; };
  declared = s.syncDevices or { };
  legacyNew = lib.filterAttrs (_: id: !(lib.elem id (lib.attrValues declared))) legacy;   # same machine twice
  peers = lib.filterAttrs (name: id: id != "" && name != s.hostName) (declared // legacyNew);
  havePeer = peers != { };
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
    openDefaultPorts = !tailnetOnly;
    overrideDevices = false;        # don't fight pairing done at runtime
    overrideFolders = false;
    settings = lib.mkMerge [
      (lib.mkIf havePeer {
        # Declared machines are reached by their Tailscale (MagicDNS) name.
        devices = lib.mapAttrs (name: id: {
          inherit id;
          addresses = if tailnetOnly then [ "tcp://${name}:22000" "quic://${name}:22000" ] else [ "dynamic" ];
        }) peers;
        folders = lib.mapAttrs (_: path: { inherit path; devices = lib.attrNames peers; }) folders;
      })
      (lib.mkIf tailnetOnly {
        # No one else's servers: no global discovery, no relays, no LAN broadcasts, no port mapping.
        options = {
          globalAnnounceEnabled = false;
          localAnnounceEnabled = false;
          relaysEnabled = false;
          natEnabled = false;
          urAccepted = -1;               # no usage reporting
        };
      })
    ];
  };

  systemd.tmpfiles.rules =
    map (p: "d ${p} 0755 ${s.username} users -") (lib.attrValues folders)
    ++ [ "d ${home}/DeviceLink 0755 ${s.username} users -" ];

  # Ports: Syncthing 22000 (TCP + QUIC), devlink PIN pairing 58846/udp, VNC
  # 5900 for `devlink screen` (nothing listens until you share; then x11vnc
  # takes only the linked machine, with a fresh per-session password).
  # Tailnet-only: open on the Tailscale interface alone. Otherwise the LAN too
  # (pairing then uses link-local multicast that never leaves the LAN).
  networking.firewall.interfaces.tailscale0 = lib.mkIf tailnetOnly {
    allowedTCPPorts = [ 22000 5900 ];
    allowedUDPPorts = [ 22000 58846 ];
  };
  networking.firewall.allowedUDPPorts = lib.optional (!tailnetOnly) 58846;
  networking.firewall.allowedTCPPorts = lib.optional (!tailnetOnly) 5900;

  # ── devlink: link the two machines with a code, send anything between them ──
  # `devlink pin <code>` (or the window) on BOTH machines with the same code
  # links them — nothing is ever accepted automatically. Files/text/tabs sent
  # from the window or `devlink send|tabs` appear on the other side; tab sets
  # reopen by themselves. `devlink screen` / `view` share a whole screen (VNC).
  # Both services ride the desktop session: they open windows and files there.
  environment.sessionVariables = {
    DEVLINK_FOLDERS = devlinkFolders;
    DEVLINK_TAILNET = if tailnetOnly then "1" else "0";
  };
  systemd.user.services.devlink = {
    description = "DeviceLink: notify on link requests + arrivals, reopen tab sets";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "syncthing.service" "graphical-session.target" ];
    path = [ pkgs.libnotify config.services.tailscale.package "/run/current-system/sw" ];   # notify-send, tailscale, the browser
    environment = { DEVLINK_FOLDERS = devlinkFolders; DEVLINK_TAILNET = if tailnetOnly then "1" else "0"; };
    serviceConfig = { ExecStart = "${pkgs.devlink}/bin/devlink auto"; Restart = "on-failure"; RestartSec = 5; };
  };
  systemd.user.services.devlink-ui = {
    description = "DeviceLink window backend";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    path = [ "/run/current-system/sw" ];
    environment = { DEVLINK_FOLDERS = devlinkFolders; DEVLINK_TAILNET = if tailnetOnly then "1" else "0"; };
    serviceConfig = { ExecStart = "${pkgs.devlink}/bin/devlink ui --port 7010"; Restart = "on-failure"; RestartSec = 5; };
  };
  # Bookmarks: no live sync service. At login (before the browsers start)
  # `browser-sync` writes this machine's bookmarks to ~/Sync/browser and merges
  # in whatever the other machine last exported there. Run it by hand too, or
  # from nixmenu. Passwords are NOT bookmarks — those stay in Proton Pass;
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
    { label = "Share my screen (VNC)"; run = "devlink screen"; mode = "term"; }
    { label = "View other screen (VNC)"; run = "devlink view"; }
    { label = "Sync bookmarks"; run = "browser-sync"; mode = "term"; }
    { label = "Browser passwords → Proton Pass"; run = "browser-sync passwords"; mode = "term"; }
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
