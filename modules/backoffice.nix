# The parts-inventory web app (github.com/bnvac/backoffice).
#
#   backoffice          open it (starts the service if needed) — http://127.0.0.1:8080
#   backoffice-sync     keep the inventory in step with the other machine
#
# It runs as a user service with a fixed data dir. (Started by hand it used
# DATA_DIR=./data — relative to wherever you ran it — so a different folder
# meant a different, empty inventory.) Listens on loopback only.
#
# With the `sync` module, the inventory hands off between the two machines as
# consistent snapshots (never the live SQLite file, which would corrupt);
# photos sync live as plain files. Optional secrets — AUTH_PASSWORD, NEXAR_*,
# THINGIVERSE_TOKEN… — go in ~/.config/backoffice/env (KEY=value lines).
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  home = "/home/${s.username}";
  data = "${home}/.local/share/backoffice";
  snapshots = "${home}/.local/share/backoffice-sync";
  synced = config.services.syncthing.enable;
  url = "http://127.0.0.1:8080";

  launcher = pkgs.writeShellScriptBin "backoffice" ''
    systemctl --user start backoffice.service
    for _ in $(seq 50); do
      ${pkgs.curl}/bin/curl -fsS -o /dev/null ${url}/healthz && break
      sleep 0.2
    done
    exec ${pkgs.chromium}/bin/chromium --app=${url}
  '';
in
{
  systemd.user.services.backoffice = {
    description = "Backoffice parts inventory";
    wantedBy = [ "default.target" ];
    environment = { DATA_DIR = data; PORT = "127.0.0.1:8080"; };
    serviceConfig = {
      ExecStartPre = lib.optional synced "${pkgs.backoffice-sync}/bin/backoffice-sync --before-start";
      ExecStart = "${pkgs.backoffice}/bin/backoffice";
      EnvironmentFile = "-%h/.config/backoffice/env";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  systemd.user.services.backoffice-sync = lib.mkIf synced {
    description = "Hand backoffice's inventory to/from the other machine";
    serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.backoffice-sync}/bin/backoffice-sync"; };
  };
  systemd.user.timers.backoffice-sync = lib.mkIf synced {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "2min"; OnUnitActiveSec = "2min"; };
  };

  my.syncFolders = lib.mkIf synced {
    backoffice-db = snapshots;
    backoffice-photos = "${data}/photos";
  };

  systemd.tmpfiles.rules = [
    "d ${data} 0700 ${s.username} users -"
    "d ${data}/photos 0755 ${s.username} users -"
    "f ${data}/photos/.stignore 0644 ${s.username} users - remote"   # don't sync the web-image cache
    "d ${snapshots} 0700 ${s.username} users -"
  ];

  environment.systemPackages = [ launcher pkgs.backoffice-sync ];
}
