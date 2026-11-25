# fastfetch (and `neofetch`), MooreOS's way. Set above by Nix: $ff (the real
# fastfetch), $cfg (the config), $logos (pkgs/fastfetch-logos), $frames (the
# tumbling dodecahedron, one text file per frame, from branding/dodeca.py).
#
#  - The logo is the dodecahedron: in a terminal it spins in place for a
#    moment, then stops at a random angle. Piped, or FASTFETCH_SPIN=0: no spin.
#  - Inside a git repo that has its own logo (pkgs/fastfetch-logos/NAME.txt),
#    that logo instead.
#  - Colours come from the terminal's palette, which `rice` takes from your
#    wallpaper: the logo and the labels are its accent, the rest plain text.
#  - ~/.config/fastfetch/config.jsonc, if you make one, replaces this config.
config=()
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/config.jsonc" ] || config=(--config "$cfg")

if [ ! -t 1 ]; then                      # piped: no room for a picture
  exec "$ff" "${config[@]}" --logo-type none "$@"
fi
if top=$(git rev-parse --show-toplevel 2>/dev/null) && [ -f "$logos/$(basename "$top").txt" ]; then
  exec "$ff" "${config[@]}" --logo-type file --logo "$logos/$(basename "$top").txt" "$@"
fi

mapfile -t all < <(ls "$frames"/frame-*.txt)
n=${#all[@]}
stop=$(( RANDOM % n ))
if [ "${FASTFETCH_SPIN:-1}" = 0 ] || [ $# -gt 0 ]; then
  exec "$ff" "${config[@]}" --logo-type file --logo "${all[$stop]}" "$@"
fi

# Print it with the first frame, then redraw just the logo, frame by frame.
out=$("$ff" "${config[@]}" --pipe false --logo-type file --logo "${all[0]}")
printf '%s\n' "$out"
lines=$(printf '%s\n' "$out" | wc -l)
rows=$(wc -l < "${all[0]}")
[ "$lines" -lt "$(tput lines 2>/dev/null || echo 0)" ] || exit 0   # scrolled: leave it be
trap 'printf "\033[?25h"' EXIT INT TERM
printf '\033[?25l'
steps=$(( n + stop ))
for ((k = 1; k <= steps; k++)); do
  f=${all[$(( k % n ))]}
  printf '\033[%dA\033[1B' "$lines"                     # to the logo's first row (1 padding line)
  while IFS= read -r row; do
    printf '\r\033[2C\033[34m%s\033[0m\n' "${row#\$1}"   # 2 columns of padding, accent colour
  done < "$f"
  printf '\033[%dB' $(( lines - 1 - rows ))
  sleep 0.035
done
