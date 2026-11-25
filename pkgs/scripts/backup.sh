# backup — encrypted restic snapshots of what's yours on this machine.
#
#   backup             same as `backup auto`
#   backup now         take a snapshot right now
#   backup auto        take one IF the destination is there and a passphrase is set
#                      (the daily timer runs this; an unplugged drive or being away
#                      from your tailnet is a reminder, not an error)
#   backup setup       make (or enter) the backup passphrase, then back up
#   backup machines    which machines have backups on your home server
#   backup bring NAME  set this machine up from NAME's backup: its home folder,
#                      and which modules it had on (for a new or reinstalled machine)
#   backup <restic…>   anything else goes straight to restic, repo and passphrase
#                      set: `backup snapshots`, `backup restore latest --target /tmp/r`,
#                      `backup check`, `backup mount ~/mnt`, `backup diff <a> <b>`
#
# What's saved: your home folder, plus the two files that make this machine
# itself (settings.local.nix, hardware-configuration.nix) and any edits to
# /etc/nixos you haven't committed. What's NOT: anything your config or the
# internet can give back: the rest of /etc/nixos (it's in git), the Nix
# store and profiles, caches, compilers and package downloads (rustup, cargo,
# go, npm), Steam games, Flatpak apps, VM disks, AI models, node_modules.
#
# Config comes from the environment (the `backups` module sets it):
#   BACKUP_REPO     where: rest:http://<server>:8010/<this machine>/ (your home
#                   server, over Tailscale) or a folder on an external drive
#   BACKUP_SERVER   the home server's name, for `machines` and `bring`
# The passphrase is read from the first of these that exists:
#   /run/secrets/restic-password   (the `secrets` module)
#   ~/.config/restic/password      (`backup setup` makes it)

repo="${BACKUP_REPO:-}"
server="${BACKUP_SERVER:-}"
port=8010
[ -n "$repo" ] || { echo "backup: BACKUP_REPO is empty (settings: backupRepo or homelabServer)." >&2; exit 2; }

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

state="${XDG_STATE_HOME:-$HOME/.local/state}/backup"

# Is the destination there right now? (drive plugged in / server reachable)
reachable() {
  case "$repo" in
    rest:*)
      local base=${repo#rest:}
      [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "$base")" != 000 ] ;;
    /*) [ -d "$(dirname "$repo")" ] ;;
    *) true ;;
  esac
}
where() {
  case "$repo" in
    rest:*) echo "your home server ($server) isn't reachable: are you on Tailscale?" ;;
    *) echo "the backup drive isn't plugged in ($(dirname "$repo"))." ;;
  esac
}

# The machine-only files of /etc/nixos (not in git), and uncommitted edits.
nixos_bits() {
  local f
  for f in settings.local.nix hardware-configuration.nix pkgs/pins.local.json pkgs/releases.local.json; do
    [ -r "/etc/nixos/$f" ] && echo "/etc/nixos/$f"
  done
  mkdir -p "$state"
  if git -C /etc/nixos rev-parse --git-dir >/dev/null 2>&1; then
    git -C /etc/nixos diff HEAD > "$state/nixos-uncommitted.diff" 2>/dev/null || true
  fi
}

run_backup() {
  reachable || { note "skipped: $(where)"; return 0; }
  if [ -z "$pwfile" ]; then
    note "no backup passphrase yet. Run: backup setup"
    return 0
  fi
  if ! restic cat config >/dev/null 2>&1; then
    note "setting up the backup…"
    restic init || { note "could not create the backup repository."; return 1; }
  fi
  local paths status=0
  mapfile -t paths < <(echo "$HOME"; nixos_bits)
  # --exclude-caches skips any folder a tool marked as a cache (CACHEDIR.TAG),
  # e.g. Rust's target/, without skipping your own folders called "target".
  restic backup "${paths[@]}" \
      --one-file-system \
      --exclude-caches \
      --exclude "$HOME/.cache" \
      --exclude "$HOME/.local/share/Trash" \
      --exclude "$HOME/.nix-profile" \
      --exclude "$HOME/.nix-defexpr" \
      --exclude "$HOME/.local/state/nix" \
      --exclude "$HOME/.local/share/Steam" \
      --exclude "$HOME/.steam" \
      --exclude "$HOME/.local/share/flatpak" \
      --exclude "$HOME/.var/app/*/cache" \
      --exclude "$HOME/.local/share/containers" \
      --exclude "$HOME/.local/share/libvirt" \
      --exclude "$HOME/.local/share/Ollama" \
      --exclude "$HOME/.ollama" \
      --exclude "$HOME/.rustup" \
      --exclude "$HOME/.cargo/registry" \
      --exclude "$HOME/.cargo/git" \
      --exclude "$HOME/go/pkg" \
      --exclude "$HOME/.npm" \
      --exclude "$HOME/.local/share/PrismLauncher/libraries" \
      --exclude "$HOME/.local/share/PrismLauncher/assets" \
      --exclude "$HOME/.local/share/PrismLauncher/meta" \
      --exclude "**/node_modules" \
      --exclude "**/.direnv" \
      --exclude "**/Cache" \
      --exclude "**/Code Cache" \
      --exclude "**/GPUCache" \
      --exclude "**/Service Worker/CacheStorage" || status=$?
  # restic: 0 = all saved; 3 = saved, but a few files couldn't be read.
  if [ "$status" -eq 0 ] || [ "$status" -eq 3 ]; then
    restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 >/dev/null 2>&1 || true
    mkdir -p "$state" && touch "$state/last-success"     # menu doctor reads this
    if [ "$status" -eq 3 ]; then
      note "backup done (a few files couldn't be read: journalctl --user -u backup -e)."
    else
      note "backup done."
    fi
  else
    note "backup FAILED: journalctl --user -u backup -e"
    return 1
  fi
}

