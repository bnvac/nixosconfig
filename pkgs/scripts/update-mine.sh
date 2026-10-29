# update-mine — move YOUR packages (neb, backoffice, intraweb…) to the newest
# commit on GitHub, without ever leaving the system unbuildable.
#
#   update-mine            pin anything newer that builds (rebuild does this first)
#   update-mine --switch   …and if anything changed, nixos-rebuild switch (daily timer)
#   update-mine --status   show what's pinned vs. what's on GitHub; change nothing
#
# The packages are the entries in /etc/nixos/pkgs/pins.json (the baseline kept
# in git). New pins go to pkgs/pins.local.json, which is gitignored, so `nixup`
# pulls never conflict with them. For each package:
#   1. ask GitHub for the latest commit (git ls-remote: no API, no token)
#   2. let Nix work out the new source hash (and Go vendorHash) by building
#      with a placeholder and reading back the hash it reports
#   3. test-build the package. If it fails (say an upstream change broke one
#      of this config's patches) keep the old pin and say why.

dir=${NIXOS_DIR:-/etc/nixos}
base="$dir/pkgs/pins.json"
localf="$dir/pkgs/pins.local.json"
fake="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
export PATH="$PATH:/run/current-system/sw/bin"

mode=${1:-}
case "$mode" in
  "" | --switch | --status) ;;
  *) echo "usage: update-mine [--switch|--status]"; exit 2 ;;
esac
[ -r "$base" ] || { echo "update-mine: no $base"; exit 1; }

# Writing /etc/nixos needs root.
if [ "$mode" != --status ] && [ "$(id -u)" -ne 0 ]; then
  exec /run/wrappers/bin/sudo "$0" "$@"
fi
if [ "$mode" != --status ]; then
  exec 9>/run/update-mine.lock
  flock -n 9 || { echo "update-mine: already running"; exit 0; }
fi

nixbuild() { nix-build '<nixpkgs/nixos>' -I nixos-config="$dir/configuration.nix" --no-out-link "$@"; }

localjson='{}'
if [ -s "$localf" ] && jq -e 'type == "object"' "$localf" >/dev/null 2>&1; then
  localjson=$(cat "$localf")
fi

savelocal() {
  local tmp
  tmp=$(mktemp "$dir/pkgs/.pins.XXXXXX")
  printf '%s\n' "$localjson" >"$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$localf"
}
setlocal() { localjson=$(jq --arg n "$1" --argjson e "$2" '.[$n] = $e' <<<"$localjson"); savelocal; }
dellocal() { localjson=$(jq --arg n "$1" 'del(.[$n])' <<<"$localjson"); savelocal; }

# The pin Nix actually uses: the local one only if it was made from the
# current baseline (same rule as pkgs/default.nix).
eff() {
  jq -r --arg n "$1" --arg f "$2" --argjson l "$localjson" '
    .[$n] as $b | ($l[$n] // null) as $o
    | (if $o != null and ($o.base // null) == $b.rev then $b + $o else $b end)[$f] // empty' "$base"
}

# Build ATTR with a placeholder hash and print the real hash Nix reports.
got() {
  local out h
  if out=$(nixbuild -A "$1" 2>&1); then return 1; fi
  h=$(grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' <<<"$out" | tail -n 1 | awk '{print $2}') || true
  if [ -z "$h" ]; then tail -n 8 <<<"$out" >&2; return 1; fi
  echo "$h"
}

changed=()
failed=()

restore() {    # NAME PREVIOUS-LOCAL-ENTRY REASON
  if [ "$2" = null ]; then dellocal "$1"; else setlocal "$1" "$2"; fi
  echo "  $1: kept the old version — $3."
  failed+=("$1")
}

for n in $(jq -r 'keys[]' "$base"); do
  brev=$(jq -r --arg n "$n" '.[$n].rev' "$base")
  # Drop a local pin made from an older baseline (git now has a newer one).
  if [ "$mode" != --status ] && [ "$(jq -r --arg n "$n" '.[$n].base // empty' <<<"$localjson")" != "" ] \
     && [ "$(jq -r --arg n "$n" '.[$n].base' <<<"$localjson")" != "$brev" ]; then
    dellocal "$n"
  fi
  owner=$(eff "$n" owner); repo=$(eff "$n" repo); rev=$(eff "$n" rev)
  latest=$(git ls-remote "https://github.com/$owner/$repo" HEAD 2>/dev/null | cut -f1) || latest=""
  if [ -z "$latest" ]; then echo "  $n: couldn't reach GitHub — keeping ${rev:0:7}"; continue; fi
  if [ "$latest" = "$rev" ]; then echo "  $n: up to date (${rev:0:7})"; continue; fi
  if [ "$mode" = --status ]; then echo "  $n: ${rev:0:7} → ${latest:0:7} available"; continue; fi

  echo "  $n: ${rev:0:7} → ${latest:0:7} …"
  prev=$(jq -c --arg n "$n" '.[$n] // null' <<<"$localjson")
  entry=$(jq -nc --arg b "$brev" --arg r "$latest" --arg f "$fake" '{base: $b, rev: $r, hash: $f}')
  govendor=$(jq -r --arg n "$n" '.[$n] | has("vendorHash")' "$base")
  [ "$govendor" = true ] && entry=$(jq -c --arg f "$fake" '.vendorHash = $f' <<<"$entry")
  setlocal "$n" "$entry"

  if ! h=$(got "pkgs.$n.src"); then restore "$n" "$prev" "couldn't fetch the new source"; continue; fi
  entry=$(jq -c --arg h "$h" '.hash = $h' <<<"$entry"); setlocal "$n" "$entry"

  if [ "$govendor" = true ]; then
    if ! vh=$(got "pkgs.$n.goModules"); then restore "$n" "$prev" "couldn't fetch its Go modules"; continue; fi
    entry=$(jq -c --arg h "$vh" '.vendorHash = $h' <<<"$entry"); setlocal "$n" "$entry"
  fi

  if ! log=$(nixbuild -A "pkgs.$n" 2>&1); then
    tail -n 15 <<<"$log"
    restore "$n" "$prev" "the new commit doesn't build (log above)"
    continue
  fi
  echo "  $n: updated to ${latest:0:7}"
  changed+=("$n")
done

[ "$mode" = --status ] && exit 0
if [ ${#changed[@]} -eq 0 ]; then
  echo "update-mine: nothing new to switch to."
else
  echo "update-mine: updated ${changed[*]}"
  if [ "$mode" = --switch ]; then nixos-rebuild switch; fi
fi
[ ${#failed[@]} -eq 0 ]
