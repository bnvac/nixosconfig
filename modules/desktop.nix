# LARBS dwm desktop: X11, dwm, dotfile seeding, X utilities.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  wallpaper = pkgs.runCommand "wallpaper.png" { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''magick -size 3840x2160 gradient:'#0d1117-#1b2733' -define png:color-type=2 "$out"'';

  # ── self-hosted dashboards (label → URL). Each needs its module on. ─────────
  dashboards = {
    "Neb"        = "http://127.0.0.1:7000";   # assistant
    "Open-WebUI" = "http://127.0.0.1:8088";   # assistant (desktop)
    "Backoffice" = "http://127.0.0.1:8080";   # backoffice (run `backoffice` first)
    "DeviceLink" = "http://127.0.0.1:7010";   # sync
    "Syncthing"  = "http://127.0.0.1:8384";   # sync
    "I2P"        = "http://127.0.0.1:7657";   # privacy
  };
  dashArray = lib.concatStringsSep "\n"
    (lib.mapAttrsToList (k: v: ''  ["${k}"]="${v}"'') dashboards);

  # `dash` — dmenu picker that opens the chosen dashboard as an app window.
  dash = pkgs.writeShellScriptBin "dash" ''
    export PATH=${lib.makeBinPath [ pkgs.larbs-dmenu pkgs.chromium pkgs.coreutils ]}:$PATH
    declare -A D=(
    ${dashArray}
    )
    sel=$(printf '%s\n' "''${!D[@]}" | sort | dmenu -i -p "open dashboard:") || exit 0
    [ -n "''${D[$sel]:-}" ] && exec chromium --app="''${D[$sel]}"
  '';

  # one desktop launcher per dashboard, for any app menu.
  dashItems = lib.mapAttrsToList (name: url: pkgs.makeDesktopItem {
    name = "dash-${lib.toLower name}"; desktopName = "${name} dashboard";
    exec = "${pkgs.chromium}/bin/chromium --app=${url}";
    icon = "web-browser"; categories = [ "Network" ];
  }) dashboards;
in
{
  services.xserver = {
    enable = true;
    xkb = { layout = "us"; options = "caps:super,altwin:menu_win"; };
    windowManager.dwm = {
      enable = true; package = pkgs.larbs-dwm;
      extraSessionCommands = ''
        export _JAVA_AWT_WM_NONREPARENTING=1
        [ -f "$HOME/.config/x11/xresources" ] && ${pkgs.xrdb}/bin/xrdb -merge "$HOME/.config/x11/xresources"
        ${pkgs.larbs-dwmblocks}/bin/dwmblocks &
        ${pkgs.xcompmgr}/bin/xcompmgr &
        ${pkgs.unclutter-xfixes}/bin/unclutter &
        ${pkgs.dunst}/bin/dunst &
        ${pkgs.mpd}/bin/mpd &
        bg="$HOME/.local/share/bg"
        [ -e "$bg" ] || { mkdir -p "$HOME/.local/share"; ln -sfn ${wallpaper} "$bg"; }
        ${pkgs.xwallpaper}/bin/xwallpaper --zoom "$bg" &
        ${pkgs.larbs-scripts}/bin/remaps &
        true
      '';
    };
  };
  services.libinput.enable = true;
  services.displayManager.ly.enable = true;
  hardware.graphics.enable = true;

  environment.variables = {
    TERMINAL = "st"; BROWSER = "firefox"; READER = "zathura"; FILE = "lfub";
    SUDO_ASKPASS = "${pkgs.larbs-scripts}/bin/dmenupass";
  };

  # seed Luke's lf/dunst/mpv/zathura/ncmpcpp/X configs once (never clobbers)
  system.activationScripts.larbsDotfiles = {
    deps = [ "users" ];
    text = ''
      home="/home/${s.username}"; stamp="$home/.local/share/larbs/.seeded"
      if [ -d "$home" ] && [ ! -e "$stamp" ]; then
        mkdir -p "$home/.config" "$home/.local/share/larbs"
        for d in ${pkgs.larbs-scripts}/share/larbs-dotfiles/config/*; do
          case "$(basename "$d")" in nvim|zsh) continue ;; esac
          cp -rn "$d" "$home/.config/" 2>/dev/null || true
        done
        cp -rn ${pkgs.larbs-scripts}/share/larbs/. "$home/.local/share/larbs/" 2>/dev/null || true
        chown -R ${s.username}:users "$home/.config" "$home/.local" 2>/dev/null || true
        touch "$stamp"; chown ${s.username}:users "$stamp" 2>/dev/null || true
      fi
    '';
  };

  environment.systemPackages = [ dash ] ++ dashItems ++ (with pkgs; [
    larbs-st larbs-dmenu larbs-dwmblocks larbs-scripts
    xorg.xinit xrdb xprop xwininfo xset setxkbmap xbacklight xorg.xrandr slop
    xclip xdotool xcape xwallpaper xcompmgr unclutter-xfixes maim slock
    dunst libnotify arandr screenkey tesseract wmctrl groff feh imagemagick
    brightnessctl xev lf ueberzugpp zathura nsxiv
    gruvbox-gtk-theme papirus-icon-theme lxappearance
    (writeShellScriptBin "zzz" ''exec systemctl suspend "$@"'')
  ]);
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.gnupg.agent = { enable = true; pinentryPackage = pkgs.pinentry-gtk2; };
  environment.pathsToLink = [ "/share/terminfo" ];
}
