# Options shared between modules (imported by core.nix, so always defined).
{ lib, ... }:
let
  inherit (lib) mkOption types;
  menuItem = types.submodule {
    options = {
      label = mkOption { type = types.str; description = "What the menu shows."; };
      run = mkOption { type = types.str; description = "Shell command, or a URL for mode = url."; };
      mode = mkOption {
        type = types.enum [ "exec" "term" "tty" "url" ];
        default = "exec";
        description = ''
          exec: run it · term: run in a terminal and wait for Enter so you can read
          the output · tty: run a full-screen terminal program · url: open as an app window.
        '';
      };
      needs = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Only show the entry when this command exists.";
      };
    };
  };
in
{
  options.my.syncFolders = mkOption {
    type = types.attrsOf types.str;
    default = { };
    example = { notes = "/home/me/notes"; };
    description = ''
      Folders the `sync` module shares with the other machine (Syncthing id →
      path). Any module can add to it; linking the machines (devlink pin)
      creates and shares every one of them.
    '';
  };

  # nixmenu (Super+Alt+Space): category → entries. Every module adds its own;
  # settings.nix → menu can add/hide/reorder, and ~/.config/nixmenu/menu can
  # too without a rebuild.
  options.my.menu = mkOption {
    type = types.attrsOf (types.listOf menuItem);
    default = { };
    description = "nixmenu categories and their entries.";
  };

  # Web apps this machine serves (name → URL). They make up the menu's
  # Self-hosted section, `dash`, and an app-menu launcher each.
  options.my.selfhosted = mkOption {
    type = types.attrsOf types.str;
    default = { };
    example = { Jellyfin = "http://127.0.0.1:8096"; };
    description = "Self-hosted web apps, name → URL.";
  };

  # Packages the modules install. core.nix turns this into
  # environment.systemPackages minus settings.removePackages, so one list in
  # settings can strip any app out of every module (`debloat remove <name>`).
  options.my.packages = mkOption {
    type = types.listOf types.package;
    default = [ ];
    description = "Packages to install (filtered by settings.removePackages).";
  };
}
