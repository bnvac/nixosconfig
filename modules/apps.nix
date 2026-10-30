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
  # Passwords + bookmarks across browsers AND machines:
  #   Bitwarden  — one end-to-end-encrypted vault in Firefox, Chromium and the
  #                desktop app; sign in once per browser. It's also where your
  #                browser-saved passwords go: `browser-sync passwords` pushes
  #                each browser's own password export into it (see sync.nix).
  #   Bookmarks  — no live sync service; `browser-sync` exports them to an HTML
  #                file that rides ~/Sync to the other machine and imports back.
  # (Firefox's own Sync also works for Firefox-to-Firefox, if you prefer it.)
  programs.firefox = {
    enable = true;
    policies.ExtensionSettings = {
      "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {          # Bitwarden
        installation_mode = "normal_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
      };
    };
  };
  programs.chromium = {                                     # policies only; the browser is below
    enable = true;
    extensions = [
      "nngceckbapebfimnlniiiahkandclblb"                    # Bitwarden
    ];
  };
  programs.nix-ld.enable = true;   # lets prebuilt/AppImage binaries run
  programs.nix-ld.libraries = with pkgs; [ webkitgtk_4_1 libappindicator-gtk3 librsvg gtk3 openssl ];
  services.usbmuxd.enable = true;  # iPhone/iPad over USB

  # Office: LibreOffice (Writer, Calc, Impress, Draw, Base, Math) with English
  # spellcheck. The fonts make Word/Excel/PowerPoint files lay out like they
  # do on Windows: Microsoft's core fonts (Arial, Times New Roman…) plus
  # Carlito/Caladea, drop-in matches for Calibri/Cambria.
  fonts.packages = with pkgs; [ corefonts carlito caladea ];

  my.packages = with pkgs; [
    libreoffice-fresh hunspell hunspellDicts.en_US
    onshape
    chromium discord slack
    mpv ani-cli yt-dlp ffmpeg mpd mpc ncmpcpp pulsemixer pavucontrol playerctl mediainfo
    cider-2                                  # Apple Music desktop client
    newsboat abook calcurse sc-im
    calibre                                  # ebook library / reader / converter
    qbittorrent                              # FOSS torrent client
    stremio-linux-shell                      # "Netflix for torrents": browse a
                                             # poster grid, click to stream via
                                             # addons (install Torrentio in-app).
                                             # Simpler classic alternative: popcorntime
    libimobiledevice balena-cli appimage-run flatpak   # (usbmuxd comes with its service)
    nodejs
    networkmanagerapplet lm_sensors
    poppler-utils man-pages xdg-utils trash-cli lynx
  ];
}