machines_json() {
  [ -n "$server" ] || { echo "backup: no home server set (settings: homelabServer)." >&2; return 1; }
  curl -fsS --max-time 8 "http://$server/backups.json" \
    || { echo "backup: couldn't reach $server (on Tailscale?)." >&2; return 1; }
}

cmd="${1:-auto}"
case "$cmd" in
  auto | now) run_backup ;;

  setup)
    if [ -n "$pwfile" ]; then
      echo "A passphrase is already set ($pwfile)."
    else
      mkdir -p "$HOME/.config/restic"; umask 077
      echo "Your backups are encrypted with a passphrase. Use the SAME one on all your"
      echo "machines (then any of them can restore any other)."
      read -r -s -p "Type it, or press Enter to make a new one: " pw </dev/tty || pw=""; echo
      if [ -z "$pw" ]; then
        pw=$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 24)
        echo; echo "  Your backup passphrase:  $pw"; echo
        echo "  Save it in Proton Pass NOW. Without it nobody, not even you, can restore."
      fi
      printf '%s' "$pw" > "$HOME/.config/restic/password"
      pwfile="$HOME/.config/restic/password"; export RESTIC_PASSWORD_FILE="$pwfile"
    fi
    run_backup ;;

  machines)
    j=$(machines_json) || exit 1
    jq -r '.[] | "  \(.name)\t last backup \(.updated)"' <<<"$j" | column -t -s $'\t'
    ;;

  bring)
    from="${2:-}"
    [ -n "$from" ] || { echo "usage: backup bring <machine>   (backup machines lists them)"; exit 2; }
    [ -n "$server" ] || { echo "backup: no home server set (settings: homelabServer)."; exit 2; }
    export RESTIC_REPOSITORY="rest:http://$server:$port/$from/"
    if ! restic cat config >/dev/null 2>&1; then
      unset RESTIC_PASSWORD_FILE
      read -r -s -p "Backup passphrase of $from: " RESTIC_PASSWORD </dev/tty; echo
      export RESTIC_PASSWORD
      restic cat config >/dev/null || { echo "That passphrase doesn't open $from's backup."; exit 1; }
    fi
    snap=$(restic snapshots latest --json) || exit 1
    oldhome=$(jq -r '[.[0].paths[] | select(startswith("/etc/") | not)][0] // empty' <<<"$snap")
    [ -n "$oldhome" ] || { echo "$from's latest backup has no home folder."; exit 1; }
    when=$(jq -r '.[0].time[:16]' <<<"$snap" | tr T ' ')
    echo "Restoring $from's home folder (backup from $when) into $HOME."
    echo "Files with the same name here are replaced; nothing else is deleted."
    read -r -p "Go ahead? [y/N] " a </dev/tty; [ "$a" = y ] || [ "$a" = Y ] || exit 0
    restic restore "latest:$oldhome" --target "$HOME" \
      --exclude "/.config/restic" --exclude "/.cache" || exit 1
    # Which modules it had on → this machine (needs your password once).
    tmp=$(mktemp)
    if restic dump latest /etc/nixos/settings.local.nix > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      mods=$(nix-instantiate --eval --strict --json -E "(import $tmp).modules or {}" 2>/dev/null || echo '{}')
      hs=$(nix-instantiate --eval --strict --json -E "(import $tmp).homelabServer or \"\"" 2>/dev/null || echo '""')
      if [ "$mods" != '{}' ]; then
        echo "$from had these modules set: $(jq -r 'to_entries | map("\(.key)=\(if .value then "on" else "off" end)") | join(" ")' <<<"$mods")"
        read -r -p "Use the same here? [Y/n] " a </dev/tty
        if [ "$a" != n ] && [ "$a" != N ]; then
          jq -r 'to_entries[] | "\(.key) \(if .value then "on" else "off" end)"' <<<"$mods" |
            while read -r m v; do nix2-setup module "$m" "$v" </dev/tty || true; done
          [ "$hs" != '""' ] && nix2-setup set homelabServer "$(jq -r . <<<"$hs")" </dev/tty || true
          echo "Run 'menu update' (or rebuild) to install them."
        fi
      fi
    fi
    rm -f "$tmp"
    echo "Done. Log out and back in so every app picks up its settings."
    ;;

  *) exec restic "$@" ;;
esac
