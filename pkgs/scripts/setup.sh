# nix2-setup — this machine's own settings (settings.local.nix).
#
#   nix2-setup                 guided: works out user, hostname, timezone,
#                                laptop/desktop and graphics card, asks you to
#                                confirm each, writes settings.local.nix
#   nix2-setup --migrate       the same without questions (rebuild runs this
#                                once on machines set up before settings.local.nix
#                                existed, carrying your old values over)
#   nix2-setup set KEY VALUE   one value: F10, 42, true, [ "a" ] (a plain word = text)
#   nix2-setup unset KEY       back to nix²'s default
#   nix2-setup get KEY         print a value (yours, else the default)
#   nix2-setup module NAME on|off|default
#   nix2-setup modules         which modules are on
#   nix2-setup share           the lines that let your other machines use
#                                this one's builds (settings shareBuilds)
# --root DIR works on DIR/etc/nixos instead (the installer uses --root /mnt).

root=""
if [ "${1:-}" = --root ]; then root=${2:?--root needs a directory}; shift 2; fi
dir=${NIXOS_DIR:-$root/etc/nixos}
local_file="$dir/settings.local.nix"
defaults="$dir/settings.nix"

need_root() {
  if [ "$(id -u)" -ne 0 ] && ! [ -w "$dir" ]; then
    exec /run/wrappers/bin/sudo env "PATH=$PATH" bash "$0" ${root:+--root "$root"} "$@"
  fi
}

ensure_file() {
  [ -e "$local_file" ] && return 0
  cat > "$local_file" <<'EOF'
# This machine's settings. Any name from settings.nix can go here and replaces
# nix²'s default. Not in git, so updates never touch it. Change it with an
# editor, `modtui` → Edit settings, `mod on|off`, or `nix2-setup set`.
{
}
EOF
}

# KEY as a sed regex (dots in a.b.c are literal)
rx() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }

set_value() {   # set KEY NIX-VALUE
  local key=$1 value=$2 k
  ensure_file
  k=$(rx "$key")
  if grep -qE "^[[:space:]]*${k}[[:space:]]*=" "$local_file"; then
    KEY="$k" KEY_RAW="$key" VAL="$value" awk '
      BEGIN { re = "^[[:space:]]*" ENVIRON["KEY"] "[[:space:]]*=" }
      $0 ~ re && !done { print "  " ENVIRON["KEY_RAW"] " = " ENVIRON["VAL"] ";"; done = 1; next }
      { print }' "$local_file" > "$local_file.new"
  else
    KEY_RAW="$key" VAL="$value" awk '
      { lines[NR] = $0; if ($0 ~ /^}[[:space:]]*$/) last = NR }
      END {
        for (i = 1; i <= NR; i++) {
          if (i == last) print "  " ENVIRON["KEY_RAW"] " = " ENVIRON["VAL"] ";"
          print lines[i]
        }
      }' "$local_file" > "$local_file.new"
  fi
  mv "$local_file.new" "$local_file"
}

unset_value() {
  [ -e "$local_file" ] || return 0
  local k; k=$(rx "$1")
  grep -viE "^[[:space:]]*${k}[[:space:]]*=" "$local_file" > "$local_file.new" || true
  mv "$local_file.new" "$local_file"
}

get_value() {   # the raw Nix value, quotes removed for plain strings
  local k v=""; k=$(rx "$1")
  [ -e "$local_file" ] && v=$(sed -nE "s/^[[:space:]]*${k}[[:space:]]*=[[:space:]]*(.*);[[:space:]]*(#.*)?$/\1/p" "$local_file" | head -1)
  [ -n "$v" ] || v=$(sed -nE "s/^[[:space:]]*${k}[[:space:]]*=[[:space:]]*([^;]*);.*/\1/p" "$defaults" | head -1)
  v=${v#\"}; printf '%s\n' "${v%\"}"
}

str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"$]/\\&/g')"; }

