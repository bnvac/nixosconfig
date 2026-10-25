# rebuild [switch|boot|test|build …] [extra nixos-rebuild flags]
# nixos-rebuild with a live progress display (nix-output-monitor): what's
# downloading/building, how many are left, and a bar. Used by mod, modtui and
# nixup. Not on a terminal (scripts, the auto-update timer) it prints plainly.
action=${1:-switch}
[ "$#" -gt 0 ] && shift
set -o pipefail
if [ -t 1 ]; then
  sudo nixos-rebuild "$action" --log-format internal-json -v "$@" |& nom --json
else
  sudo nixos-rebuild "$action" "$@"
fi
