# screenshot — Print = whole screen, Shift+Print = this menu.
#   screenshot [menu|full|area|window|copy-area|copy-window|text]
# Saves to ~/Pictures/screenshots/<date>_<time>.png (always an absolute
# path, so it works no matter which folder your session started in) and puts
# the picture on the clipboard too. A notification shows the shot — or says
# what went wrong, instead of failing silently.

dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/screenshots"
mode=${1:-menu}

fail() {
  notify-send -u critical -a Screenshot "Screenshot failed" "$1" 2>/dev/null || true
  echo "screenshot: $1" >&2
  exit 1
}

if [ "$mode" = menu ]; then
  choice=$(printf '%s\n' "Area" "Window" "Full screen" "Area → clipboard only" \
             "Window → clipboard only" "Text from an area → clipboard (OCR)" \
           | dmenu -i -l 6 -p "Screenshot:") || exit 0
  case "$choice" in
    Area) mode=area ;;
    Window) mode=window ;;
    "Full screen") mode=full ;;
    "Area →"*) mode=copy-area ;;
    "Window →"*) mode=copy-window ;;
    Text*) mode=text ;;
    *) exit 0 ;;
  esac
fi

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
    echo "usage: screenshot [menu|full|area|window|copy-area|copy-window|text]"; exit 2 ;;
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
