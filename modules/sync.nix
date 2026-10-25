# Syncthing between the desktop and laptop, plus DeviceLink on top of it.
#
# Shared folders (my.syncFolders — other modules add theirs, e.g. backoffice):
#   ~/Sync                       general shared files
#   ~/.config/neb-shared         Neb-to-Neb notes (never his live SQLite db)
#   ~/.local/share/bookmarks-sync   browser bookmarks (floccus, see below)
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

  # Bookmarks: floccus (in Firefox + Chromium, see apps.nix) syncs to this
  # local WebDAV; Syncthing carries the file to the other machine. Basic auth
  # with a per-machine random password, because a loopback server without one
  # can be read by any website through DNS rebinding.
  bookmarksDav = pkgs.writeShellScript "bookmarks-webdav" ''
    pass="$HOME/.config/bookmarks-sync/pass"
    umask 077; mkdir -p "''${pass%/*}"
    [ -s "$pass" ] || head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$pass"
    exec ${pkgs.rclone}/bin/rclone serve webdav "${home}/.local/share/bookmarks-sync" \
      --addr 127.0.0.1:7020 --user floccus --pass "$(cat "$pass")"
  '';
  bookmarksLogin = pkgs.writeShellScriptBin "bookmarks-login" ''
    f="$HOME/.config/bookmarks-sync/pass"
    [ -s "$f" ] || { echo "bookmark sync hasn't started yet (systemctl --user status bookmarks-webdav)"; exit 1; }
    printf %s "$(cat "$f")" | ${pkgs.xclip}/bin/xclip -selection clipboard 2>/dev/null || true
    cat <<EOF
    In each browser (Firefox and Chromium, on each machine), once:
      floccus icon → Add account → "WebDAV share" (XBEL)
        Server URL           http://127.0.0.1:7020/
        Username             floccus
        Password             $(cat "$f")    (also copied to your clipboard)
        Bookmarks file path  bookmarks.xbel
    EOF
  '';
in
{
  my.syncFolders = {
    Sync = "${home}/Sync";
    neb-shared = "${home}/.config/neb-shared";
    bookmarks = "${home}/.local/share/bookmarks-sync";
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
  systemd.user.services.bookmarks-webdav = {
    description = "Local WebDAV for browser bookmark sync (floccus)";
    wantedBy = [ "default.target" ];
    serviceConfig = { ExecStart = bookmarksDav; Restart = "on-failure"; RestartSec = 5; };
  };

  environment.systemPackages = [
    pkgs.devlink bookmarksLogin
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
