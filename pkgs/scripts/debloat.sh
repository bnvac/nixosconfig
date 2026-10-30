# debloat — see what takes space, free it, and drop apps you don't use.
#
#   debloat               what's using space (asks to clean when run in a terminal)
#   debloat clean         free space now: old system versions (keeps the last 5),
#                         unused store paths, safe caches, old logs, unused
#                         Docker images and Flatpak runtimes
#   debloat list          the app names you can remove
#   debloat remove NAME…  stop installing these, in EVERY module (settings.nix →
#                         removePackages), then `rebuild --no-update`
#   debloat keep NAME…    undo a remove
#
# Removing an app also drops whatever it alone depended on at the next
# `debloat clean`. Nothing here deletes your own files.

dir=${NIXOS_DIR:-/etc/nixos}
settings="$dir/settings.nix"
export PATH="$PATH:/run/current-system/sw/bin:/run/wrappers/bin"

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

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
  if have docker && systemctl is-active --quiet docker.service 2>/dev/null; then
    echo "  docker:"; docker system df 2>/dev/null | sed 's/^/    /'
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
    echo ":: unused Flatpak runtimes …"
    flatpak uninstall --unused -y >/dev/null 2>&1 || true
  fi
  # The boot menu still lists the versions just deleted — refresh it.
  sudo /run/current-system/bin/switch-to-configuration boot >/dev/null 2>&1 || true
  after=$(df -B1 --output=avail / | tail -n 1)
  echo "Freed $(human "$(( after > before ? after - before : 0 ))")."
}

# The removePackages = [ … ]; line in settings.nix, as one name per line.
current() { grep -E '^\s*removePackages\s*=' "$settings" | grep -oE '"[^"]+"' | tr -d '"' || true; }
setlist() {
  local items line
  items=$(sort -u | awk 'NF {printf " \"%s\"", $0}')
  line="  removePackages = [${items} ];"
  if grep -qE '^\s*removePackages\s*=' "$settings"; then
    sudo sed -i -E "s|^\s*removePackages\s*=.*|${line}|" "$settings"
  else
    sudo sed -i -E "s|^\}\s*$|${line}\n}|" "$settings"
  fi
  echo "settings.nix: removePackages = [${items} ];"
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
  list)
    echo "Installed by your modules (\`debloat remove <name>\` drops one everywhere):"
    sort -u /etc/debloat/packages 2>/dev/null | column -c "${COLUMNS:-100}"
    r=$(current)
    if [ -n "$r" ]; then echo; echo "Already removed:"; while read -r x; do echo "  $x"; done <<<"$r"; fi ;;
  remove)
    shift; [ "$#" -gt 0 ] || { echo "usage: debloat remove NAME…"; exit 2; }
    for n in "$@"; do
      [ -r /etc/debloat/packages ] && ! grep -qx "$n" /etc/debloat/packages && echo "note: '$n' isn't something your modules install (see: debloat list)"
    done
    { current; printf '%s\n' "$@"; } | setlist ;;
  keep)
    shift; [ "$#" -gt 0 ] || { echo "usage: debloat keep NAME…"; exit 2; }
    { current | grep -vxF -f <(printf '%s\n' "$@") || true; } | setlist ;;
  -h | --help | help) awk '/^# debloat —/ {f = 1} f && /^#/ {sub(/^# ?/, ""); print; next} f {exit}' "$0" ;;
  *) echo "usage: debloat [clean|list|remove NAME…|keep NAME…]"; exit 2 ;;
esac
