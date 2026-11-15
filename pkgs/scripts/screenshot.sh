# screenshot — Print = whole screen, Shift+Print (or Super+Alt+S) = this menu.
#   screenshot [menu|full|area|window|copy-area|copy-window|text]
#   screenshot record | record-area | record-stop      screen recording (video)
# Saves to ~/Pictures/screenshots/<date>_<time>.png (always an absolute
# path, so it works no matter which folder your session started in) and puts
# the picture on the clipboard too. A notification shows the shot — or says
# what went wrong, instead of failing silently.

dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/screenshots"
mode=${1:-menu}
recpid="${XDG_RUNTIME_DIR:-/tmp}/screen-recording.pid"
recfile="${XDG_RUNTIME_DIR:-/tmp}/screen-recording.file"
# Running = the process exists and isn't a zombie (a recorder that failed
# straight away stays around as one until this script exits).
alive() { [ -r "/proc/$1/stat" ] && [ "$(sed 's/.*) //' "/proc/$1/stat" | cut -d' ' -f1)" != Z ]; }
recording() { [ -s "$recpid" ] && alive "$(cat "$recpid")"; }

fail() {
  notify-send -u critical -a Screenshot "Screenshot failed" "$1" 2>/dev/null || true
  echo "screenshot: $1" >&2
  exit 1
}

if [ "$mode" = menu ]; then
  # One menu at a time: holding the keys makes key-repeat start this again
  # and again, and the extra menus would fight over the keyboard.
  exec 9>"${XDG_RUNTIME_DIR:-/tmp}/screenshot-menu.lock"
  flock -n 9 || exit 0
  err=$(mktemp)
  status=0
  items=("Area" "Window" "Full screen" "Area → clipboard only" "Window → clipboard only"
         "Text from an area → clipboard (OCR)" "Record the screen (video, with sound)"
         "Record an area (video, with sound)")
  recording && items=("■ Stop recording" "${items[@]}")
  choice=$(printf '%s\n' "${items[@]}" | dmenu -i -l 9 -p "Screenshot:" 2>"$err") || status=$?
  if [ "$status" -ne 0 ]; then
    if grep -q 'cannot grab keyboard' "$err"; then
      rm -f "$err"
      fail "couldn't open the menu: another program had the keyboard. Try again, or press Super+Alt+S."
    fi
    rm -f "$err"; exit 0                       # Escape: you closed the menu
  fi
  rm -f "$err"
  exec 9>&-         # menu's done: let go of the lock (xclip, below, lives on)
  case "$choice" in
    Area) mode=area ;;
    Window) mode=window ;;
    "Full screen") mode=full ;;
    "Area →"*) mode=copy-area ;;
    "Window →"*) mode=copy-window ;;
    Text*) mode=text ;;
    "■ Stop"*) mode=record-stop ;;
    "Record the screen"*) mode=record ;;
    "Record an area"*) mode=record-area ;;
    *) exit 0 ;;
  esac
fi

