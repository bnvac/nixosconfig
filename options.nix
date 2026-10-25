# Options shared between modules (imported by core.nix, so always defined).
{ lib, ... }:
{
  options.my.syncFolders = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = { notes = "/home/me/notes"; };
    description = ''
      Folders the `sync` module shares with the other machine (Syncthing id →
      path). Any module can add to it; linking the machines (devlink pin)
      creates and shares every one of them.
    '';
  };
}
