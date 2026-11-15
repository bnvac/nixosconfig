# wifi — pick a Wi-Fi network from a menu (Super+Alt+y, or menu → System).
# Networks you've used before connect straight away; a new one asks for its
# password (hidden as you type). Also: Wi-Fi off/on, forget a network, join a
# hidden one. NetworkManager does the work, so `nmtui` and the network icon
# see the same networks.
#
#   wifi           the menu
#   wifi off|on    turn Wi-Fi off / on
say() {
  echo "wifi: $1"
  notify-send -a Wi-Fi -i network-wireless "Wi-Fi" "$1" 2>/dev/null || true
}

case "${1:-}" in
  on | off) if nmcli radio wifi "$1"; then say "Wi-Fi $1."; fi; exit ;;
  "") ;;
  *) echo "usage: wifi [on|off]"; exit 2 ;;
esac

if [ "$(nmcli radio wifi)" != enabled ]; then
  printf '%s\n' "Turn Wi-Fi on" | dmenu -i -p "Wi-Fi is off:" >/dev/null || exit 0
  if nmcli radio wifi on; then say "Wi-Fi on — looking for networks…"; fi
  sleep 3
fi

# One line per network: in-use, signal, security, ssid (separated by \037), strongest
# first, each name once. SSID goes last because it may itself contain ":".
networks=$(nmcli --get-values IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan auto 2>/dev/null \
  | awk -F: '{ ssid = $4; for (i = 5; i <= NF; i++) ssid = ssid ":" $i
               gsub(/\\:/, ":", ssid)
               if (ssid != "") print $1 "\037" $2 "\037" $3 "\037" ssid }' \
  | sort -t$'\037' -k1,1r -k2,2nr | awk -F'\037' '!seen[$4]++')
known=$(nmcli --get-values NAME,TYPE connection show 2>/dev/null | awk -F: '$NF == "802-11-wireless" { sub(/:[^:]*$/, ""); print }')

bars() { if [ "$1" -ge 75 ]; then echo "▂▄▆█"; elif [ "$1" -ge 50 ]; then echo "▂▄▆_"; elif [ "$1" -ge 25 ]; then echo "▂▄__"; else echo "▂___"; fi; }
rows=()
while IFS=$'\037' read -r use signal sec ssid; do
  [ -n "$ssid" ] || continue
  mark="  "; [ "$use" = "*" ] && mark="● "
  lock=""; [ -n "$sec" ] && [ "$sec" != "--" ] && lock=" 🔒"
  saved=""; printf '%s\n' "$known" | grep -qxF "$ssid" && saved="  (saved)"
  rows+=("$mark$(bars "${signal:-0}")  $ssid$lock$saved")
done <<<"$networks"
rows+=("Join a hidden network…" "Forget a saved network…" "Turn Wi-Fi off")

pick=$(printf '%s\n' "${rows[@]}" | dmenu -i -l 15 -p "Wi-Fi:") || exit 0
case "$pick" in
  "Turn Wi-Fi off") if nmcli radio wifi off; then say "Wi-Fi off."; fi; exit ;;
  "Forget a saved network…")
    [ -n "$known" ] || { say "No saved Wi-Fi networks."; exit 0; }
    gone=$(printf '%s\n' "$known" | dmenu -i -l 15 -p "Forget which network?") || exit 0
    if nmcli connection delete id "$gone" >/dev/null; then say "Forgot $gone."; fi
    exit ;;
  "Join a hidden network…")
    ssid=$(printf '' | dmenu -p "Network name:") || exit 0
    [ -n "$ssid" ] || exit 0
    pw=$(printf '' | dmenu -P -p "Password for $ssid (empty if none):") || exit 0
    ok=0
    if [ -n "$pw" ]; then out=$(nmcli device wifi connect "$ssid" password "$pw" hidden yes 2>&1) && ok=1
    else out=$(nmcli device wifi connect "$ssid" hidden yes 2>&1) && ok=1; fi
    unset pw
    if [ "$ok" = 1 ]; then say "Connected to $ssid."; else say "Couldn't join $ssid: ${out#Error: }"; fi
    exit ;;
esac

# Back from the row to the network: strip the marker, the bars, the lock and "(saved)".
ssid=$(printf '%s' "$pick" | sed -E 's/^(● |  )[▂▄▆█_]+  //; s/  \(saved\)$//; s/ 🔒$//')
line=$(printf '%s\n' "$networks" | awk -F'\037' -v s="$ssid" '$4 == s { print; exit }')
[ -n "$line" ] || exit 0
sec=$(printf '%s' "$line" | cut -d$'\037' -f3)
[ "$(printf '%s' "$line" | cut -d$'\037' -f1)" = "*" ] && { say "Already connected to $ssid."; exit 0; }

if printf '%s\n' "$known" | grep -qxF "$ssid"; then
  say "Connecting to $ssid…"
  if out=$(nmcli connection up id "$ssid" 2>&1); then say "Connected to $ssid."; exit 0; fi
  # Saved, but it didn't take (the password changed?): ask again below.
  echo "$out" >&2
fi
if [ -n "$sec" ] && [ "$sec" != "--" ]; then
  pw=$(printf '' | dmenu -P -p "Password for $ssid:") || exit 0
  [ -n "$pw" ] || exit 0
  say "Connecting to $ssid…"
  if out=$(nmcli device wifi connect "$ssid" password "$pw" 2>&1); then unset pw; say "Connected to $ssid."
  else
    unset pw
    case "$out" in
      *[Ss]ecrets* | *[Pp]assword* | *802-1[Xx]* | *"wrong"*) say "Couldn't connect to $ssid — wrong password?" ;;
      *) say "Couldn't connect to $ssid: ${out#Error: }" ;;
    esac
    # Don't keep a half-made connection with the wrong password.
    printf '%s\n' "$known" | grep -qxF "$ssid" || nmcli connection delete id "$ssid" >/dev/null 2>&1 || true
    exit 1
  fi
else
  say "Connecting to $ssid (open network)…"
  if out=$(nmcli device wifi connect "$ssid" 2>&1); then say "Connected to $ssid."; else say "Couldn't connect to $ssid: ${out#Error: }"; fi
fi
