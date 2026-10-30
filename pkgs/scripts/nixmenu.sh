# nixmenu — this system's own actions, in two short levels: pick a category,
# then an action (Super+Alt+Space). `nixmenu "Self-hosted"` jumps straight
# into one category.
#
# Entries come from:
#   /etc/nixmenu/menu.tsv        built from the modules + settings.nix → menu
#   ~/.config/nixmenu/menu       yours — edit any time, no rebuild:
#       Category | Label | command          run it
#       Category | Label | term: command    run in a terminal, wait for Enter
#       Category | Label | tty: command     a full-screen terminal program
#       Category | Label | url: https://…   open as an app window
#       hide  | Label                        hide a built-in entry
#       order | System, Self-hosted, …       category order
# Self-hosted also lists running Docker containers that publish a port.

sysmenu=${NIXMENU_FILE:-/etc/nixmenu/menu.tsv}
usermenu=${XDG_CONFIG_HOME:-$HOME/.config}/nixmenu/menu
export PATH="$PATH:/run/current-system/sw/bin"

have() { command -v "$1" >/dev/null 2>&1; }

# First run: leave a commented starter file so the format is right there.
if [ ! -e "$usermenu" ] && mkdir -p "${usermenu%/*}" 2>/dev/null; then
  cat >"$usermenu" <<'EOF'
# Your own nixmenu entries (Super+Alt+Space). Changes apply instantly.
#   Category | Label | command          run it
#   Category | Label | term: command    run in a terminal, wait for Enter
#   Category | Label | tty: command     a full-screen terminal program
#   Category | Label | url: https://…   open as an app window
#   hide  | Label                        hide a built-in entry
#   order | System, Self-hosted, …       category order (listed ones first)
# Examples (remove the # to use):
# My stuff | Notes | tty: nvim ~/notes
# My stuff | Disk usage | term: df -h
# Self-hosted | Home server | url: http://192.168.1.10:9000
# hide | Toggle live snow
EOF
fi
trim() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"$1"; }

cats=(); labels=(); modes=(); runs=()
declare -A hidden=()
order=()

add() {   # CATEGORY LABEL MODE RUN
  [ -n "${hidden[$2]:-}" ] && return 0
  cats+=("$1"); labels+=("$2"); modes+=("$3"); runs+=("$4")
}

# Your file, pass 1: hides and order (they apply to the built-ins too).
userlines=()
if [ -r "$usermenu" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(trim "$line")
    case "$line" in "" | "#"*) continue ;; esac
    [[ "$line" == *" | "* ]] || continue
    c=$(trim "${line%% | *}"); rest=$(trim "${line#* | }")
    case "$c" in
      hide) hidden[$rest]=1 ;;
      order) IFS=',' read -ra o <<<"$rest"; for x in "${o[@]}"; do order+=("$(trim "$x")"); done ;;
      *) userlines+=("$line") ;;
    esac
  done <"$usermenu"
fi

# Built-in entries (category, label, mode, needs or -, command), in module order.
if [ -r "$sysmenu" ]; then
  while IFS=$'\t' read -r c l m n r; do
    [ -n "$c" ] || continue
    if [ "$n" != - ] && ! have "$n"; then continue; fi
    add "$c" "$l" "$m" "$r"
  done <"$sysmenu"
fi

# Your entries.
for line in "${userlines[@]}"; do
  c=$(trim "${line%% | *}"); rest=${line#* | }
  [[ "$rest" == *" | "* ]] || continue
  l=$(trim "${rest%% | *}"); r=$(trim "${rest#* | }")
  case "$r" in
    term:*) add "$c" "$l" term "$(trim "${r#term:}")" ;;
    tty:*)  add "$c" "$l" tty "$(trim "${r#tty:}")" ;;
    url:*)  add "$c" "$l" url "$(trim "${r#url:}")" ;;
    *)      add "$c" "$l" exec "$r" ;;
  esac
done

# Running Docker containers that publish a port → Self-hosted. Only if Docker
# is already up: asking a socket-activated daemon would start it just for this.
if have docker && systemctl is-active --quiet docker.service 2>/dev/null; then
  while IFS=$'\t' read -r name ports; do
    port=$(grep -oE ':[0-9]+->' <<<"$ports" | head -n 1 | grep -oE '[0-9]+') || true
    [ -n "$port" ] && add "Self-hosted" "$name (docker :$port)" url "http://127.0.0.1:$port"
  done < <(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null)
fi

[ "${#cats[@]}" -gt 0 ] || { echo "nixmenu: no entries ($sysmenu missing?)"; exit 1; }

# Categories: your `order` lines first, then the rest as they appeared.
declare -A seen=()
catlist=()
for c in "${order[@]}" "${cats[@]}"; do
  [ -n "${seen[$c]:-}" ] && continue
  for x in "${cats[@]}"; do
    if [ "$x" = "$c" ]; then catlist+=("$c"); seen[$c]=1; break; fi
  done
done

menu() { dmenu -i -l 20 -p "$1"; }

if [ -n "${1:-}" ]; then
  cat=$1
else
  cat=$(printf '%s\n' "${catlist[@]}" | menu "nix:") || exit 0
fi

idx=(); shown=()
for i in "${!cats[@]}"; do
  if [ "${cats[$i]}" = "$cat" ]; then idx+=("$i"); shown+=("${labels[$i]}"); fi
done
[ "${#idx[@]}" -gt 0 ] || exit 0
sel=$(printf '%s\n' "${shown[@]}" | menu "$cat:") || exit 0

for i in "${idx[@]}"; do
  [ "${labels[$i]}" = "$sel" ] || continue
  run=${runs[$i]}
  case "${modes[$i]}" in
    term) exec st -e sh -c "$run; echo; printf '[enter] '; read -r _" ;;
    tty)  exec st -e sh -c "$run" ;;
    url)
      if have chromium; then exec chromium --app="$run"; fi
      exec xdg-open "$run" ;;
    *)    exec sh -c "$run" ;;
  esac
done
