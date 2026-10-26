# snow [on|off|toggle] — the live falling snow over the wallpaper (xsnow).
# It snows *behind* your windows (dwm keeps its window at the very bottom and
# never tiles it), so it shows on empty space only. Just flakes: no Santa,
# trees, moon, stars, aurora or birds. On at login unless settings.nix has
# liveSnow = false.
# (Match the command line, not the process name: Nix wraps the binary, so the
# process is really called .xsnow-wrapped.)
pattern='(^|/)xsnow( |$)'
running() { pgrep -f "$pattern" >/dev/null; }
start() {
  running && return 0
  setsid -f xsnow -nomenu -noconfig -nosanta -notrees -nometeors -moon 0 -stars 0 -aurora 0 \
    -showbirds 0 -nowind -snowflakes 70 -snowsize 7 -nokeepsnowonwindows >/dev/null 2>&1
}
stop() {                      # xsnow can ignore SIGTERM; give it 2 s, then make sure
  pkill -f "$pattern" || return 0
  for _ in 1 2 3 4 5 6 7 8 9 10; do running || return 0; sleep 0.2; done
  pkill -KILL -f "$pattern" || true
}
case "${1:-toggle}" in
  on)     start ;;
  off)    stop ;;
  toggle) if running; then stop; else start; fi ;;
  *)      echo "usage: snow [on|off|toggle]"; exit 2 ;;
esac
