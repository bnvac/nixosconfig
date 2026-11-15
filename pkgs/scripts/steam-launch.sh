# steam — starts Steam, and gets it going again when it crashes while
# starting. (This replaces the plain `steam` command, so the app menu, the
# nixmenu entry and a terminal all go through it.)
#
# The crash: Steam's window helper (steamwebhelper) dies a few seconds in,
# the log fills with "CCrossProcessPipe … Broken pipe", and Steam quits. On
# NixOS this is a known problem with no fix upstream yet; what gets it going
# is restarting the sound server (PipeWire) — NixOS issues #324875/#521087 —
# and, failing that, clearing the helper's cache or drawing Steam's own
# window without the GPU. So when Steam dies within 90 seconds of starting:
#   1st retry: stop what's left of Steam, restart PipeWire, clear the helper's
#              web cache (only a cache: your login and games are untouched)
#   2nd retry: also draw Steam's window without the GPU (games still use
#              it) — and remember that, since it's what worked
#
#   steam-fix          stop Steam, do all of the above, start it again
#   steam-fix --gpu    draw Steam's window with the GPU again
# Each start is logged to ~/.local/state/nix2/steam-start.log.
real=${NIX2_REAL_STEAM:?}
state="${XDG_STATE_HOME:-$HOME/.local/state}/nix2"
mkdir -p "$state"
log="$state/steam-start.log"
cpu_ui="$state/steam-cpu-ui"            # exists = draw Steam's window without the GPU
uid=$(id -u)

say() {
  echo "steam: $1" >&2
  notify-send -a Steam -i steam "Steam" "$1" 2>/dev/null || true
}
running() { pgrep -u "$uid" -x steamwebhelper >/dev/null 2>&1; }

stop_steam() {
  pkill -u "$uid" -f '/Steam/ubuntu12_(32|64)/' 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -u "$uid" -f '/Steam/ubuntu12_(32|64)/' >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  pkill -KILL -u "$uid" -f '/Steam/ubuntu12_(32|64)/' 2>/dev/null || true
}

fix_up() {
  stop_steam
  systemctl --user restart pipewire.socket pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null \
    || systemctl --user restart pipewire 2>/dev/null || true
  for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
    rm -rf "$root/config/htmlcache" "$root/appcache/httpcache" 2>/dev/null || true
  done
  sleep 1
}

extra=()
use_cpu_ui() { extra=(-cef-disable-gpu -cef-disable-gpu-compositing); }
[ -e "$cpu_ui" ] && use_cpu_ui

case "${1:-}" in
  --nix2-fix)
    shift
    echo "Stopping Steam, restarting the sound server, clearing Steam's web cache…"
    fix_up ;;
  --nix2-gpu)
    rm -f "$cpu_ui"
    echo "Steam will draw its window with the GPU again. Starting it…"
    shift; extra=() ;;
esac

# Steam already open: it takes the request (a game link, -silent…) itself.
if running; then exec "$real" "$@"; fi

# One start. Returns 0 unless Steam died while starting.
attempt() {
  local start rc=0
  printf '\n=== %s  steam %s\n' "$(date '+%F %T')" "${extra[*]} $*" >>"$log"
  start=$(date +%s)
  "$real" "${extra[@]}" "$@" > >(tee -a "$log") 2>&1 || rc=$?
  sleep 1
  if [ $(( $(date +%s) - start )) -lt 90 ] && ! running \
     && tail -n 400 "$log" | grep -qE 'CCrossProcessPipe|Segmentation fault|steamwebhelper.*(crash|not responding)|Assertion Failed'; then
    return 1
  fi
  return "$rc"
}

attempt "$@" && exit 0
running && exit 0
say "Steam crashed while starting — fixing the usual cause (the sound server) and trying again…"
fix_up
attempt "$@" && exit 0
running && exit 0
if [ "${#extra[@]}" -eq 0 ]; then
  say "Still crashing — trying once more with Steam's window drawn without the GPU (games still use it)…"
  stop_steam
  use_cpu_ui
  if attempt "$@" || running; then
    touch "$cpu_ui"
    say "That worked, so Steam will keep starting that way. Games aren't affected. To try the GPU again: steam-fix --gpu"
    exit 0
  fi
fi
say "Steam still won't start. What it said is in ~/.local/state/nix2/steam-start.log — or run steam in a terminal to watch."
exit 1
