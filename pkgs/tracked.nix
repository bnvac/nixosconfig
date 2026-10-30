# Which git repos this system builds from, and the exact commit each one uses.
# Pure Nix (no nixpkgs needed), so update-mine reads it in a split second:
#   nix-instantiate --eval --strict --json pkgs/tracked.nix
#
# Where it comes from:
#   pins.json          the built-in apps (neb, backoffice, intraweb) — kept in git
#   settings.gitApps   any repo you add, or a fork you point a built-in at
#   pins.local.json    newer commits update-mine found (gitignored, per machine)
# A local pin only counts while it matches the repo/branch you configured and
# was made from the current baseline, so changing settings or pulling a newer
# baseline from git never leaves a stale pin in charge.
let
  s = import ../settings.nix;
  base = builtins.fromJSON (builtins.readFile ./pins.json);
  local =
    if builtins.pathExists ./pins.local.json
    then builtins.fromJSON (builtins.readFile ./pins.local.json) else { };
  apps = s.gitApps or { };

  ghUrl = r: "https://github.com/${r}";
  # "owner/repo" → GitHub; anything containing :// or @ → any git server.
  parse = n: src:
    if builtins.match ".*(://|@).*" src != null then { url = src; github = null; }
    else
      let m = builtins.match "([^/]+)/([^/]+)" src; in
      if m == null
      then throw "gitApps.${n}: repo = \"${src}\" should be \"owner/repo\" (GitHub) or a full git URL"
      else { url = ghUrl src; github = { owner = builtins.elemAt m 0; repo = builtins.elemAt m 1; }; };

  # Hashes besides the source that a build type needs (update-mine fills them).
  extraHashes = { go = [ "vendorHash" ]; node = [ "npmDepsHash" ]; };

  one = n:
    let
      b = base.${n} or null;
      a = apps.${n} or { };
      builtin = b != null;
      spec = a.repo or a.url or (
        if builtin then "${b.owner}/${b.repo}"
        else throw "gitApps.${n}: set repo = \"owner/repo\" or url = \"https://…\"");
      p = parse n spec;
      branch = a.branch or null;
      type = if builtin then "builtin" else a.type or "script";
      baseRev = if builtin then b.rev else null;
      l = local.${n} or null;
      baseOk = builtin && p.url == ghUrl "${b.owner}/${b.repo}" && branch == null;
      localOk = l != null && (l.url or null) == p.url && (l.base or null) == baseRev
        && (l.branch or null) == branch;
    in {
      inherit (p) url github;
      inherit type branch baseRev builtin;
      hashes = if builtin then (if b ? vendorHash then [ "vendorHash" ] else [ ]) else extraHashes.${type} or [ ];
      pin = if localOk then l else if baseOk then b else null;
      attr = if builtin then n else "gitApps.${n}";
    };

  names = builtins.filter (n: (apps.${n}.enable or true)) (builtins.attrNames (base // apps));
in
builtins.listToAttrs (map (n: { name = n; value = one n; }) names)
