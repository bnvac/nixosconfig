# update-mine — keep every git-built app on its newest commit, without ever
# leaving the system unbuildable.
#
#   update-mine            pin anything newer that builds (rebuild does this first)
#   update-mine --switch   …and if anything changed, nixos-rebuild switch (daily timer)
#   update-mine --status   show what's pinned vs. what's upstream; change nothing
#
# Apps released as a file instead (pkgs/releases.json: the Claude desktop
# app) move to each new release the same way: checksum, test-build,
# or hold back.
#
# What it tracks comes from pkgs/tracked.nix: the built-ins (neb, backoffice,
# intraweb, slowtyper — pkgs/pins.json) plus every repo in settings.gitApps, from GitHub
# or any git server, on a branch if you set one. New pins go to
# pkgs/pins.local.json (gitignored, so `menu update` pulls never conflict). For each:
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

# Build one attribute of this config's package set. Evaluates nixpkgs + this
# overlay only (not all of NixOS): the same derivations the real rebuild
# uses — so its test builds are reused — in a fraction of the time.
nixbuild() {
  nix-build --no-out-link --argstr attr "$1" -E '{ attr }: let
      p = import <nixpkgs> {
        overlays = [ (import '"$dir"'/pkgs) ];
        config = { allowUnfree = true; allowInsecurePredicate = _: true; };
      };
    in p.lib.getAttrFromPath (p.lib.splitString "." attr) p'
}
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
  if out=$(nixbuild "$1" 2>&1); then return 1; fi
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

# Ask every repo for its latest commit at once (one slow network round each,
# in parallel instead of one after another).
heads=$(mktemp -d)
trap 'rm -rf "$heads"' EXIT
for n in $(jq -r 'keys[]' <<<"$tracked"); do
  (
    url=$(jq -r --arg n "$n" '.[$n].url' <<<"$tracked")
    branch=$(jq -r --arg n "$n" '.[$n].branch // empty' <<<"$tracked")
    ref=HEAD; [ -n "$branch" ] && ref="refs/heads/$branch"
    git ls-remote "$url" "$ref" 2>/dev/null | head -n 1 | cut -f1 >"$heads/$n" || true
  ) &
done
wait

for n in $(jq -r 'keys[]' <<<"$tracked"); do
  t=$(jq -c --arg n "$n" '.[$n]' <<<"$tracked")
  url=$(jq -r .url <<<"$t"); branch=$(jq -r '.branch // empty' <<<"$t")
  attr=$(jq -r .attr <<<"$t"); rev=$(jq -r '.pin.rev // empty' <<<"$t")
  latest=$(cat "$heads/$n" 2>/dev/null) || latest=""
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
    if ! v=$(got "$attr.$(hashattr "$h")"); then
      restore "$n" "$prev" "couldn't fetch its $( [ "$h" = hash ] && echo source || echo dependencies )"
      ok=false; break
    fi
    entry=$(jq -c --arg k "$h" --arg v "$v" '.[$k] = $v' <<<"$entry"); setlocal "$n" "$entry"
  done
  $ok || continue

  if ! log=$(nixbuild "$attr" 2>&1); then
    tail -n 15 <<<"$log"
    restore "$n" "$prev" "the new commit doesn't build (log above)"
    continue
  fi
  echo "  $n: updated to ${latest:0:7}"
  changed+=("$n")
done

# ── Apps released as a file (pkgs/releases.json — the Claude desktop app) ───
# Newest version: a GitHub release tag (git ls-remote again: no API, no token)
# or an apt repository's index → its checksum → test-build. A release that
# doesn't download or build is held back.
rlocalf="$dir/pkgs/releases.local.json"
if [ -r "$dir/pkgs/releases.nix" ] && releases=$(nix-instantiate --eval --strict --json "$dir/pkgs/releases.nix" 2>/dev/null); then
  rlocal='{}'
  if [ -s "$rlocalf" ] && jq -e 'type == "object"' "$rlocalf" >/dev/null 2>&1; then rlocal=$(cat "$rlocalf"); fi
  saverlocal() {
    local tmp
    tmp=$(mktemp "$dir/pkgs/.pins.XXXXXX")
    printf '%s\n' "$rlocal" >"$tmp"; chmod 644 "$tmp"; mv "$tmp" "$rlocalf"
  }
  for n in $(jq -r 'keys[]' <<<"$releases"); do
    r=$(jq -c --arg n "$n" '.[$n]' <<<"$releases")
    repo=$(jq -r '.repo // empty' <<<"$r"); index=$(jq -r '.index // empty' <<<"$r")
    pkg=$(jq -r .package <<<"$r"); have=$(jq -r .version <<<"$r")
    latest=""; sha=""
    if [ -n "$index" ]; then
      # An apt repository: its index lists every version with its SHA256.
      line=$(curl -fsSL --max-time 60 "$index" 2>/dev/null | awk -v p="$pkg" '
        /^Package:/ { cur = $2 } /^Version:/ { v = $2 }
        /^SHA256:/ && cur == p { print v, $2 }' | sort -V | tail -n 1)
      latest=${line%% *}; sha=${line#* }
      where=$index
    else
      latest=$(git ls-remote --tags --refs "https://github.com/$repo" 2>/dev/null \
        | sed 's|.*refs/tags/||' | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -V | tail -n 1)
      where="github.com/$repo"
    fi
    if [ -z "$latest" ]; then echo "  $n: couldn't reach $where — keeping $have"; continue; fi
    if [ "$(printf '%s\n%s\n' "$have" "$latest" | sort -V | tail -n 1)" = "$have" ]; then
      echo "  $n: up to date ($have)"; continue
    fi
    if [ "$mode" = --status ]; then echo "  $n: $have → $latest available"; continue; fi

    echo "  $n: $have → $latest …"
    template=$(jq -r .urlTemplate <<<"$r")
    url=${template//\{version\}/$latest}
    # The apt index already gave the checksum; for a GitHub release, Nix
    # downloads it once to work it out (the test build below reuses that).
    if [ -z "$sha" ] && { ! sha=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null) || [ -z "$sha" ]; }; then
      echo "  $n: kept $have — couldn't download $latest"; failed+=("$n"); continue
    fi
    prev=$(jq -c --arg n "$n" '.[$n] // null' <<<"$rlocal")
    rlocal=$(jq --arg n "$n" --arg v "$latest" --arg s "$sha" --arg b "$(jq -r .baseVersion <<<"$r")" \
      '.[$n] = {version: $v, sha256: $s, base: $b}' <<<"$rlocal"); saverlocal
    if ! log=$(nixbuild "$n" 2>&1); then
      tail -n 15 <<<"$log"
      if [ "$prev" = null ]; then rlocal=$(jq --arg n "$n" 'del(.[$n])' <<<"$rlocal")
      else rlocal=$(jq --arg n "$n" --argjson e "$prev" '.[$n] = $e' <<<"$rlocal"); fi
      saverlocal
      echo "  $n: kept $have — $latest doesn't build (log above)"; failed+=("$n"); continue
    fi
    echo "  $n: updated to $latest"
    changed+=("$n")
  done
fi

[ "$mode" = --status ] && exit 0
if [ ${#changed[@]} -eq 0 ]; then
  echo "update-mine: nothing new to switch to."
else
  echo "update-mine: updated ${changed[*]}"
  if [ "$mode" = --switch ]; then nixos-rebuild switch; fi
fi
[ ${#failed[@]} -eq 0 ]
