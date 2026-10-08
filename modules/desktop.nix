# LARBS dwm desktop: X11, dwm, dotfile seeding, X utilities.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  wallpaper = pkgs.runCommand "wallpaper.png" { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''magick -size 3840x2160 gradient:'#0d1117-#1b2733' -define png:color-type=2 "$out"'';
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
    TERMINAL = "st"; BROWSER = "chromium"; READER = "zathura"; FILE = "lfub";
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

  environment.systemPackages = with pkgs; [
    larbs-st larbs-dmenu larbs-dwmblocks larbs-scripts
    xorg.xinit xrdb xprop xwininfo xset setxkbmap xbacklight xorg.xrandr slop
    xclip xdotool xcape xwallpaper xcompmgr unclutter-xfixes maim slock
    dunst libnotify arandr screenkey tesseract wmctrl groff feh imagemagick
    brightnessctl xev lf ueberzugpp zathura nsxiv
    gruvbox-gtk-theme papirus-icon-theme lxappearance
    (writeShellScriptBin "zzz" ''exec systemctl suspend "$@"'')
  ];
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.gnupg.agent = { enable = true; pinentryPackage = pkgs.pinentry-gtk2; };
  environment.pathsToLink = [ "/share/terminfo" ];
}
