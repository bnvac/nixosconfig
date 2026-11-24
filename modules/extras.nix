# The bigger everyday apps, off by default to keep the system lean
# (`mod on extras`): chat, a second browser, music, ebooks, torrents, phones.
{ pkgs, ... }:
let
  onshape = pkgs.makeDesktopItem {
    name = "onshape"; desktopName = "Onshape";
    exec = "${pkgs.brave}/bin/brave --app=https://cad.onshape.com/documents";
    icon = "applications-engineering"; categories = [ "Engineering" ];
  };
in
{
  services.usbmuxd.enable = true;  # iPhone/iPad over USB
  my.packages = with pkgs; [
    chromium discord slack                   # Chromium: a plain second browser
    onshape                                  # CAD in the browser
    ani-cli mpd mpc ncmpcpp
    cider-2                                  # Apple Music desktop client
    newsboat abook calcurse sc-im
    calibre                                  # ebook library / reader / converter
    qbittorrent                              # FOSS torrent client
    stremio-linux-shell                      # "Netflix for torrents": poster grid,
                                             # streams via addons (Torrentio in-app)
    libimobiledevice balena-cli              # iPhones over USB; flashing Pi images
  ];
}
