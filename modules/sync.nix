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
  ];
}
