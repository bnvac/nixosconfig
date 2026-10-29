# rebuild [switch|boot|test|build …] [--no-update] [extra nixos-rebuild flags]
# nixos-rebuild with a live progress display (nix-output-monitor): what's
# downloading/building, how many are left, and a bar. Not on a terminal
# (scripts, timers) it prints plainly.
#
# Before building it updates everything, so a manual rebuild is also an update:
#   - the NixOS channel, i.e. every regular package   (nix-channel --update)
#   - your own packages: neb, backoffice, intraweb…    (update-mine)
# --no-update skips both, for a quick rebuild after a config change (`mod on|off`
# and modtui's "apply" use it).
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
  sudo update-mine || echo "rebuild: some of your packages kept their old version (see above)"
fi

set -o pipefail
if [ -t 1 ]; then
  sudo nixos-rebuild "$action" --log-format internal-json -v "$@" |& nom --json
else
  sudo nixos-rebuild "$action" "$@"
fi
