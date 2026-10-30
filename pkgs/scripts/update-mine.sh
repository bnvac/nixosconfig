# update-mine — keep every git-built app on its newest commit, without ever
# leaving the system unbuildable.
#
#   update-mine            pin anything newer that builds (rebuild does this first)
#   update-mine --switch   …and if anything changed, nixos-rebuild switch (daily timer)
#   update-mine --status   show what's pinned vs. what's upstream; change nothing
#
# What it tracks comes from pkgs/tracked.nix: the built-ins (neb, backoffice,
# intraweb — pkgs/pins.json) plus every repo in settings.gitApps, from GitHub
# or any git server, on a branch if you set one. New pins go to
# pkgs/pins.local.json (gitignored, so `nixup` pulls never conflict). For each:
#   1. ask the repo for its latest commit (git ls-remote — no API, no token)
#   2. let Nix work out the new hashes (source, and Go/npm dependencies) by
#      building with a placeholder and reading back the hash it reports
#   3. test-build it. If that fails (say an upstream change broke one of this
#      config's patches) keep the old pin and say why.

dir=${NIXOS_DIR:-/etc/nixos}
localf="$dir/pkgs/pins.local.json"
fake="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
export PATH="$PATH:/run/current-system/sw/bin"

mode=${1:-}
case "$mode" in
  "" | --switch | --status) ;;
  *) echo "usage: update-mine [--switch|--status]"; exit 2 ;;
esac
[ -r "$dir/pkgs/tracked.nix" ] || { echo "update-mine: no $dir/pkgs/tracked.nix"; exit 1; }

# Writing /etc/nixos needs root.
if [ "$mode" != --status ] && [ "$(id -u)" -ne 0 ]; then
  exec /run/wrappers/bin/sudo env "PATH=$PATH" "$0" "$@"
fi
if [ "$mode" != --status ]; then
  exec 9>/run/update-mine.lock
  flock -n 9 || { echo "update-mine: already running"; exit 0; }
fi

nixbuild() { nix-build '<nixpkgs/nixos>' -I nixos-config="$dir/configuration.nix" --no-out-link "$@"; }
readtracked() { nix-instantiate --eval --strict --json "$dir/pkgs/tracked.nix"; }

if ! tracked=$(readtracked 2>&1); then
  echo "update-mine: couldn't read what to track:"; echo "$tracked"; exit 1
fi

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

# Forget local pins for apps that are no longer tracked.
if [ "$mode" != --status ]; then
  for n in $(jq -r 'keys[]' <<<"$localjson"); do
    jq -e --arg n "$n" 'has($n)' <<<"$tracked" >/dev/null || dellocal "$n"
  done
fi

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
# The derivation attribute a hash belongs to.
hashattr() {
  case "$1" in
    hash) echo src ;;
    vendorHash) echo goModules ;;
    npmDepsHash) echo npmDeps ;;
  esac
}

for n in $(jq -r 'keys[]' <<<"$tracked"); do
  t=$(jq -c --arg n "$n" '.[$n]' <<<"$tracked")
  url=$(jq -r .url <<<"$t"); branch=$(jq -r '.branch // empty' <<<"$t")
  attr=$(jq -r .attr <<<"$t"); rev=$(jq -r '.pin.rev // empty' <<<"$t")
  ref=HEAD; [ -n "$branch" ] && ref="refs/heads/$branch"
  latest=$(git ls-remote "$url" "$ref" 2>/dev/null | head -n 1 | cut -f1) || latest=""
  now=${rev:0:7}; now=${now:-none}
  if [ -z "$latest" ]; then echo "  $n: couldn't reach $url${branch:+ ($branch)} — keeping $now"; continue; fi
  if [ "$latest" = "$rev" ]; then echo "  $n: up to date ($now)"; continue; fi
  if [ "$mode" = --status ]; then echo "  $n: $now → ${latest:0:7} available"; continue; fi

  echo "  $n: $now → ${latest:0:7} …"
  prev=$(jq -c --arg n "$n" '.[$n] // null' <<<"$localjson")
  entry=$(jq -c --arg r "$latest" --arg f "$fake" \
    '{url, branch, base: .baseRev, rev: $r, hash: $f} + ([.hashes[] | {(.): $f}] | add // {})' <<<"$t")
  setlocal "$n" "$entry"

  ok=true
  for h in hash $(jq -r '.hashes[]' <<<"$t"); do
    if ! v=$(got "pkgs.$attr.$(hashattr "$h")"); then
      restore "$n" "$prev" "couldn't fetch its $( [ "$h" = hash ] && echo source || echo dependencies )"
      ok=false; break
    fi
    entry=$(jq -c --arg k "$h" --arg v "$v" '.[$k] = $v' <<<"$entry"); setlocal "$n" "$entry"
  done
  $ok || continue

  if ! log=$(nixbuild -A "pkgs.$attr" 2>&1); then
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