# ── working things out ─────────────────────────────────────────────────────
detect_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then echo "$SUDO_USER"
  else getent passwd 1000 | cut -d: -f1; fi
}
detect_name() { getent passwd "$1" | cut -d: -f5 | cut -d, -f1; }
detect_tz() {
  local tz
  tz=$(timedatectl show -p Timezone --value 2>/dev/null) || tz=""
  [ -n "$tz" ] || tz=$(readlink "$root/etc/localtime" 2>/dev/null | sed 's|.*zoneinfo/||')
  echo "${tz:-UTC}"
}
detect_device() {
  for b in /sys/class/power_supply/BAT*; do [ -e "$b" ] && { echo laptop; return; }; done
  echo desktop
}
detect_gpu() {   # discrete NVIDIA/AMD over integrated; laptops keep the integrated one
  local vendors="" v
  for c in /sys/class/drm/card[0-9]*/device/vendor; do
    [ -e "$c" ] || continue
    v=$(cat "$c"); vendors="$vendors $v"
  done
  case "$vendors" in
    *0x10de*) if [ "$(detect_device)" = laptop ] && [[ "$vendors" =~ 0x8086|0x1002 ]]; then :; else echo nvidia; return; fi ;;
  esac
  case "$vendors" in
    *0x1002*) echo amd ;;
    *0x8086*) echo intel ;;
    *0x10de*) echo nvidia ;;
    *) echo none ;;
  esac
}
detect_esp() {
  local t
  for t in /boot/efi /boot /efi; do
    if [ "$(findmnt -n -o FSTYPE --target "$root$t" 2>/dev/null)" = vfat ] \
       && [ "$(findmnt -n -o TARGET --target "$root$t")" = "$root$t" ]; then echo "$t"; return; fi
  done
  echo /boot
}
# Rough location from the timezone (tzdata lists each zone's main city), for
# the night light's sunset time.
tz_location() {
  local tab line coords lat lon
  for tab in /etc/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone1970.tab; do [ -r "$tab" ] && break; done
  [ -r "$tab" ] || return 1
  line=$(awk -F'\t' -v z="$1" '$3 == z { print $2; exit }' "$tab")
  [ -n "$line" ] || return 1
  coords=$(printf '%s' "$line" | sed -E 's/^([+-][0-9]+)([+-][0-9]+)$/\1 \2/')
  read -r lat lon <<<"$coords"
  dm() { awk -v s="$1" -v w="$2" 'BEGIN { sign = substr(s,1,1) == "-" ? -1 : 1; d = substr(s,2,w); m = substr(s,2+w,2); printf "%.1f", sign * (d + m/60) }'; }
  echo "$(dm "$lat" 2) $(dm "$lon" 3)"
}

write_machine() {   # user name host tz device gpu esp grub
  set_value username "$(str "$1")"
  set_value fullName "$(str "$2")"
  set_value hostName "$(str "$3")"
  set_value timeZone "$(str "$4")"
  set_value device "$(str "$5")"
  set_value gpu "$(str "$6")"
  set_value espMountPoint "$(str "$7")"
  [ "$8" = true ] || set_value useGrub false
  local loc
  if loc=$(tz_location "$4"); then
    set_value location.latitude "${loc% *}"
    set_value location.longitude "${loc#* }"
  fi
}

ask() {   # ask "Question" default → answer
  local a
  read -r -p "$1 [$2]: " a </dev/tty || a=""
  echo "${a:-$2}"
}

ask_choice() {   # ask_choice "Question" default option… → one of the options
  local q=$1 def=$2 a o
  shift 2
  while :; do
    a=$(ask "$q" "$def" | tr '[:upper:]' '[:lower:]')
    for o in "$@"; do [ "$a" = "$o" ] && { echo "$a"; return; }; done
    echo "  Please type one of: $*" >/dev/tty
  done
}

# Keyboard layout: from the installer (which already switched to it, so the
# passwords typed there match), else asked here. Checked against the layouts
# this system knows when that list is around.
ask_keyboard() {
  local kb=${NIX2_KEYBOARD:-} sym=""
  [ -n "$kb" ] && { echo "$kb"; return; }
  for sym in "${NIX2_XKB:-}" /run/current-system/sw/share/X11/xkb ""; do
    [ -n "$sym" ] && [ -d "$sym/symbols" ] && break
  done
  while :; do
    kb=$(ask "Keyboard layout (us, gb, de, fr, es, it, se, br…)" "$(get_value keyboardLayout)" | tr '[:upper:]' '[:lower:]')
    if [[ "$kb" =~ ^[a-z0-9_]+$ ]] && { [ -z "$sym" ] || [ -e "$sym/symbols/$kb" ]; }; then echo "$kb"; return; fi
    echo "  Don't know a layout called '$kb' — it's a short code like us, gb, de or fr." >/dev/tty
  done
}

