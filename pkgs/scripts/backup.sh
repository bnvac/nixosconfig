# backup — restic snapshots of your home + the NixOS config to an external drive.
#
#   backup           same as `backup auto`
#   backup now       take a snapshot right now
#   backup auto      take one IF the drive is plugged in and a password is set
#                    (this is what the daily timer runs; it never errors just
#                     because the drive is unplugged — it reminds you instead)
#   backup <restic…> anything else is passed straight to restic with the repo
#                    and password already set: `backup snapshots`, `backup
#                    restore latest --target /tmp/r`, `backup check`, `backup
#                    mount ~/mnt`, `backup diff <a> <b>`, …
#
# Config comes from the environment (the `backups` module sets it):
#   BACKUP_REPO     the restic repository (settings.nix → backupRepo)
#   BACKUP_PATHS    what to back up (default: $HOME and /etc/nixos)
# The repo password is read from the first of these that exists:
#   /run/secrets/restic-password   (if you manage it with the `secrets` module)
#   ~/.config/restic/password      (a plain 0600 file you create)

repo="${BACKUP_REPO:-}"
if [ -z "$repo" ]; then
  echo "backup: BACKUP_REPO is empty — set backupRepo in settings.nix." >&2
  exit 2
fi

note() {
  echo "backup: $1"
  notify-send -a Backup -i drive-harddisk "Backup" "$1" 2>/dev/null || true
}

pwfile=""
for c in /run/secrets/restic-password "$HOME/.config/restic/password"; do
  if [ -r "$c" ]; then pwfile="$c"; break; fi
done

export RESTIC_REPOSITORY="$repo"
[ -n "$pwfile" ] && export RESTIC_PASSWORD_FILE="$pwfile"

cmd="${1:-auto}"

case "$cmd" in
  auto | now)
    # If the repo is a local path, its parent is the drive's mountpoint; when
    # the drive is unplugged that directory is gone (udisks removes it). Don't
    # treat "not plugged in" as a failure — just say so and stop.
    case "$repo" in
      /*)
        dir=$(dirname "$repo")
        if [ ! -d "$dir" ]; then
          note "backup drive not mounted ($dir) — plug it in to back up."
          exit 0
        fi
        ;;
    esac

    if [ -z "$pwfile" ]; then
      note "no backup password yet — create ~/.config/restic/password (chmod 600), then run: backup now"
      exit 0
    fi

    # First ever run on this drive: make the repo.
    if ! restic cat config >/dev/null 2>&1; then
      note "setting up the backup repo…"
      if ! restic init; then note "could not create the repo."; exit 1; fi
    fi

    read -ra paths <<< "${BACKUP_PATHS:-$HOME /etc/nixos}"
    if restic backup "${paths[@]}" \
        --one-file-system \
        --exclude-caches \
        --exclude "$HOME/.cache" \
        --exclude "$HOME/.local/share/Trash" \
        --exclude "$HOME/.local/share/Steam" \
        --exclude "$HOME/.local/share/containers" \
        --exclude "$HOME/.local/share/libvirt" \
        --exclude "$HOME/.local/share/Ollama" \
        --exclude "**/node_modules" \
        --exclude "**/.direnv" \
        --exclude "**/target"; then
      # Keep a sensible ladder of old snapshots and reclaim the rest.
      restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 >/dev/null || true
      note "backup complete."
    else
      note "backup FAILED — see: journalctl --user -u backup -e"
      exit 1
    fi
    ;;
  *)
    # Pass through to restic for restore/snapshots/check/mount/etc.
    exec restic "$@"
    ;;
esac
