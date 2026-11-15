# offtimer — turn the computer off (or suspend / restart) later.
# (Super+Alt+o, or menu → System → Shutdown timer.)
#
#   offtimer                 the menu: pick a time, or cancel the one that's set
#   offtimer 30              off in 30 minutes   (also 45m, 1h, 1h30, 90s)
#   offtimer 23:30           off at 23:30 (tomorrow if that's already past)
#   offtimer suspend 1h      suspend instead (or: reboot 10m)
#   offtimer status          what's set
#   offtimer cancel          cancel it
#
# 5 minutes and 1 minute before, a notification warns you (with how to
# cancel). It's a systemd timer, so it keeps running when you close the
# menu or the terminal; it does not survive a reboot or a log out.
unit=nix2-offtimer

note() {
  echo "offtimer: $1"
  notify-send -a "Shutdown timer" -i system-shutdown "${2:-Shutdown timer}" "$1" 2>/dev/null || true
}

# The time it fires, as "HH:MM" (empty when nothing's set).
when() {
  local us
  us=$(systemctl --user show "$unit.timer" -p NextElapseUSecRealtime --value 2>/dev/null) || return 0
  case "$us" in "" | 0 | n/a) return 0 ;; esac
  # systemd gives a date string ("Sun 2026-11-15 23:30:00 EST") or µs
  if [[ $us =~ ^[0-9]+$ ]]; then date -d "@$(( us / 1000000 ))" '+%H:%M'
  else date -d "$us" '+%H:%M' 2>/dev/null || echo "$us"; fi
}
what() { systemctl --user show "$unit.service" -p Description --value 2>/dev/null | sed -n 's/^Shutdown timer: //p'; }

cancel() {
  local had
  had=$(when)
  for u in "$unit" "$unit-warn5" "$unit-warn1"; do
    systemctl --user stop "$u.timer" 2>/dev/null || true
    systemctl --user reset-failed "$u.service" "$u.timer" 2>/dev/null || true
  done
  if [ -n "$had" ]; then note "Cancelled — nothing will happen at $had."; else echo "offtimer: nothing was set."; fi
}

# "30" "30m" "1h" "1h30" "90s" → seconds;  "23:30" → "clock 23:30"
parse() {
  local c
  c=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  if [[ $c =~ ^([0-9]{1,2}):([0-9]{2})$ ]] && [ "$((10#${BASH_REMATCH[1]}))" -lt 24 ] && [ "$((10#${BASH_REMATCH[2]}))" -lt 60 ]; then
    echo "clock $(printf '%02d:%02d' "$((10#${BASH_REMATCH[1]}))" "$((10#${BASH_REMATCH[2]}))")"
  elif [[ $c =~ ^([0-9]+)(h|hr|hrs|hour|hours)([0-9]+)?(m|min|mins|minutes?)?$ ]]; then
    echo $(( (10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[3]:-0}) * 60 ))
  elif [[ $c =~ ^([0-9]+)(s|sec|secs|seconds?)$ ]]; then
    echo $(( 10#${BASH_REMATCH[1]} ))
  elif [[ $c =~ ^([0-9]+)(m|min|mins|minutes?)?$ ]]; then
    echo $(( 10#${BASH_REMATCH[1]} * 60 ))
  else
    return 1
  fi
}

# set ACTION WHEN  (action: poweroff | suspend | reboot)
set_timer() {
  local action=$1 at secs fire word
  at=$(parse "$2") || { note "Didn't understand \"$2\" — try 30, 1h, 1h30 or 23:30."; return 1; }
  if [[ $at == clock* ]]; then
    local hm=${at#clock } now target
    now=$(date +%s)
    target=$(date -d "today $hm" +%s)
    [ "$target" -le "$now" ] && target=$(date -d "tomorrow $hm" +%s)
    secs=$(( target - now ))
  else
    secs=$at
  fi
  [ "$secs" -ge 1 ] || { note "That's not in the future."; return 1; }
  [ "$secs" -le $(( 3 * 86400 )) ] || { note "That's more than 3 days away — pick something sooner."; return 1; }

  cancel >/dev/null
  case "$action" in
    poweroff) word="turn off" ;;
    suspend)  word="suspend" ;;
    reboot)   word="restart" ;;
  esac
  # --check-inhibitors=no: a timer means it, even with Steam or a download open
  systemd-run --user --quiet --unit="$unit" --description="Shutdown timer: $word" \
    --on-active="${secs}s" --timer-property=AccuracySec=1s \
    systemctl "$action" --check-inhibitors=no || { note "Couldn't set the timer (systemd-run failed)."; return 1; }
  local warned=()
  for w in 5 1; do
    if [ "$secs" -gt $(( w * 60 + 30 )) ]; then
      warned+=("$w")
      systemd-run --user --quiet --unit="$unit-warn$w" --description="Shutdown timer warning" \
        --on-active="$(( secs - w * 60 ))s" --timer-property=AccuracySec=1s \
        notify-send -a "Shutdown timer" -u critical -i system-shutdown \
          "This computer will $word in $w minute$([ "$w" -gt 1 ] && echo s)" \
          "Save your work. To stop it: Super+Alt+o → Cancel, or run: offtimer cancel" || true
    fi
  done
  fire=$(date -d "@$(( $(date +%s) + secs ))" '+%H:%M')
  case "${warned[*]}" in
    "5 1") note "This computer will $word at $fire. You'll get a warning 5 minutes and 1 minute before." ;;
    1) note "This computer will $word at $fire. You'll get a warning 1 minute before." ;;
    *) note "This computer will $word at $fire (in under 2 minutes — no warning). To stop it: offtimer cancel" ;;
  esac
}

