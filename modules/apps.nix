# Everyday apps, kept lean: Brave, LibreOffice, a video player, sound and
# network controls. Chat apps, Chromium, music, ebooks, torrents and Onshape
# are the `extras` module (off by default: `mod on extras`).
{ pkgs, ... }:
{
  # Browser: Brave (the default — Super+w, links, BROWSER, web-app windows).
  #   Brave      Chromium with ad and tracker blocking built in (Shields), and
  #              Brave Search, which does !bangs. Its extras are switched off
  #              below: no crypto wallet, Rewards, VPN upsell, AI chat, News,
  #              Talk, Playlist or usage pings. "New Private Window with Tor"
  #              stays. Proton Pass is installed in it, and Brave's own password
  #              saving is off so everything goes to Pass.
  #   Chromium   (extras module) a plain second browser.
  #   Tor Browser: privacy module.
  #
  # Passwords + bookmarks across machines:
  #   Proton Pass — one end-to-end-encrypted vault in Brave and the desktop app.
  #                `browser-sync passwords` adds a browser's own password export
  #                to it (see sync.nix).
  #   Bookmarks  — no live sync service; `browser-sync` exports them to an HTML
  #                file that rides ~/Sync to the other machine and imports back.
  environment.etc."brave/policies/managed/nix2.json".text = builtins.toJSON {
    ExtensionInstallForcelist = [
      "ghmbeldphafepmbegfdlkpapadhbakde;https://clients2.google.com/service/update2/crx"   # Proton Pass
    ];
    PasswordManagerEnabled = false;          # Proton Pass keeps the passwords
    BraveRewardsDisabled = true;
    BraveWalletDisabled = true;
    BraveVPNDisabled = true;
    BraveAIChatEnabled = false;
    BraveNewsDisabled = true;
    BraveTalkDisabled = true;
    BravePlaylistEnabled = false;
    BraveP3AEnabled = false;                 # anonymous usage stats
    BraveStatsPingEnabled = false;
    BraveWebDiscoveryEnabled = false;
  };
  programs.nix-ld.enable = true;   # lets prebuilt/AppImage binaries run
  programs.nix-ld.libraries = with pkgs; [ webkitgtk_4_1 libappindicator-gtk3 librsvg gtk3 openssl ];

  # Office: LibreOffice (Writer, Calc, Impress, Draw, Base, Math) with English
  # spellcheck. The fonts make Word/Excel/PowerPoint files lay out like they
  # do on Windows: Microsoft's core fonts (Arial, Times New Roman…) plus
  # Carlito/Caladea, drop-in matches for Calibri/Cambria.
  fonts.packages = with pkgs; [ corefonts carlito caladea ];

  my.packages = with pkgs; [
    libreoffice-fresh hunspell hunspellDicts.en_US
    brave
    mpv yt-dlp ffmpeg pulsemixer pavucontrol playerctl mediainfo
    networkmanagerapplet lm_sensors
    poppler-utils man-pages xdg-utils trash-cli
  ];
}