# ── screen recording (video): ~/Videos/recordings/<date>.mp4 ───────────────
# With the sound the computer is playing (not the mic). Stops from the same
# menu (Shift+Print → Stop recording) or with: screenshot record-stop
case "$mode" in
  record | record-area)
    if recording; then
      notify-send -a Screenshot "Already recording" "Stop it first: Shift+Print → Stop recording" 2>/dev/null || true
      exit 0
    fi
    if [ "$mode" = record-area ]; then
      geo=$(slop -f '%w %h %x %y' 2>/dev/null) || exit 0          # Esc: cancelled
    else
      geo=$(xwininfo -root | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w, h, 0, 0}')
    fi
    read -r w h x y <<<"$geo"
    w=$(( w / 2 * 2 )); h=$(( h / 2 * 2 ))                    # the video encoder wants even sizes
    [ "$w" -ge 16 ] && [ "$h" -ge 16 ] || fail "that area is too small to record"
    vdir="${XDG_VIDEOS_DIR:-$HOME/Videos}/recordings"
    mkdir -p "$vdir" || fail "can't create $vdir"
    out="$vdir/$(date '+%Y-%m-%d_%H-%M-%S').mp4"
    audio=()
    if sink=$(pactl get-default-sink 2>/dev/null) && [ -n "$sink" ]; then
      audio=(-f pulse -i "$sink.monitor" -c:a aac -b:a 160k)
    fi
    setsid ffmpeg -nostdin -y -loglevel error -f x11grab -framerate 30 -video_size "${w}x${h}" \
      -i "${DISPLAY:-:0}+$x,$y" "${audio[@]}" -c:v libx264 -preset veryfast -crf 23 \
      -pix_fmt yuv420p "$out" >/dev/null 2>"${XDG_RUNTIME_DIR:-/tmp}/screen-recording.log" &
    echo $! >"$recpid"; echo "$out" >"$recfile"
    sleep 1
    recording || fail "the recording didn't start: $(head -c 200 "${XDG_RUNTIME_DIR:-/tmp}/screen-recording.log")"
    notify-send -a Screenshot -i media-record "Recording" \
      "Stop with Shift+Print → Stop recording$([ "${#audio[@]}" -gt 0 ] || echo ' (no sound: the sound server isn'"'"'t answering)')" 2>/dev/null || true
    exit 0 ;;
  record-stop)
    recording || { notify-send -a Screenshot "Not recording" 2>/dev/null || true; exit 0; }
    pid=$(cat "$recpid"); out=$(cat "$recfile" 2>/dev/null || true)
    kill -INT "$pid" 2>/dev/null || true                # ffmpeg finishes the file properly on Ctrl+C
    for _ in $(seq 1 50); do alive "$pid" || break; sleep 0.2; done
    if alive "$pid"; then kill "$pid" 2>/dev/null || true; fi
    rm -f "$recpid" "$recfile"
    if [ -s "$out" ]; then
      notify-send -a Screenshot -i video-x-generic "Recording saved" "${out#"$HOME"/}" 2>/dev/null || true
      echo "$out"
    else
      fail "the recording is empty"
    fi
    exit 0 ;;
esac

tmp=$(mktemp --suffix=.png)
trap 'rm -f "$tmp"' EXIT

case "$mode" in
  full)
    err=$(maim -u -q -d 0.2 "$tmp" 2>&1) || fail "maim: ${err:-could not grab the screen}" ;;
  area | copy-area | text)
    if ! err=$(maim -u -s "$tmp" 2>&1); then
      case "$err" in *ancel*) exit 0 ;; esac          # Esc / right-click: you cancelled
      fail "maim: ${err:-could not grab the area}"
    fi ;;
  window | copy-window)
    win=$(xdotool getactivewindow 2>/dev/null) || fail "no window is focused"
    err=$(maim -u -q -d 0.2 -i "$win" "$tmp" 2>&1) || fail "maim: ${err:-could not grab the window}" ;;
  *)
    echo "usage: screenshot [menu|full|area|window|copy-area|copy-window|text|record|record-area|record-stop]"; exit 2 ;;
esac
[ -s "$tmp" ] || fail "maim produced an empty image"

case "$mode" in
  text)
    txt=$(tesseract "$tmp" - -l eng 2>/dev/null) || fail "couldn't read any text"
    printf '%s' "$txt" | xclip -selection clipboard
    notify-send -a Screenshot "Text copied" "$(printf '%s' "$txt" | head -c 120)" 2>/dev/null || true ;;
  copy-*)
    last="${XDG_CACHE_HOME:-$HOME/.cache}/screenshot-last.png"
    mkdir -p "${last%/*}"; cp "$tmp" "$last"
    xclip -selection clipboard -t image/png -i "$last"
    notify-send -a Screenshot -i "$last" "Screenshot copied" "On your clipboard — paste it anywhere." 2>/dev/null || true ;;
  *)
    mkdir -p "$dir" || fail "can't create $dir"
    out="$dir/$(date '+%Y-%m-%d_%H-%M-%S').png"
    [ -e "$out" ] && out="${out%.png}-$mode.png"
    mv "$tmp" "$out" || fail "can't save to $dir"
    xclip -selection clipboard -t image/png -i "$out"
    notify-send -a Screenshot -i "$out" "Screenshot saved" \
      "${out#"$HOME"/} — also on your clipboard" 2>/dev/null || true ;;
esac
