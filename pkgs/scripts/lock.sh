# lock — the lock screen: Super+Alt+l, sysact → lock, and automatically on
# suspend or after 10 idle minutes (xss-lock). Snowy picture, a clock, and a
# ring that lights up as you type. Uses your own wallpaper instead if it's a PNG.
img=$LOCK_IMAGE                                   # set by the overlay: the snowy default
bg="${XDG_DATA_HOME:-$HOME/.local/share}/bg"
if [ -e "$bg" ] && [ "$(file -b -L --mime-type "$bg")" = image/png ]; then
  img=$(readlink -f "$bg")
fi
exec i3lock --nofork --image "$img" --fill --clock --indicator \
  --time-str "%H:%M" --date-str "%A, %d %B" \
  --time-font "JetBrainsMono Nerd Font" --date-font "JetBrainsMono Nerd Font" \
  --time-size 64 --date-size 20 --time-color e8f0f8ff --date-color c8d8eaff \
  --inside-color 0b1a2e99 --ring-color e8f0f8bb --line-uses-inside --separator-color 00000000 \
  --keyhl-color 8ec5ffff --bshl-color ffb0b0ff \
  --insidever-color 0b1a2ecc --ringver-color 8ec5ffff --verif-color e8f0f8ff --verif-text "" \
  --insidewrong-color 4a1420cc --ringwrong-color ff8a8aff --wrong-text "try again" \
  --noinput-text "" --radius 110 --ring-width 7 \
  --pass-media-keys --pass-volume-keys --pass-screen-keys --ignore-empty-password --show-failed-attempts
