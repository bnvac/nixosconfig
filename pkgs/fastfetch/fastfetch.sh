# fastfetch (and `neofetch`), nix²'s way. Set above by Nix: $ff (the real
# fastfetch), $cfg (nix²'s config), $logos (pkgs/fastfetch-logos), $eye (the
# frames from eye.py).
#
#  - Inside a git repo that has its own logo (pkgs/fastfetch-logos/NAME.txt),
#    that logo.
#  - Otherwise the eye: fastfetch lays out a blank logo, this draws the eye
#    into it and, with no arguments, blinks it twice (about 2 s; Ctrl+C skips,
#    NIX2_NO_BLINK=1 turns it off).
#  - ~/.config/fastfetch/config.jsonc, if you make one, replaces nix²'s config.
config=()
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/config.jsonc" ] || config=(--config "$cfg")

if top=$(git rev-parse --show-toplevel 2>/dev/null); then
  n=$(basename "$top")
  if [ -f "$logos/$n.txt" ]; then
    exec "$ff" "${config[@]}" --logo-type file --logo "$logos/$n.txt" "$@"
  fi
fi
if [ ! -t 1 ]; then                      # piped: no room for drawing
  exec "$ff" "${config[@]}" --logo-type none "$@"
fi

# Print fastfetch's output ourselves, with line wrapping off so a long line
# can't push the layout down, and keep it to work out where the eye goes.
out=$("$ff" "${config[@]}" --pipe false --logo-type file --logo "$eye/space.txt" "$@"; printf x)
out=${out%x}
printf '\033[?7l%s\033[?7h' "$out"

# Cursor row now, counted from where the output started: newlines, minus
# fastfetch's own moves up (it goes back up to print the info beside the
# logo), plus moves down. The eye's top row is row 1 (logo padding top = 1).
moves() { { printf '%s' "$out" | grep -oaE $'\033\\[[0-9]*'"$1" || true; } | tr -dc '0-9\n' | awk '{ s += ($1 == "" ? 1 : $1) } END { print s + 0 }'; }
nl=$(printf '%s' "$out" | tr -cd '\n' | wc -c)
here=$(( nl - $(moves A) + $(moves B) ))
rows=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f1 || true)
# Too tall for the window (the eye scrolled off), or something odd: no eye.
[ "$here" -gt 1 ] && [ "$here" -lt "${rows:-0}" ] || exit 0

draw() {   # frame number: overwrite the eye's rows, then come back
  printf '\0337\033[%dA' $(( here - 1 ))
  while IFS= read -r line; do printf '\033[2G%s\033[1B' "$line"; done < "$eye/eye-$1.txt"
  printf '\0338'
}
draw 0
[ $# -eq 0 ] && [ -z "${NIX2_NO_BLINK:-}" ] || exit 0

printf '\033[?25l'                                 # hide the cursor meanwhile
trap 'draw 0; printf "\033[?25h"; exit 0' INT TERM
blink() {
  for f in 1 2 3 4; do draw "$f"; sleep 0.03; done
  sleep 0.08
  for f in 3 2 1 0; do draw "$f"; sleep 0.04; done
}
sleep 0.5; blink
sleep 0.9; blink
printf '\033[?25h'