menu() {
  local now act choice opts word
  now=$(when)
  opts=("15 minutes" "30 minutes" "45 minutes" "1 hour" "1½ hours" "2 hours" "3 hours"
        "At a time… (type it, e.g. 23:30)" "Suspend instead…" "Restart instead…")
  if [ -n "$now" ]; then
    opts=("Cancel ($(what) at $now)" "${opts[@]}")
    prompt="Set for $now ($(what)). Change it to:"
  else
    prompt="Turn this computer off in:"
  fi
  choice=$(printf '%s\n' "${opts[@]}" | dmenu -i -l 12 -p "$prompt") || return 0
  act=poweroff
  case "$choice" in
    Cancel*) cancel; return ;;
    Suspend*) act=suspend ;;
    Restart*) act=reboot ;;
  esac
  case "$choice" in
    Suspend* | Restart*)
      word=$([ "$act" = suspend ] && echo Suspend || echo Restart)
      choice=$(printf '%s\n' "15 minutes" "30 minutes" "1 hour" "2 hours" | dmenu -i -l 6 -p "$word in (or a time like 23:30):") || return 0 ;;
    At*)
      choice=$(printf '' | dmenu -p "Turn off at (like 23:30), or in (like 40 or 1h20):") || return 0 ;;
  esac
  case "$choice" in
    "1½ hours") choice=90m ;;
    *" minutes") choice=${choice% minutes}m ;;
    *" hour" | *" hours") choice=${choice%% *}h ;;
  esac
  set_timer "$act" "$choice"
}

case "${1:-}" in
  "") menu ;;
  status)
    t=$(when)
    if [ -n "$t" ]; then echo "Set: $(what) at $t."; else echo "No shutdown timer set."; fi ;;
  cancel | off | stop) cancel ;;
  suspend | reboot | restart | poweroff | shutdown)
    a=$1; [ "$a" = restart ] && a=reboot; [ "$a" = shutdown ] && a=poweroff
    [ -n "${2:-}" ] || { echo "usage: offtimer $1 TIME   (30, 1h, 23:30…)"; exit 2; }
    set_timer "$a" "$2" ;;
  -h | --help | help)
    awk '/^# offtimer —/ { f = 1 } f && /^#/ { sub(/^# ?/, ""); print; next } f { exit }' "$0" ;;
  *) set_timer poweroff "$1" ;;
esac
