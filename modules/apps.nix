# Everyday apps: browsers, comms, media, torrents, device tooling, Onshape.
{ pkgs, ... }:
let
  onshape = pkgs.makeDesktopItem {
    name = "onshape"; desktopName = "Onshape";
    exec = "${pkgs.chromium}/bin/chromium --app=https://cad.onshape.com/documents";
    icon = "applications-engineering"; categories = [ "Engineering" ];
  };
in
{
  programs.firefox.enable = true;
  programs.nix-ld.enable = true;   # lets prebuilt/AppImage binaries run
  programs.nix-ld.libraries = with pkgs; [ webkitgtk_4_1 libappindicator-gtk3 librsvg gtk3 openssl ];
  services.usbmuxd.enable = true;  # iPhone/iPad over USB

  environment.systemPackages = with pkgs; [
    onshape
    chromium discord slack
    mpv ani-cli yt-dlp ffmpeg mpd mpc ncmpcpp pulsemixer pavucontrol playerctl mediainfo
    newsboat abook calcurse sc-im
    qbittorrent                              # FOSS torrent client
    usbmuxd libimobiledevice balena-cli appimage-run flatpak
    nodejs
    networkmanagerapplet lm_sensors ntfs3g exfatprogs dosfstools simple-mtpfs
    poppler-utils man-pages xdg-utils trash-cli lynx
  ];
}
