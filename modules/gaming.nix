# Steam + Proton-GE, Minecraft (Prism + JDKs), game tooling.
{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    protontricks.enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];   # GE in the compat dropdown
  };
  programs.gamemode.enable = true;
  environment.systemPackages = with pkgs; [
    protonup-qt mangohud winetricks steam-run
    prismlauncher temurin-bin jdk8         # Minecraft; Feather/Fabric via Modrinth
  ];
}
