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
{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    protontricks.enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];   # GE in the compat dropdown
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
  };
  programs.gamescope = { enable = true; capSysNice = true; };
  programs.gamemode.enable = true;

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
