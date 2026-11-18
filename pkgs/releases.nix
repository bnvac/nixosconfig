# Apps that come as a released file on GitHub (an AppImage, say) rather than
# built from a commit. Pure Nix, like tracked.nix, so update-mine reads it fast:
#   nix-instantiate --eval --strict --json pkgs/releases.nix
#
#   releases.json        the version each one ships with — kept in git
#   releases.local.json  newer releases update-mine found and test-built
#                        (gitignored, per machine). One counts only while it's
#                        newer than the version in git, so pulling a newer
#                        baseline never leaves an older local pin in charge.
let
  base = builtins.fromJSON (builtins.readFile ./releases.json);
  local =
    if builtins.pathExists ./releases.local.json
    then builtins.fromJSON (builtins.readFile ./releases.local.json) else { };
  replace = v: builtins.replaceStrings [ "{version}" ] [ v ];
  one = n:
    let
      b = base.${n};
      l = local.${n} or null;
      useLocal = l != null && (l.base or null) == b.version
        && builtins.compareVersions l.version b.version > 0;
      p = if useLocal then l else b;
    in {
      inherit (b) repo asset;
      inherit (p) version sha256;
      baseVersion = b.version;
      url = "https://github.com/${b.repo}/releases/download/${p.version}/${replace p.version b.asset}";
    };
in
builtins.listToAttrs (map (n: { name = n; value = one n; }) (builtins.attrNames base))
