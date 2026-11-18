# nix2-prebuild — get the next update ready before you ask for it, so `nixup`
# only has to switch (seconds) instead of compiling while you wait.
#
#   nix2-prebuild            fetch your config's git remote; if there's
#                            something new, build that system now
#   nix2-prebuild --channel  first move to the newest NixOS packages; if this
#                            machine's config doesn't build on them, the
#                            channel goes back so your next rebuild can't break
#
# Timers run it at idle priority and only on mains power: every 6 hours for
# the config, weekly (settings.channelUpdates) for the channel. Nothing is
# switched and /etc/nixos isn't touched: the update is built from a scratch
# copy (plus this machine's own settings.local.nix, hardware-configuration.nix
# and app pins). What it builds stays in the Nix store, kept from garbage
# collection by links in /var/lib/nixos-prebuild — `nixup` finds it there.
dir=${NIXOS_DIR:-/etc/nixos}
state=${STATE_DIRECTORY:-/var/lib/nixos-prebuild}
channel=false
case "${1:-}" in
  "") ;;
  --channel) channel=true ;;
  *) echo "usage: nix2-prebuild [--channel]"; exit 2 ;;
esac
[ "$(id -u)" -eq 0 ] || { echo "nix2-prebuild: run it as root (its timers do)"; exit 1; }
mkdir -p "$state"
cd "$state" || exit 1
# The two timers can meet; one at a time.
exec 9>"$state/.lock"
flock 9

# ── 1. newest NixOS packages (weekly) ──────────────────────────────────────
if $channel; then
  nix-channel --update
  if nixos-rebuild build; then          # leaves ./result: the current config on the new packages
    echo "nix2-prebuild: the newest NixOS packages are built — the next rebuild switches to them in seconds."
  else
    echo "nix2-prebuild: the newest NixOS packages don't build with this config; rolled the channel back."
    nix-channel --rollback
    exit 1
  fi
fi

# ── 2. the newest version of your config ───────────────────────────────────
[ -d "$dir/.git" ] || { echo "nix2-prebuild: $dir isn't a git clone — nothing to fetch."; exit 0; }
# git runs as whoever owns the folder (see nix2-pull): as root in a folder
# you own, git refuses, and fetching would leave root's files in your repo.
asowner=()
owner=$(stat -c %U "$dir")
if [ "$owner" != root ] && [ "$owner" != UNKNOWN ]; then
  asowner=(runuser -u "$owner" --)
fi
g() { "${asowner[@]}" "$(type -P git)" -C "$dir" "$@"; }

up=$(g rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || {
  echo "nix2-prebuild: $dir doesn't follow a remote branch — nothing to fetch."; exit 0; }
g fetch -q 2>/dev/null || { echo "nix2-prebuild: couldn't reach the remote; trying again later."; exit 0; }
rev=$(g rev-parse "$up")
chan=$(readlink -f /nix/var/nix/profiles/per-user/root/channels 2>/dev/null || true)
key="$rev $chan"
if [ "$(cat "$state/next.key" 2>/dev/null)" = "$key" ]; then
  echo "nix2-prebuild: ${rev:0:7} is already built."; exit 0
fi
# Already have everything upstream has: what's running is the update.
if g merge-base --is-ancestor "$rev" HEAD 2>/dev/null; then
  echo "nix2-prebuild: nothing new upstream."
  echo "$key" >"$state/next.key"
  exit 0
fi

echo "nix2-prebuild: building ${rev:0:7} (what nixup will pull) …"
src="$state/src"
rm -rf "$src" "$src.tmp"
mkdir -p "$src.tmp"
if ! g archive "$rev" | tar -x -C "$src.tmp"; then
  rm -rf "$src.tmp"; echo "nix2-prebuild: couldn't copy ${rev:0:7}"; exit 1
fi
# This machine's own files, which aren't in git.
for f in settings.local.nix hardware-configuration.nix pkgs/pins.local.json pkgs/releases.local.json; do
  [ -e "$dir/$f" ] && cp "$dir/$f" "$src.tmp/$f"
done
mv "$src.tmp" "$src"

status=0
nix-build '<nixpkgs/nixos>' -A system -I "nixos-config=$src/configuration.nix" -o "$state/next" || status=$?
rm -rf "$src"
if [ "$status" -ne 0 ]; then
  echo "nix2-prebuild: ${rev:0:7} doesn't build on this machine yet (nixup would stop at the same error, above)."
  exit 1
fi
echo "$key" >"$state/next.key"
echo "nix2-prebuild: ${rev:0:7} is built — nixup will just switch to it."
