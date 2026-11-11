# Which feature modules exist, and which are on. A module is modules/<name>.nix
# (except core). nix²'s defaults: ON when an empty marker file mods/<name>
# exists. Your machine overrides them in settings.local.nix
# (modules.<name> = true/false; `mod on|off` writes it).
# Shared by configuration.nix (to import them) and core.nix (to document them).
lib: rec {
  all = lib.pipe (builtins.readDir ./modules) [
    builtins.attrNames
    (map (lib.removeSuffix ".nix"))
    (builtins.filter (m: m != "core"))
  ];
  byDefault = m: builtins.pathExists (./mods + "/${m}");
  on = builtins.filter (m: (import ./settings.nix).modules.${m} or (byDefault m)) all;
}
