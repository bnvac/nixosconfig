# debloat — see what takes space, free it, and drop apps you don't use.
#
#   debloat               what's using space (asks to clean when run in a terminal)
#   debloat clean         free space now: old system versions (keeps the last 5),
#                         unused store paths, safe caches, old logs, unused
#                         Docker images and Flatpak runtimes
#   debloat list          the app names you can remove
#   debloat remove NAME…  stop installing these, in EVERY module (settings →
#                         removePackages), then `rebuild --no-update`. A Flatpak
#                         app id (org.gimp.GIMP) is uninstalled instead, along
#                         with any runtime nothing else needs; its data is kept
#   debloat keep NAME…    undo a remove
#   debloat junk [DAYS]   build leftovers (target/, node_modules/, build/,
#                         .venv/…) in projects you haven't built for 30 days:
#                         lists them with sizes, asks before deleting. The
#                         next build re-creates them.
#
# Removing an app also drops whatever it alone depended on at the next
# `debloat clean`. Nothing here deletes your own files.
#
# Flatpak keeps runtimes (GNOME, KDE, freedesktop, GL drivers) that apps share,
# and leaves them behind when the last app using them goes. Apps install
# system-wide or per user, so both scopes are trimmed.

export PATH="$PATH:/run/current-system/sw/bin:/run/wrappers/bin"

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Build-output folders in your projects not touched for DAYS — only next to
# the file that proves what they are (target/ beside Cargo.toml, …).
junk_dirs() {
  local days=${1:-30} d parent
  find "$HOME" -xdev -path "$HOME/.*" -prune -o -type d \( -name target -o -name node_modules \
       -o -name build -o -name .direnv -o -name .venv -o -name __pycache__ -o -name .zig-cache \
       -o -name zig-out \) -prune -print 2>/dev/null |
  while IFS= read -r d; do
    parent=${d%/*}
    case "${d##*/}" in
      target)       [ -e "$parent/Cargo.toml" ] || continue ;;
      node_modules) [ -e "$parent/package.json" ] || continue ;;
      build)        [ -e "$parent/CMakeLists.txt" ] || [ -e "$parent/meson.build" ] || continue ;;
      .direnv)      [ -e "$parent/.envrc" ] || continue ;;
      .venv)        [ -e "$d/pyvenv.cfg" ] || continue ;;
      .zig-cache | zig-out) [ -e "$parent/build.zig" ] || continue ;;
    esac
    # anything inside written in the last DAYS → still in use
    [ -n "$(find "$d" -maxdepth 1 -newermt "$days days ago" -print -quit 2>/dev/null)" ] && continue
    printf '%s\n' "$d"
  done
}

junk() {
  local days=${1:-30} total=0 size a d
  local -a list
  mapfile -t list < <(junk_dirs "$days")
  if [ "${#list[@]}" -eq 0 ]; then echo "No build leftovers older than $days days."; return 0; fi
  echo "Build leftovers in projects you haven't built for $days+ days"
  echo "(safe to delete — the next build makes them again):"
  for d in "${list[@]}"; do
    size=$(du -sb "$d" 2>/dev/null | cut -f1); total=$(( total + ${size:-0} ))
    printf '  %8s  %s\n' "$(human "${size:-0}")" "${d#"$HOME"/}"
  done
  echo "  total: $(human "$total")"
  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Delete them? [y/N] '; read -r a
    case "$a" in
      y | Y | yes) for d in "${list[@]}"; do rm -rf -- "$d"; done; echo "Freed $(human "$total")." ;;
    esac
  fi
}

