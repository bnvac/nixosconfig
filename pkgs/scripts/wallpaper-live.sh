# wallpaper-live — plays the Wallpaper Engine wallpaper you picked in
# `wallpapers` on every screen (linux-wallpaperengine): muted, capped at
# 30 fps, paused while something is fullscreen. Run by the wallpaper-live
# user service; nothing picked = nothing runs.
#
# Two things this desktop needs for it to show up at all:
#  - XDG_SESSION_TYPE=x11. linux-wallpaperengine decides between X11 and
#    Wayland from it and quits straight away without it — and systemd user
#    services don't get it from the X session.
#  - A window per monitor instead of drawing on the root window. On X11, a
#    compositor (picom, which makes the terminals see-through) hides anything
#    drawn on the root window. dwm keeps windows of class
#    linux-wallpaperengine at the very bottom and never tiles them.
conf="${XDG_CONFIG_HOME:-$HOME/.config}/wallpapers/live"
[ -s "$conf" ] || exit 0
bg=$(head -n 1 "$conf")
[ -e "$bg" ] || { echo "wallpaper-live: $bg is gone (unsubscribed in the Workshop?)"; exit 0; }
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"

# Wallpaper Engine's own assets come with the app from Steam; most
# wallpapers need them.
assets=""
for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
  if [ -d "$root/steamapps/common/wallpaper_engine/assets" ]; then
    assets="$root/steamapps/common/wallpaper_engine/assets"; break
  fi
done
if [ -z "$assets" ]; then
  echo "wallpaper-live: Wallpaper Engine isn't installed in Steam; its assets are needed (wallpapers → Wallpaper Engine tab)"
  exit 0
fi

# One window per monitor: "1920/527x1080/296+0+0" → --window 0x0x1920x1080
args=()
while read -r geom; do
  win=$(printf '%s' "$geom" | sed -E 's#^([0-9]+)/[0-9]+x([0-9]+)/[0-9]+\+([0-9]+)\+([0-9]+)$#\3x\4x\1x\2#')
  [ "$win" != "$geom" ] && args+=(--window "$win" --bg "$bg")
done < <(xrandr --listactivemonitors | awk 'NR > 1 {print $3}')
[ "${#args[@]}" -gt 0 ] || { echo "wallpaper-live: no screens found"; exit 1; }

exec linux-wallpaperengine --silent --disable-mouse --fps "${WALLPAPER_FPS:-30}" \
  --assets-dir "$assets" "${args[@]}"
