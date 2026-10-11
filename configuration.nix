# NixOS — samadams.  Everything lives in ./modules; this file only picks them.
#
# A feature module (modules/<name>.nix, except core) is ON when an empty file
# named <name> exists in ./mods. New modules register themselves — no list here.
#   mod list          show every module and whether it's on
#   mod on gaming     enable + rebuild        mod off osint   disable + rebuild
{ lib, ... }:
let
  names = lib.pipe (builtins.readDir ./modules) [
    builtins.attrNames
    (map (lib.removeSuffix ".nix"))
    (builtins.filter (m: m != "core"))
  ];
  isOn = m: builtins.pathExists (./mods + "/${m}");
in
{
  imports = [ ./hardware-configuration.nix ./modules/core.nix ]
    ++ map (m: ./modules + "/${m}.nix") (builtins.filter isOn names);
}
