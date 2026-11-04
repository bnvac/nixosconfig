# rebuild [switch|boot|test|build …] [--upgrade] [--no-update] [extra nixos-rebuild flags]
# nixos-rebuild with a live progress display (nix-output-monitor). Not on a
# terminal (scripts, timers) it prints plainly.
#
# Kept fast on purpose:
#   rebuild              your config + your own git apps (update-mine — a few
#                        seconds when nothing's new). Stays on the NixOS
#                        package set you have, so nothing else rebuilds.
#   rebuild --upgrade    also move to the newest NixOS packages (the channel).
#                        Rarely needed by hand: a weekly background job
#                        downloads and pre-builds the new set at idle priority,
#                        so the next plain `rebuild` switches to it in seconds.
#   rebuild --no-update  just apply config changes (mod on/off uses this)
# After switching, services that a module just added are started right away.
dir=${NIXOS_DIR:-/etc/nixos}
mine=true; channel=false
args=()
for a in "$@"; do
  case "$a" in
    --no-update) mine=false ;;
    --upgrade) channel=true ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]}"
action=${1:-switch}
[ "$#" -gt 0 ] && shift

if $channel; then
  echo ":: updating the NixOS channel …"
  sudo nix-channel --update || echo "rebuild: channel update failed — building with the current one"
fi
if $mine; then
  echo ":: checking your git apps …"
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
