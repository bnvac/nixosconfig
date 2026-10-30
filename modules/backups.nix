# Backups — restic snapshots to an external drive, on a daily timer.
#
# Syncthing mirrors files between the machines, but it mirrors mistakes just as
# fast: a deletion or a bad edit lands everywhere. restic is the actual safety
# net — append-only, encrypted, deduplicated snapshots with history you can
# restore from. It backs up $HOME and /etc/nixos (minus caches, Steam, VMs,
# node_modules…) to the drive named in settings.nix → backupRepo.
#
# Setup, once:
#   1. Plug in the drive (it mounts under /run/media/<you>/<label>).
#   2. Put a strong passphrase in ~/.config/restic/password (chmod 600) — or
#      manage it with the `secrets` module, which drops it at
#      /run/secrets/restic-password. Keep a copy of this passphrase somewhere
#      safe: without it the backup cannot be restored, by design.
#   3. `backup now` — it creates the repo and takes the first snapshot.
# After that the daily timer runs on its own and quietly skips when the drive
# isn't plugged in. `backup snapshots`, `backup restore latest --target DIR`.
{ pkgs, ... }:
let
  s = import ../settings.nix;
  repo = s.backupRepo or "";
in
{
  my.packages = [ pkgs.restic pkgs.backup ];
  environment.sessionVariables.BACKUP_REPO = repo;   # so `backup …` works in your shell

  systemd.user.services.backup = {
    description = "restic backup to the external drive";
    serviceConfig = {
      Type = "oneshot";
      Environment = [ "BACKUP_REPO=${repo}" ];
      ExecStart = "${pkgs.backup}/bin/backup auto";
    };
  };
  systemd.user.timers.backup = {
    description = "daily restic backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;              # catch up after the machine was off
      RandomizedDelaySec = "30m";
    };
  };
}
