# backoffice-sync — keep backoffice's inventory the same on both machines.
#
# The live database is SQLite in WAL mode, so it is NEVER synced directly (two
# writers, or a half-copied -wal file, corrupt it). Instead this hands off
# consistent snapshots through a Syncthing folder:
#   push   local changed, other side didn't  → VACUUM INTO a snapshot, bump version
#   pull   other side changed, local didn't  → stop backoffice, take the snapshot, start
#   both   changed (used both at once)       → keep this machine's, save the other
#                                              copy in conflicts/, notify, push
# "Changed" compares a hash of the database's contents (.dump), not file times.
# Photos are plain files and sync live in their own folder. Runs every 2 min
# (timer) and before backoffice starts (--before-start: never touches systemctl).
#
#   backoffice-sync [--before-start] [--status]

data="${BACKOFFICE_DATA:-$HOME/.local/share/backoffice}"
sync="${BACKOFFICE_SYNC:-$HOME/.local/share/backoffice-sync}"
db="$data/inventory.db"
state="$data/.sync-state"            # "<version> <local content hash>" at the last push/pull
meta="$sync/meta"                    # "<version> <content hash of snapshot>"; version = gen.host
host=${BACKOFFICE_HOST:-$(uname -n)}
mode=${1:-}

say() { echo "backoffice-sync: $*"; notify-send -a Backoffice -i emblem-synchronizing "Backoffice" "$*" 2>/dev/null || true; }
content_hash() { sqlite3 -readonly "$1" .dump 2>/dev/null | sha256sum | cut -c1-64; }
has_data() {     # does this database hold anything a person entered?
  local n
  n=$(sqlite3 -readonly "$1" "SELECT (SELECT count(*) FROM items)+(SELECT count(*) FROM projects)+(SELECT count(*) FROM folders);" 2>/dev/null || echo 0)
  [ "${n:-0}" -gt 0 ]
}
read_pair() { [ -r "$1" ] && read -r a b <"$1" && printf '%s %s' "$a" "$b" || true; }

mkdir -p "$data" "$sync" "$data/conflicts"
exec 9>"$data/.sync.lock"
flock -n 9 || exit 0                 # another run is busy

# Syncthing renames the loser of a simultaneous write to *.sync-conflict-*;
# never lose those — move them where you'll see them.
for c in "$sync"/*.sync-conflict-*; do
  [ -e "$c" ] || continue
  mv "$c" "$data/conflicts/"
  say "Both machines saved inventory at once — the other copy is in ~/.local/share/backoffice/conflicts/."
done

read -r last_ver last_hash <<<"$(read_pair "$state")"
read -r remote_ver remote_hash <<<"$(read_pair "$meta")"
local_hash=""; [ -f "$db" ] && local_hash=$(content_hash "$db")

if [ "$mode" = --status ]; then
  printf 'local  %s (%s)\nlast   %s\nremote %s\n' "${local_hash:0:12}" "$db" "${last_ver:-none}" "${remote_ver:-none}"
  exit 0
fi

remote_new=false; [ -n "$remote_ver" ] && [ "$remote_ver" != "$last_ver" ] && [ -f "$sync/inventory.db" ] && remote_new=true
local_changed=false
if [ -n "$local_hash" ]; then
  if [ -n "$last_ver" ]; then [ "$local_hash" != "$last_hash" ] && local_changed=true
  else has_data "$db" && local_changed=true        # first run: an empty new DB doesn't count as edits
  fi
fi

push() {
  local gen r l tmp ver snap_hash
  r=${remote_ver%%.*}; l=${last_ver%%.*}; r=${r:-0}; l=${l:-0}
  gen=$(( (r > l ? r : l) + 1 ))
  ver="$gen.$host"
  tmp="$data/.snapshot.tmp"; rm -f "$tmp"
  sqlite3 "$db" "VACUUM INTO '$tmp'"               # consistent copy, safe while backoffice runs
  snap_hash=$(content_hash "$tmp")
  mv "$tmp" "$sync/inventory.db"                   # same filesystem: atomic, Syncthing never sees half a file
  printf '%s %s\n' "$ver" "$snap_hash" >"$sync/.meta.tmp" && mv "$sync/.meta.tmp" "$meta"
  printf '%s %s\n' "$ver" "$(content_hash "$db")" >"$state"
}

pull() {
  local got was_running=false
  got=$(content_hash "$sync/inventory.db")
  [ "$got" = "$remote_hash" ] || exit 0            # snapshot still arriving; try next round
  if [ "$mode" != --before-start ] && systemctl --user is-active --quiet backoffice.service; then
    was_running=true; systemctl --user stop backoffice.service
  fi
  cp "$sync/inventory.db" "$db.incoming" && rm -f "$db-wal" "$db-shm" && mv "$db.incoming" "$db"
  printf '%s %s\n' "$remote_ver" "$(content_hash "$db")" >"$state"
  $was_running && systemctl --user start backoffice.service
  say "Updated inventory from ${remote_ver#*.}."
}

if $remote_new && $local_changed; then
  cp "$sync/inventory.db" "$data/conflicts/inventory-from-${remote_ver#*.}-$(date +%F_%H%M%S).db"
  say "Inventory changed on both machines — kept this one's; ${remote_ver#*.}'s copy is in conflicts/."
  push
elif $remote_new; then
  pull
elif $local_changed && [ -f "$db" ]; then
  push
fi
