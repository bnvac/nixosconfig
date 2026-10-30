# rebuild [switch|boot|test|build …] [--no-update] [extra nixos-rebuild flags]
# nixos-rebuild with a live progress display (nix-output-monitor): what's
# downloading/building, how many are left, and a bar. Not on a terminal
# (scripts, timers) it prints plainly.
#
# Before building it updates everything, so a manual rebuild is also an update:
#   - the NixOS channel, i.e. every regular package   (nix-channel --update)
#   - your own packages / git apps                     (update-mine)
# --no-update skips both, for a quick rebuild after a config change (`mod on|off`
# and modtui's "apply" use it). After switching, services that a module just
# added are started right away instead of at your next login.
dir=${NIXOS_DIR:-/etc/nixos}
update=true
args=()
for a in "$@"; do
  case "$a" in
    --no-update) update=false ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]}"
action=${1:-switch}
[ "$#" -gt 0 ] && shift

if $update; then
  echo ":: updating the NixOS channel …"
  sudo nix-channel --update || echo "rebuild: channel update failed — building with the current one"
  echo ":: updating your packages …"
  # Always the repo's copy, so a freshly pulled updater is the one that runs.
  if [ -r "$dir/pkgs/scripts/update-mine.sh" ]; then
    sudo env "PATH=$PATH" bash "$dir/pkgs/scripts/update-mine.sh" \
      || echo "rebuild: some of your packages kept their old version (see above)"
  fi
fi

build() {
  set -o pipefail
  if [ -t 1 ] && command -v nom >/dev/null; then
    sudo nixos-rebuild "$action" --log-format internal-json -v "$@" |& nom --json
  else
    sudo nixos-rebuild "$action" "$@"
  fi
}
status=0
build "$@" || status=$?

# Bring up user services that modules added (intraweb, printer alerts, …).
if [ "$status" -eq 0 ] && [ "$action" = switch ] && [ "$(id -u)" -ne 0 ]; then
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user start default.target 2>/dev/null || true
  if [ -n "${DISPLAY:-}" ]; then systemctl --user start graphical-session.target 2>/dev/null || true; fi
fi
exit "$status"