report() {
  echo "── disk ─────────────────────────────────────────────"
  df -h / | awk 'NR == 2 {print "  / : " $3 " used of " $2 " (" $5 "), " $4 " free"}'
  local closure gens
  closure=$(nix path-info -S /run/current-system 2>/dev/null | awk '{print $2}')
  gens=$(find /nix/var/nix/profiles -maxdepth 1 -name 'system-*-link' 2>/dev/null | wc -l)
  echo "  this system with everything it needs: $(human "${closure:-0}")"
  echo "  system versions kept for rollback:    $gens   (clean keeps the last 5)"
  echo
  echo "── biggest things in this system ────────────────────"
  nix path-info -rs /run/current-system 2>/dev/null | sort -k2 -n | tail -n 15 | sort -k2 -nr \
    | while read -r path size; do
        name=${path#/nix/store/*-}
        printf '  %8s  %s\n' "$(human "$size")" "$name"
      done
  echo
  echo "── caches & logs ────────────────────────────────────"
  [ -d "$HOME/.cache" ] && echo "  ~/.cache           $(du -sh "$HOME/.cache" 2>/dev/null | cut -f1)"
  echo "  system journal     $(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]' | head -n 1)"
  for c in sccache ccache; do
    [ -d "$HOME/.cache/$c" ] && printf '  ~/.cache/%-9s %s   (compile cache: makes rebuilds fast; capped)\n' "$c" "$(du -sh "$HOME/.cache/$c" 2>/dev/null | cut -f1)"
  done
  local junk_n
  junk_n=$(junk_dirs 30 | wc -l)
  [ "$junk_n" -gt 0 ] && echo "  build leftovers    $junk_n old project build folders — see: debloat junk"
  if have docker && systemctl is-active --quiet docker.service 2>/dev/null; then
    echo "  docker:"; docker system df 2>/dev/null | sed 's/^/    /'
  fi
  if have flatpak; then
    echo
    echo "── flatpak ──────────────────────────────────────────"
    local apps runtimes
    apps=$(flatpak list --app --columns=application 2>/dev/null | grep -c .)
    runtimes=$(flatpak list --runtime --columns=application 2>/dev/null | grep -c .)
    echo "  $apps apps, $runtimes runtimes and extensions"
    for d in /var/lib/flatpak "$HOME/.local/share/flatpak"; do
      [ -d "$d" ] && echo "  $(du -sh "$d" 2>/dev/null | cut -f1)  $d"
    done
    [ -d "$HOME/.var/app" ] && echo "  $(du -sh "$HOME/.var/app" 2>/dev/null | cut -f1)  ~/.var/app (app data and caches)"
  fi
  echo
  echo "Apps you can drop everywhere: \`debloat list\`, then \`debloat remove <name>\`."
}

clean() {
  local before after
  before=$(df -B1 --output=avail / | tail -n 1)
  echo ":: old system versions (keeping the last 5) …"
  sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +5 >/dev/null 2>&1 || true
  nix-env --delete-generations 14d >/dev/null 2>&1 || true
  echo ":: unused store paths …"
  sudo nix-collect-garbage 2>&1 | tail -n 1
  echo ":: caches (re-created on demand) …"
  for c in "$HOME/.cache/thumbnails" "$HOME/.cache/pip" "$HOME/.cache/go-build" "$HOME/.cache/yarn" \
           "$HOME/.npm/_cacache" "$HOME/.cache/nix" "$HOME/.cargo/registry/cache" "$HOME/.cache/mesa_shader_cache"; do
    [ -e "$c" ] && rm -rf "$c"
  done
  echo ":: logs older than a month / over 200 MB …"
  sudo journalctl --vacuum-time=1month --vacuum-size=200M >/dev/null 2>&1 || true
  if have docker && systemctl is-active --quiet docker.service 2>/dev/null; then
    echo ":: unused Docker images and build cache (volumes are never touched) …"
    docker image prune -af >/dev/null 2>&1 || true
    docker builder prune -af >/dev/null 2>&1 || true
  fi
  if have flatpak; then
    trim_flatpak
    echo ":: Flatpak app caches (each app re-creates its own) …"
    for c in "$HOME"/.var/app/*/cache; do
      [ -d "$c" ] && rm -rf "${c:?}"/*
    done
  fi
  # The boot menu still lists the versions just deleted — refresh it.
  sudo /run/current-system/bin/switch-to-configuration boot >/dev/null 2>&1 || true
  after=$(df -B1 --output=avail / | tail -n 1)
  echo "Freed $(human "$(( after > before ? after - before : 0 ))")."
}

# Runtimes and extensions no installed app uses any more, in both scopes.
# --unused never touches a runtime an app still needs.
trim_flatpak() {
  echo ":: unused Flatpak runtimes and extensions …"
  flatpak uninstall --user --unused -y --noninteractive 2>/dev/null | grep -E '^ *[0-9]+\.' | sed 's/^ */   /' || true
  sudo flatpak uninstall --system --unused -y --noninteractive 2>/dev/null | grep -E '^ *[0-9]+\.' | sed 's/^ */   /' || true
}

# Is NAME an installed Flatpak app id, in either scope?
is_flatpak_app() {
  have flatpak && flatpak list --app --columns=application 2>/dev/null | grep -qxF "$1"
}

# removePackages = [ … ] (this machine's, settings.local.nix), one name per line.
current() { nix2-setup get removePackages | grep -oE '"[^"]+"' | tr -d '"' || true; }
setlist() {
  local items
  items=$(sort -u | awk 'NF {printf " \"%s\"", $0}')
  sudo nix2-setup set removePackages "[${items} ]"
  echo "settings.local.nix: removePackages = [${items} ];"
  echo "Apply with: rebuild --no-update"
}

case "${1:-}" in
  "")
    report
    if [ -t 0 ] && [ -t 1 ]; then
      printf '\nClean up now? [y/N] '; read -r a
      case "$a" in y | Y | yes) echo; clean ;; esac
    fi ;;
  clean) clean ;;
  junk) junk "${2:-30}" ;;
  list)
    echo "Installed by your modules (\`debloat remove <name>\` drops one everywhere):"
    sort -u /etc/debloat/packages 2>/dev/null | column -c "${COLUMNS:-100}"
    if have flatpak && flatpak list --app --columns=application 2>/dev/null | grep -q .; then
      echo; echo "Flatpak apps (\`debloat remove <id>\` uninstalls one and trims its runtimes):"
      flatpak list --app --columns=application,size 2>/dev/null | sed 's/^/  /'
    fi
    r=$(current)
    if [ -n "$r" ]; then echo; echo "Already removed:"; while read -r x; do echo "  $x"; done <<<"$r"; fi ;;
  remove)
    shift; [ "$#" -gt 0 ] || { echo "usage: debloat remove NAME…"; exit 2; }
    nix_names=()
    for n in "$@"; do
      if is_flatpak_app "$n"; then
        echo ":: uninstalling Flatpak app $n (its data in ~/.var/app/$n is kept) …"
        flatpak uninstall -y --noninteractive "$n" >/dev/null 2>&1 \
          || sudo flatpak uninstall --system -y --noninteractive "$n" >/dev/null 2>&1 \
          || echo "   could not uninstall $n; try: flatpak uninstall $n"
        flatpak_removed=1
        continue
      fi
      [ -r /etc/debloat/packages ] && ! grep -qx "$n" /etc/debloat/packages && echo "note: '$n' isn't something your modules install (see: debloat list)"
      nix_names+=("$n")
    done
    [ -n "${flatpak_removed:-}" ] && trim_flatpak
    [ "${#nix_names[@]}" -gt 0 ] && { current; printf '%s\n' "${nix_names[@]}"; } | setlist
    true ;;
  keep)
    shift; [ "$#" -gt 0 ] || { echo "usage: debloat keep NAME…"; exit 2; }
    { current | grep -vxF -f <(printf '%s\n' "$@") || true; } | setlist ;;
  -h | --help | help) awk '/^# debloat —/ {f = 1} f && /^#/ {sub(/^# ?/, ""); print; next} f {exit}' "$0" ;;
  *) echo "usage: debloat [clean|list|remove NAME…|keep NAME…]"; exit 2 ;;
esac
