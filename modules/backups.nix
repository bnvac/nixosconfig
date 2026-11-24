# Backups — encrypted restic snapshots, every day, of what's yours.
#
# Where to: your home server, over Tailscale (settings.homelabServer is set:
# the `homelab` module there runs the backup server), from anywhere you are.
# Otherwise an external drive (settings.backupRepo). Syncthing mirrors your
# mistakes as fast as your files; these snapshots keep history you can go
# back to (7 daily, 4 weekly, 6 monthly).
#
# Only what your config can't give back: your home folder and this machine's
# own settings (settings.local.nix, hardware-configuration.nix, uncommitted
# edits). Not the rest of /etc/nixos (git), the Nix store, caches, compilers'
# downloads, Steam games, Flatpak apps, VM disks or AI models.
#
#   backup setup          once: the passphrase (same on all machines), first backup
#   backup                back up now · backup snapshots · backup restore …
#   backup machines       what's on the server
#   backup bring NAME     a new machine gets NAME's home folder and modules
#
# Nothing set up yet → the daily run just reminds you. Away from home without
# Tailscale, or the drive unplugged → it skips quietly and catches up later.
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  server = s.homelabServer or "";
  # The home server itself backs up to a drive (backing up to itself would
  # lose both copies at once).
  toServer = server != "" && !(s.modules.homelab or false);
  repo = s.backupRepo or (if toServer then "rest:http://${server}:8010/${s.hostName}/"
                          else "/run/media/${s.username}/BACKUP/restic");
in
{
  my.packages = [ pkgs.restic pkgs.backup ];
  environment.sessionVariables = { BACKUP_REPO = repo; BACKUP_SERVER = server; };

  systemd.user.services.backup = {
    description = "Daily backup (restic)";
    environment = { BACKUP_REPO = repo; BACKUP_SERVER = server; };
    path = [ "/run/current-system/sw" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.backup}/bin/backup auto";
      Nice = 15;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.backup = {
    description = "Daily backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;              # catch up after the machine was off
      RandomizedDelaySec = "30m";
    };
  };

  my.menu."System/Backups" = [
    { label = "Back up now"; run = "backup now"; mode = "term"; }
    { label = "Set up backups (passphrase)"; run = "backup setup"; mode = "term"; }
    { label = "My backups (snapshots)"; run = "backup snapshots"; mode = "term"; }
    { label = "Browse a backup (opens a folder)"; mode = "term";
      run = "mkdir -p ~/backup-browse && echo 'Opening… close this window to stop.' && (sleep 4; thunar ~/backup-browse) & backup mount ~/backup-browse"; }
  ];
}
