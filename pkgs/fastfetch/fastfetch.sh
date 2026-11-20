# fastfetch (and `neofetch`), parajynx's way. Set above by Nix: $ff (the real
# fastfetch), $cfg (parajynx's config), $logos (pkgs/fastfetch-logos), $logo
# (the 并行 logo, pkgs/fastfetch/logo.txt).
#
#  - Inside a git repo that has its own logo (pkgs/fastfetch-logos/NAME.txt),
#    that logo; otherwise 并行.
#  - Colours come from the terminal's palette, which `rice` takes from your
#    wallpaper: the logo and the labels are its accent, the rest plain text.
#  - ~/.config/fastfetch/config.jsonc, if you make one, replaces parajynx's config.
config=()
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/config.jsonc" ] || config=(--config "$cfg")

use=$logo
if top=$(git rev-parse --show-toplevel 2>/dev/null); then
  n=$(basename "$top")
  [ -f "$logos/$n.txt" ] && use="$logos/$n.txt"
fi
if [ ! -t 1 ]; then                      # piped: no room for a picture
  exec "$ff" "${config[@]}" --logo-type none "$@"
fi
exec "$ff" "${config[@]}" --logo-type file --logo "$use" "$@"
