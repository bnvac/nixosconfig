# wallpaper-live — plays the Wallpaper Engine wallpaper you picked in
# `wallpapers` on every connected screen (linux-wallpaperengine). Muted, capped
# at 30 fps, and it pauses by itself while something is fullscreen (games,
# videos). Run by the wallpaper-live user service; no pick = nothing runs.
conf="${XDG_CONFIG_HOME:-$HOME/.config}/wallpapers/live"
[ -s "$conf" ] || exit 0
bg=$(head -n 1 "$conf")
[ -e "$bg" ] || { echo "wallpaper-live: $bg is gone (unsubscribed?)"; exit 0; }

args=()
while read -r out; do
  args+=(--screen-root "$out" --scaling fill)
done < <(xrandr --listactivemonitors | awk 'NR > 1 {print $NF}')
[ "${#args[@]}" -gt 0 ] || { echo "wallpaper-live: no screens found"; exit 1; }

exec linux-wallpaperengine --silent --fps "${WALLPAPER_FPS:-30}" "${args[@]}" "$bg"
