# NixOS — samadams.  Everything lives in ./modules; this file only picks them.
#
# A feature module (modules/<name>.nix, except core) is ON when an empty file
# named <name> exists in ./mods. New modules register themselves — no list here.
#   mod list          show every module and whether it's on
#   mod on gaming     enable + rebuild        mod off osint   disable + rebuild
#   modtui            the same, plus onboarding / settings / AI model, as a TUI
{ lib, ... }:
{
  imports = [ ./hardware-configuration.nix ./modules/core.nix ]
    ++ map (m: ./modules + "/${m}.nix") (import ./picker.nix lib).on;
}