usage() {
  cat <<'EOF'
nix2-setup                 guided setup of this machine (settings.local.nix)
nix2-setup --migrate       the same, no questions (rebuild runs it when needed)
nix2-setup set KEY VALUE   one value: F10, 42, true, [ "a" ] (a plain word = text)
nix2-setup unset KEY       back to nix²'s default
nix2-setup get KEY         print a value
nix2-setup module NAME on|off|default
nix2-setup modules         which modules are on
nix2-setup share           how your other machines can use this one's builds
--root DIR (first) works on DIR/etc/nixos; the installer uses --root /mnt
EOF
}

# ── commands ───────────────────────────────────────────────────────────────
# `nix2-setup set`, forgiving: a name in the wrong case is corrected to the
# one settings.nix uses (screenshotkey → screenshotKey), and a plain word
# becomes text (F10 → "F10"), so the Nix quoting rules can't trip you up.
set_cmd() {
  local key=$1 value=$2 top rest known
  top=${key%%.*}; rest=${key#"$top"}
  # Every setting name settings.nix mentions, set or commented out.
  known=$(sed -nE 's/^[[:space:]]*#?[[:space:]]*([A-Za-z][A-Za-z0-9]*)[[:space:]]*=.*/\1/p' "$defaults" | sort -u)
  if ! printf '%s\n' "$known" | grep -qx "$top"; then
    local fixed; fixed=$(printf '%s\n' "$known" | grep -ixm1 "$top" || true)
    if [ -n "$fixed" ]; then
      echo ":: (it's spelled $fixed)"
      top=$fixed; key=$fixed$rest
    else
      echo "nix2-setup: note — settings.nix doesn't mention \"$top\"; setting it anyway."
    fi
  fi
  case "$value" in
    true | false | null | \"* | \[* | \{* | \'\'* ) ;;
    *) printf '%s' "$value" | grep -qE '^-?[0-9]+(\.[0-9]+)?$' || value=$(str "$value") ;;
  esac
  cp "$local_file" "$local_file.bak" 2>/dev/null || true
  set_value "$key" "$value"
  # Never leave a file that breaks the next rebuild.
  if command -v nix-instantiate >/dev/null \
     && ! err=$(nix-instantiate --eval --strict "$local_file" 2>&1 >/dev/null); then
    mv "$local_file.bak" "$local_file"
    echo "nix2-setup: $key = $value isn't valid, so nothing was changed:"
    printf '%s\n' "$err" | grep -m1 'error:' | sed 's/^/  /'
    echo "  (a list needs quotes around it: nix2-setup set $key '[ \"a\" \"b\" ]')"
    exit 1
  fi
  rm -f "$local_file.bak"
  echo ":: $key = $value"
}

migrate() {
  need_root --migrate
  [ -e "$local_file" ] && { echo "nix2-setup: $local_file already exists"; return 0; }
  local user name host tz dev gpu esp grub=true old="" m
  user=$(detect_user); name=$(detect_name "$user"); host=$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname)
  tz=$(detect_tz); dev=$(detect_device); gpu=$(detect_gpu); esp=$(detect_esp)
  [ -d "$root/boot/grub" ] || [ -d "$root$esp/grub" ] || { [ -d "$root$esp/loader" ] && grub=false; }

  # Set up before settings.local.nix existed? Then the old settings.nix and
  # mods/ in git history say which modules you had on, and your look.
  if [ -d "$dir/.git" ]; then
    old=$(git -C "$dir" log -1 --format=%H -S'hasLocal' -- settings.nix 2>/dev/null || true)
  fi
  ensure_file
  write_machine "$user" "${name:-$user}" "$host" "$tz" "$dev" "$gpu" "$esp" "$grub"
  if [ -n "$old" ] && git -C "$dir" cat-file -e "$old^:settings.nix" 2>/dev/null; then
    local oldmods; oldmods=$(git -C "$dir" ls-tree --name-only "$old^" mods/ | sed 's|^mods/||')
    for f in "$dir"/modules/*.nix; do
      m=$(basename "$f" .nix); [ "$m" = core ] && continue
      local was=false now=false
      printf '%s\n' "$oldmods" | grep -qx "$m" && was=true
      [ -e "$dir/mods/$m" ] && now=true
      [ "$was" = "$now" ] || set_value "modules.$m" "$was"
    done
    local key val
    for key in termOpacity liveSnow kernel autoUpdate channelUpdates backupRepo; do
      val=$(git -C "$dir" show "$old^:settings.nix" | sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^;]*);.*/\1/p" | head -1)
      [ -n "$val" ] && [ "$val" != "$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^;]*);.*/\1/p" "$defaults" | head -1)" ] \
        && set_value "$key" "$val"
    done
  fi
  echo ":: wrote $local_file (this machine's settings):"
  sed -n '/^{/,/^}/p' "$local_file"
}

