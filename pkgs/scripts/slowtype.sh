# slowtype — SlowTyper from the menu, asking how long the typing should take.
#
#   slowtype            type what's on the clipboard
#   slowtype paste      paste the text into a terminal first
#
# The menu offers common durations; you can also type any number of minutes
# (7, 2.5), a speed (60wpm), or a time like 1h30 / 90s. Then a terminal
# counts down 8 seconds so you can click where the text should go. While it
# types: F8 pauses, F9 stops.
mode=${1:-clipboard}
text=""
cleanup() { [ -z "$text" ] || rm -f "$text"; }
trap cleanup EXIT

if [ "$mode" = clipboard ]; then
  text=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/slowtype.XXXXXX")
  xclip -selection clipboard -o > "$text" 2>/dev/null || true
  if ! grep -q '[^[:space:]]' "$text"; then
    notify-send "SlowTyper" "The clipboard is empty: copy the text you want typed first."
    exit 0
  fi
  words=$(wc -w < "$text")
  normal=$(awk -v w="$words" 'BEGIN { m = w / 45; printf (m < 1 ? "%.1f" : "%.0f"), m }')
  prompt="Type $words words in how long?"
  first="normal speed (45 WPM, about $normal min)"
else
  prompt="Type it in how long?"
  first="normal speed (45 WPM)"
fi

choice=$(printf '%s\n' "$first" "1 min" "2 min" "5 min" "10 min" "15 min" "20 min" "30 min" "45 min" "1 hour" "2 hours" \
  | dmenu -i -l 11 -p "$prompt (or type: 7, 1h30, 60wpm)") || exit 0

# What you picked or typed → slowtyper's --minutes or --wpm.
c=$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
num='([0-9]+\.?[0-9]*|\.[0-9]+)'
speed=()
if [[ $c == normalspeed* ]]; then speed=(--wpm 45)
elif [[ $c =~ ^${num}wpm$ ]]; then speed=(--wpm "${BASH_REMATCH[1]}")
elif [[ $c =~ ^${num}(h|hr|hrs|hour|hours)(${num}(m|min|mins|minutes?)?)?$ ]]; then
  speed=(--minutes "$(awk -v h="${BASH_REMATCH[1]}" -v m="${BASH_REMATCH[4]:-0}" 'BEGIN { print h * 60 + m }')")
elif [[ $c =~ ^([0-9]+):([0-9]{1,2})$ ]]; then                  # 1:30 = h:mm
  speed=(--minutes "$(( 10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]} ))")
elif [[ $c =~ ^${num}(s|sec|secs|seconds?)$ ]]; then
  speed=(--minutes "$(awk -v s="${BASH_REMATCH[1]}" 'BEGIN { print s / 60 }')")
elif [[ $c =~ ^${num}(m|min|mins|minutes?)?$ ]]; then speed=(--minutes "${BASH_REMATCH[1]}")
fi
if [ "${#speed[@]}" -eq 0 ] || awk -v v="${speed[1]}" 'BEGIN { exit !(v <= 0) }'; then
  notify-send "SlowTyper" "Didn't understand \"$choice\". Pick one from the list, or type minutes (7), a time (1h30) or a speed (60wpm)."
  exit 0
fi

# The terminal does the typing; it deletes the copied text when it's done.
if [ "$mode" = clipboard ]; then
  # shellcheck disable=SC2016  # expanded by the inner sh, not here
  exec "${TERMINAL:-st}" -e sh -c 'f=$1; shift; slowtyper -y -d 8 -f "$f" "$@"; rm -f "$f"; printf "\n[enter] "; read -r _' \
    sh "$text" "${speed[@]}"
else
  # shellcheck disable=SC2016
  exec "${TERMINAL:-st}" -e sh -c 'slowtyper -d 8 "$@"; printf "\n[enter] "; read -r _' sh "${speed[@]}"
fi
