# apps — every installed app, grouped by category, in dmenu (Super+Alt+a).
#   apps              pick a category, then an app
#   apps --list       category<TAB>name<TAB>.desktop file  (Neb's `desk open` uses this)
#   apps --launch F   start the app described by .desktop file F

app_dirs() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  IFS=: read -ra sys <<<"${XDG_DATA_DIRS:-/run/current-system/sw/share}"
  for d in "${sys[@]}"; do printf '%s\n' "$d/applications"; done
}

# One line per visible app. The first .desktop id wins (your ~/.local copy
# overrides the system one), and duplicate names are dropped.
index() {
  local files=() d f
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    for f in "$d"/*.desktop; do [ -e "$f" ] && files+=("$f"); done
  done < <(app_dirs)
  [ "${#files[@]}" -gt 0 ] || return 0
  awk '
    function category(c) {
      if (c ~ /;Game;/)                                         return "Games"
      if (c ~ /;(AudioVideo|Audio|Video);/)                     return "Media"
      if (c ~ /;Graphics;/)                                     return "Graphics"
      if (c ~ /;(Engineering|Electronics|Science|Education|Math);/) return "Engineering & Science"
      if (c ~ /;Development;/)                                  return "Development"
      if (c ~ /;Office;/)                                       return "Office"
      if (c ~ /;(Network|WebBrowser|Email|Chat|InstantMessaging);/) return "Internet"
      if (c ~ /;(Utility|Accessories|FileManager|TextEditor|Archiving);/) return "Utilities"
      if (c ~ /;(Settings|System|Monitor|HardwareSettings|PackageManager);/) return "System"
      return "Other"
    }
    function flush() {
      if (file != "" && type == "Application" && name != "" && nodisplay != "true" \
          && hidden != "true" && onlyshow == "" && !(seen[id]++) && !(named[name]++))
        printf "%s\t%s\t%s\n", category(cats), name, file
    }
    FNR == 1 {
      flush(); file = FILENAME; id = FILENAME; sub(/.*\//, "", id)
      name = type = cats = nodisplay = hidden = onlyshow = ""; insec = 0
    }
    /^\[/                                 { insec = ($0 == "[Desktop Entry]"); next }
    insec && /^Name=/ && name == ""       { name = substr($0, 6) }
    insec && /^Type=/                     { type = substr($0, 6) }
    insec && /^Categories=/               { cats = ";" substr($0, 12) ";" }
    insec && /^NoDisplay=/                { nodisplay = tolower(substr($0, 11)) }
    insec && /^Hidden=/                   { hidden = tolower(substr($0, 8)) }
    insec && /^OnlyShowIn=/               { onlyshow = substr($0, 12) }
    END                                   { flush() }
  ' "${files[@]}"
}

field() {   # field FILE KEY — a key from the [Desktop Entry] section
  awk -v k="$2=" '/^\[/ { s = ($0 == "[Desktop Entry]") }
                  s && index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$1"
}

launch() {
  local f=$1 cmd
  # drop the %f/%U/… field codes (we pass no files), keep a literal %%
  cmd=$(field "$f" Exec | sed -E 's/%%/\x01/g; s/%[fFuUdDnNickvm]//g; s/\x01/%/g')
  [ -n "$cmd" ] || { echo "apps: no Exec in $f" >&2; return 1; }
  if [ "$(field "$f" Terminal | tr '[:upper:]' '[:lower:]')" = true ]; then
    setsid -f "${TERMINAL:-st}" -e sh -c "$cmd" >/dev/null 2>&1
  else
    setsid -f sh -c "$cmd" >/dev/null 2>&1
  fi
}

menu() {
  local list cat names pick file
  list=$(index)
  [ -n "$list" ] || { notify-send "Apps" "No applications found."; return 1; }
  while :; do
    cat=$({ echo "★ Everything"
            cut -f1 <<<"$list" | sort | uniq -c | awk '{ n = $1; $1 = ""; sub(/^ /, ""); printf "%s  (%d)\n", $0, n }'
          } | dmenu -i -l 15 -p "apps:") || return 0
    cat=${cat%  (*}
    if [ "$cat" = "★ Everything" ]; then
      names=$(cut -f2 <<<"$list" | sort -f)
    else
      names=$(awk -F'\t' -v c="$cat" '$1 == c { print $2 }' <<<"$list" | sort -f)
    fi
    pick=$(printf '%s\n%s\n' "← back" "$names" | dmenu -i -l 20 -p "$cat:") || return 0
    [ "$pick" = "← back" ] && continue
    file=$(awk -F'\t' -v n="$pick" '$2 == n { print $3; exit }' <<<"$list")
    [ -n "$file" ] && launch "$file"
    return 0
  done
}

case "${1:-}" in
  --list)   index ;;
  --launch) launch "$2" ;;
  *)        menu ;;
esac
