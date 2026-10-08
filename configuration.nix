# NixOS — samadams.  Everything lives in ./modules; this file only picks them.
#
# A module is ON when an empty file with its name exists in ./mods.
#   mod list          show every module and whether it is on
#   mod on gaming     enable + rebuild        mod off osint   disable + rebuild
# Off modules stay fully configured in ./modules — they just aren't built.
{ ... }:
let
  optional = [ "desktop" "apps" "ai" "ee" "gaming" "privacy" "virt" "osint" "backoffice" ];
  isOn = m: builtins.pathExists (./mods + "/${m}");
in
{
  imports = [ ./hardware-configuration.nix ./modules/core.nix ]
    ++ map (m: ./modules + "/${m}.nix") (builtins.filter isOn optional);
}
