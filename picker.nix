# Which feature modules exist, and which are on. A module is modules/<name>.nix
# (except core); it's ON when an empty marker file mods/<name> exists.
# Shared by configuration.nix (to import them) and core.nix (to document them).
lib: rec {
  all = lib.pipe (builtins.readDir ./modules) [
    builtins.attrNames
    (map (lib.removeSuffix ".nix"))
    (builtins.filter (m: m != "core"))
  ];
  on = builtins.filter (m: builtins.pathExists (./mods + "/${m}")) all;
}
