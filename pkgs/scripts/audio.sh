# audio — a quick dmenu audio manager (Super+Alt+v).
# Pick where sound goes (speakers / headphones / Bluetooth / HDMI) and which
# mic is used, nudge volume, mute. Volume steps reopen the menu so you can tap
# Enter repeatedly. "Full mixer" opens pavucontrol for per-app volumes.
#   audio            the menu
#   audio up|down|mute   one-shot volume change (no menu)

sig() { pkill -RTMIN+10 dwmblocks 2>/dev/null || true; }      # refresh the bar's volume
vol() {
  local v m
  v=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oE '[0-9]+%' | head -n 1)
  m=$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}')
  [ "$m" = yes ] && echo "muted" || echo "${v:-?}"
}

# pick KIND (sink|source): choose a device, make it the default, move what's playing/recording.
pick() {
  local kind=$1 cur list sel label name
  cur=$(pactl "get-default-$kind")
  list=$(pactl -f json list "${kind}s" | jq -r --arg cur "$cur" '
    .[] | select(.name | test("\\.monitor$") | not)
    | (if .name == $cur then "● " else "  " end) + .description + "\t" + .name')
  [ -n "$list" ] || { notify-send -a Audio "Audio" "No ${kind/sink/output}s found"; return; }
  sel=$(cut -f1 <<<"$list" | dmenu -i -l 15 -p "${kind/sink/Output}:" ) || return 0
  label=$(sed 's/^● //; s/^ *//; s/ *$//' <<<"$sel")
  name=$(awk -F'\t' -v s="$label" '{ d = $1; sub(/^● /, "", d); gsub(/^ +| +$/, "", d) } d == s { print $2; exit }' <<<"$list")
  [ -n "$name" ] || return 0
  pactl "set-default-$kind" "$name"
  local streams; [ "$kind" = sink ] && streams=sink-inputs || streams=source-outputs
  pactl list short "$streams" | cut -f1 | while read -r id; do
    pactl "move-${streams%s}" "$id" "$name" 2>/dev/null || true
  done
  notify-send -a Audio -i audio-card "Audio" "${kind/sink/Output}: $label"
  sig
}

case "${1:-}" in
  up)   pactl set-sink-volume @DEFAULT_SINK@ +5%; sig; exit 0 ;;
  down) pactl set-sink-volume @DEFAULT_SINK@ -5%; sig; exit 0 ;;
  mute) pactl set-sink-mute @DEFAULT_SINK@ toggle; sig; exit 0 ;;
esac

while :; do
  sel=$(printf '%s\n' "Output device…" "Input (mic)…" "Volume +5%" "Volume -5%" \
          "Mute / unmute" "Mic mute / unmute" "Full mixer (per-app)" \
        | dmenu -i -l 10 -p "Audio [$(vol)]:") || exit 0
  case "$sel" in
    Output*)     pick sink; exit 0 ;;
    Input*)      pick source; exit 0 ;;
    "Volume +"*) pactl set-sink-volume @DEFAULT_SINK@ +5%; sig ;;      # stay open
    "Volume -"*) pactl set-sink-volume @DEFAULT_SINK@ -5%; sig ;;
    Mute*)       pactl set-sink-mute @DEFAULT_SINK@ toggle; sig ;;
    Mic*)        pactl set-source-mute @DEFAULT_SOURCE@ toggle
                 notify-send -a Audio "Audio" "Mic: $(pactl get-source-mute @DEFAULT_SOURCE@ | awk '{print $2}' | sed 's/yes/muted/;s/no/live/')"
                 exit 0 ;;
    Full*)       setsid -f pavucontrol >/dev/null 2>&1; exit 0 ;;
    *)           exit 0 ;;
  esac
done