guided() {
  need_root
  echo "nix² setup — this machine's settings. Enter keeps the value in [brackets]."
  echo
  local user name host tz dev gpu esp grub=true
  # From the installer (--root) the live USB's own user and hostname mean
  # nothing, so suggest none.
  local defuser defname defhost
  defuser=$(get_value username); defhost=$(get_value hostName); defname=""
  if [ -z "$root" ]; then
    [ "$defuser" != user ] || defuser=$(detect_user)
    defhost=$(hostname 2>/dev/null || echo "$defhost")
  fi
  while :; do
    user=$(ask "Your username (lowercase, no spaces)" "$defuser")
    [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] && [ "$user" != root ] && break
    echo "  A username is lowercase letters, digits, - or _, starting with a letter (like ada or sam_2)." >/dev/tty
  done
  [ -z "$root" ] && defname=$(detect_name "$user" || true)
  name=$(ask "Your name" "${defname:-$user}")
  host=$(ask "This computer's name (hostname)" "$defhost")
  tz=$(ask "Timezone (e.g. America/New_York, Europe/London)" "$(detect_tz)")
  local kb oldkb
  oldkb=$(get_value keyboardLayout)
  kb=$(ask_keyboard)
  dev=$(ask_choice "desktop or laptop" "$(detect_device)" desktop laptop)
  gpu=$(ask_choice "Graphics: amd, intel, nvidia or none" "$(detect_gpu)" amd intel nvidia none)
  esp=$(detect_esp)
  [ -d "$root$esp/loader" ] && ! [ -d "$root/boot/grub" ] && grub=false
  ensure_file
  write_machine "$user" "${name:-$user}" "$host" "$tz" "$dev" "$gpu" "$esp" "$grub"
  if [ "$kb" = us ]; then unset_value keyboardLayout; else set_value keyboardLayout "$(str "$kb")"; fi
  if [ -z "$root" ] && [ "$kb" != "$oldkb" ]; then
    echo
    echo "Note: after the rebuild and a restart, the login screen (and the disk password"
    echo "prompt, if the disk is encrypted) use the $kb layout too — type passwords by"
    echo "the letters printed on your keys."
  fi
  echo
  echo ":: saved to $local_file:"
  sed -n '/^{/,/^}/p' "$local_file"
  [ -n "$root" ] || { echo; echo "Apply it with: rebuild"; }
}

module() {   # module NAME on|off|default
  local m=$1 want=$2 def=false
  [ -f "$dir/modules/$m.nix" ] && [ "$m" != core ] || { echo "no module '$m' (try: mod list)"; exit 1; }
  [ -e "$dir/mods/$m" ] && def=true
  case "$want" in
    on) want=true ;; off) want=false ;;
    default) unset_value "modules.$m"; return ;;
    *) echo "usage: nix2-setup module NAME on|off|default"; exit 2 ;;
  esac
  if [ "$want" = "$def" ]; then unset_value "modules.$m"; else set_value "modules.$m" "$want"; fi
}

modules_on() {
  nix-instantiate --eval --strict --json -E \
    "(import $dir/picker.nix (import <nixpkgs/lib>)).on" 2>/dev/null | tr -d '[]"' | tr ',' '\n'
}

share() {
  local key=/var/lib/nix2/cache-key
  if ! [ -r "$key.pub" ]; then
    echo "This machine doesn't share its builds yet. In settings.local.nix:"
    echo "  shareBuilds.serve = true;"
    echo "then rebuild, and run nix2-setup share again."
    return 1
  fi
  echo "Put these two lines in settings.local.nix on your OTHER machines, then rebuild there:"
  echo
  echo "  shareBuilds.from = \"http://$(hostname).local:5000\";"
  echo "  shareBuilds.key = \"$(cat "$key.pub")\";"
}

case "${1:-}" in
  "") guided ;;
  --migrate) migrate ;;
  set) need_root "$@"; [ $# -ge 3 ] || { echo "usage: nix2-setup set KEY VALUE"; exit 2; }; k=$2; shift 2; set_cmd "$k" "$*" ;;
  unset) need_root "$@"; unset_value "${2:?KEY}" ;;
  get) get_value "${2:?KEY}" ;;
  module) need_root "$@"; module "${2:?NAME}" "${3:?on|off|default}" ;;
  modules) modules_on ;;
  share) share ;;
  -h|--help|help) usage ;;
  *) echo "nix2-setup: unknown command '$1' (try: nix2-setup help)"; exit 2 ;;
esac
