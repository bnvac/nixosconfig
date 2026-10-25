# desk — the desktop actions Neb may take (each is its own allowlist entry in
# assistant.nix; typing, key presses and closing windows need your "yes").
# Things Neb opens go on HIS workspace, tag 9, and the view follows them there.
#
#   desk apps | open <app> | web <site> | search <words> | workspace
#   desk windows | focus <title words> | close <title words>
#   desk type <text> | key <combo>      desk volume up|down|mute|<0-100>
#   desk media play|pause|toggle|next|prev   desk brightness up|down
#   desk notify <text> | screenshot | lock

# Neb's server is a user service started before X, so it may lack DISPLAY:
# the dwm session writes it to $XDG_RUNTIME_DIR/x-env at login.
if [ -z "${DISPLAY:-}" ]; then
  envf="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/x-env"
  # shellcheck source=/dev/null
  [ -r "$envf" ] && . "$envf"
fi
export DISPLAY="${DISPLAY:-:0}"

NEB_TAG=9
neb_space() { xdotool key "super+$NEB_TAG"; sleep 0.15; }
run_bg() { setsid -f "$@" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
desk apps | open <app> | web <site> | search <words> | workspace
desk windows | focus <title words> | close <title words>
desk type <text> | key <combo>      desk volume up|down|mute|<0-100>
desk media play|pause|toggle|next|prev   desk brightness up|down
desk notify <text> | screenshot | lock
EOF
}
client_tags() {         # a window's tag bitmask (dwm stores it in _NET_CLIENT_INFO)
  xprop -id "$1" _NET_CLIENT_INFO 2>/dev/null | sed -n 's/.*= \([0-9]*\),.*/\1/p' || true
}
window_id() {           # first window whose title contains the words (case-insensitive)
  [ "$#" -gt 0 ] || return 0
  xdotool search --name "$*" 2>/dev/null | head -1 || true
}
show_window() {         # switch to the window's tag, then point at it (dwm focuses under the mouse)
  local id=$1 info tags n=1
  info=$(client_tags "$id")
  tags=${info:-0}
  if [ "$tags" -gt 0 ]; then
    while [ $((tags & 1)) -eq 0 ]; do tags=$((tags >> 1)); n=$((n + 1)); done
    xdotool key "super+$n"; sleep 0.15
  fi
  xdotool mousemove --window "$id" 40 40
}

cmd=${1:-help}
[ "$#" -gt 0 ] && shift
case "$cmd" in
  apps)
    apps --list | cut -f2 | sort -fu ;;
  open)
    want=$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]')
    [ -n "$want" ] || { echo "open what?"; exit 2; }
    list=$(apps --list)
    line=$(awk -F'\t' -v w="$want" 'tolower($2) == w { print; exit }' <<<"$list")
    [ -n "$line" ] || line=$(awk -F'\t' -v w="$want" 'index(tolower($2), w) { print; exit }' <<<"$list")
    [ -n "$line" ] || { echo "no installed app matches '$*' (try: desk apps)"; exit 1; }
    neb_space; apps --launch "$(cut -f3 <<<"$line")"
    echo "opened $(cut -f2 <<<"$line") on my workspace (tag $NEB_TAG)" ;;
  web)
    url=${1:-}; [ -n "$url" ] || { echo "which site?"; exit 2; }
    case "$url" in http://*|https://*) ;; *) url="https://$url" ;; esac
    neb_space; run_bg firefox --new-window "$url"; echo "opened $url" ;;
  search)
    [ "$#" -gt 0 ] || { echo "search for what?"; exit 2; }
    q=$(printf '%s' "$*" | jq -sRr @uri)
    neb_space; run_bg firefox --new-window "https://duckduckgo.com/?q=$q"; echo "searched for: $*" ;;
  workspace)
    neb_space; echo "switched to my workspace (tag $NEB_TAG)" ;;
  windows)
    for id in $(xprop -root _NET_CLIENT_LIST | grep -o '0x[0-9a-f]*' || true); do
      tags=$(client_tags "$id")
      n=1; t=${tags:-0}
      while [ "$t" -gt 1 ] && [ $((t & 1)) -eq 0 ]; do t=$((t >> 1)); n=$((n + 1)); done
      printf 'tag %s  %s\n' "$n" "$(xdotool getwindowname "$id" 2>/dev/null)"
    done ;;
  focus)
    id=$(window_id "$@"); [ -n "$id" ] || { echo "no window titled like '$*'"; exit 1; }
    show_window "$id"; echo "focused: $(xdotool getwindowname "$id")" ;;
  close)
    id=$(window_id "$@"); [ -n "$id" ] || { echo "no window titled like '$*'"; exit 1; }
    title=$(xdotool getwindowname "$id" || true); show_window "$id"; sleep 0.1
    xdotool key super+q; echo "closed: $title" ;;
  type)
    xdotool type --delay 15 -- "$*"; echo "typed it" ;;
  key)
    xdotool key -- "${1:?which key?}"; echo "pressed $1" ;;
  volume)
    case "${1:-}" in
      up)    wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ ;;
      down)  wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
      mute)  wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
      [0-9]*) wpctl set-volume @DEFAULT_AUDIO_SINK@ "$(( ${1%%[!0-9]*} > 150 ? 150 : ${1%%[!0-9]*} ))%" ;;
      *)     echo "volume up|down|mute|<0-100>"; exit 2 ;;
    esac
    pkill -RTMIN+10 dwmblocks 2>/dev/null || true
    wpctl get-volume @DEFAULT_AUDIO_SINK@ ;;
  media)
    case "${1:-toggle}" in
      play) a=play ;; pause) a=pause ;; toggle) a=play-pause ;; next) a=next ;; prev|previous) a=previous ;;
      *) echo "media play|pause|toggle|next|prev"; exit 2 ;;
    esac
    playerctl "$a" && echo "media: $a" ;;
  brightness)
    case "${1:-}" in up) brightnessctl -q set 10%+ ;; down) brightnessctl -q set 10%- ;; *) echo "brightness up|down"; exit 2 ;; esac
    echo "brightness $(brightnessctl -m | cut -d, -f4)" ;;
  notify)
    notify-send -a Neb Neb "$*"; echo "shown" ;;
  screenshot)
    f="$HOME/Pictures/screenshots/neb-$(date +%F_%H%M%S).png"; mkdir -p "${f%/*}"
    maim "$f" && echo "$f" ;;
  lock)
    run_bg lock; echo "locked" ;;
  *)
    usage ;;
esac
