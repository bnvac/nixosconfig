# Steam (native) + Proton-GE, Minecraft (Prism + JDKs), game tooling.
#
# Steam is the nixpkgs build (not Flatpak): 32-bit graphics, controller rules
# and the larger memory-map limit some games need come with programs.steam.
# On top of that:
#   - Steam Play is switched on for every title at login (steam-setup), so
#     Windows-only games — and Wallpaper Engine — install and run directly.
#   - Proton-GE is in each game's compatibility dropdown.
#   - gamemode + gamescope (and a "Steam Big Picture" session at the login
#     screen) for smoother frame pacing; Remote Play and LAN game transfers
#     are let through the firewall.
#   - NTSYNC is loaded: newer Proton (10+, GE) uses it for faster, more
#     Windows-accurate syncing — fewer stutters and hangs in some games.
#   - Xbox controllers work over Bluetooth (xpadneo: proper buttons, rumble,
#     battery) and with the Xbox Wireless Adapter dongle (xone).
{ config, pkgs, lib, ... }:
{
  programs.steam = {
    enable = true;
    protontricks.enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];   # GE in the compat dropdown
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
  };
  # No capSysNice: it swaps gamescope for a privileged wrapper, which Steam's
  # sandbox can't start — "gamescope %command%" in a game's launch options
  # then just fails. Plain gamescope works everywhere.
  programs.gamescope.enable = true;
  programs.gamemode.enable = true;
  # When a game starts (gamemode sets the CPU to performance itself):
  # notifications wait, the live wallpaper freezes and the snow stops, so the
  # GPU is all the game's. Everything comes back as it was when you quit.
  # Steam: add `gamemoderun %command%` to a game's launch options.
  programs.gamemode.settings.custom = {
    start = "${pkgs.hearth}/bin/hearth game start";
    end = "${pkgs.hearth}/bin/hearth game end";
  };
  # /dev/ntsync (built into the zen kernel; the kernel makes it usable by
  # everyone). Only asked for on kernels that have it (6.14+).
  boot.kernelModules = lib.mkIf (lib.versionAtLeast config.boot.kernelPackages.kernel.version "6.14") [ "ntsync" ];
  hardware.xpadneo.enable = true;             # Xbox controllers over Bluetooth
  hardware.xone.enable = true;                # Xbox Wireless Adapter + wired Xbox controllers

  # Steam Play for all titles (only while Steam is closed; keeps a backup,
  # never overrides a tool you already chose). `steam-setup` runs it by hand.
  systemd.user.services.steam-setup = {
    description = "Turn on Steam Play (Proton) for all titles";
    wantedBy = [ "default.target" ];
    path = [ pkgs.procps ];
    serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.steam-setup}/bin/steam-setup"; };
  };

  my.menu."Games" = [
    { label = "Steam"; run = "steam"; }
    { label = "Steam: play Windows games (Steam Play setup)"; run = "steam-setup"; mode = "term"; }
    { label = "Minecraft (Prism Launcher)"; run = "prismlauncher"; }
    { label = "Proton versions (ProtonUp-Qt)"; run = "protonup-qt"; }
  ];

  my.packages = with pkgs; [
    steam-setup
    protonup-qt mangohud winetricks steam-run
    prismlauncher temurin-bin jdk8         # Minecraft; Feather/Fabric via Modrinth
  ];
}
