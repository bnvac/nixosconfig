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

  # `mykeys` — a printable cheat sheet of MY custom keybinds (Super+Alt+F1, and
  # an entry in nixmenu). Stock LARBS keys stay on Super+F1's manual.
  mykeys = pkgs.writeShellScriptBin "mykeys" ''
    cat <<'SHEET'

      MY KEYBINDS   (Super = the key that used to be CapsLock)

      Super + Space          talk to Neb  (listen → answer → speak)
      Super + Alt + Space    nixmenu — the menu of everything below
      Super + Alt + d        dashboards (dash)
      Super + Alt + b        Bluetooth manager
      Super + Alt + t        Tor Browser
      Super + Alt + Return    tmux session
      Super + Alt + i        system info (fastfetch)
      Super + Alt + F1       this sheet

      Everything else is stock LARBS — press Super + F1 for that manual.

    SHEET
  '';

  # `nixmenu` — Super+Alt+Space. A dmenu of this system's own actions. Entries
  # only appear when the command behind them exists (its module is on), so it
  # stays honest as modules come and go. Terminal actions open in st.
  nixmenu = pkgs.writeShellScriptBin "nixmenu" ''
    export PATH=${lib.makeBinPath [ pkgs.larbs-dmenu pkgs.larbs-st pkgs.coreutils ]}:/run/current-system/sw/bin:$PATH
    have() { command -v "$1" >/dev/null 2>&1; }
    labels=()
    labels+=("Setup / modules (TUI)")
    labels+=("Update system (pull + rebuild)")
    have dash            && labels+=("Dashboards")
    have devlink-window  && labels+=("DeviceLink (send files)")
    have devlink         && labels+=("Share my screen (VNC)")
    have devlink         && labels+=("View other screen (VNC)")
    have blueman-manager && labels+=("Bluetooth devices")
    have neb             && labels+=("Ask Neb")
    have elegoo-slicer   && labels+=("Elegoo Slicer")
    have tormode         && labels+=("Tor: route everything ON")
    have tormode         && labels+=("Tor: stop routing")
    labels+=("My keybinds")
    labels+=("Suspend")
    sel=$(printf '%s\n' "''${labels[@]}" | dmenu -i -l 14 -p "nix:") || exit 0
    case "$sel" in
      "Setup / modules (TUI)")      exec st -e modtui ;;
      Update*)                      exec st -e nixup ;;
      Dashboards)                   exec dash ;;
      DeviceLink*)                  exec devlink-window ;;
      "Share my screen (VNC)")      exec st -e sh -c 'devlink screen; echo; read -p "[enter] " _' ;;
      "View other screen (VNC)")    exec devlink view ;;
      Bluetooth*)                   exec blueman-manager ;;
      "Ask Neb")                    exec neb hotkey ;;
      "Elegoo Slicer")              exec elegoo-slicer ;;
      "Tor: route everything ON")   exec st -e sh -c 'tormode on;  echo; read -p "[enter] " _' ;;
      "Tor: stop routing")          exec st -e sh -c 'tormode off; echo; read -p "[enter] " _' ;;
      "My keybinds")                exec st -e sh -c 'mykeys; read -p "[enter] " _' ;;
      Suspend)                      exec zzz ;;
    esac
  '';

  # Compositor config. Terminals (class St) are translucent, but ANY fullscreen
  # window is forced fully opaque — rules match top-to-bottom and the last match
  # wins, so the fullscreen rule overrides the terminal rule when you Super+f a
  # terminal. (picom v13 `rules` syntax; `fullscreen` is a built-in condition.)
  picomConf = pkgs.writeText "picom.conf" ''
    backend = "glx";
    vsync = true;
    rules = (
      { match = "class_g = 'St'"; opacity = ${s.termOpacity}; },
      { match = "fullscreen";     opacity = 1.0; }
    );
  '';
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
        ${pkgs.picom}/bin/picom --config ${picomConf} &
        ${pkgs.unclutter-xfixes}/bin/unclutter &
        ${pkgs.dunst}/bin/dunst &
        ${pkgs.blueman}/bin/blueman-applet &
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

  environment.systemPackages = [ dash nixmenu mykeys ] ++ dashItems ++ (with pkgs; [
    larbs-st larbs-dmenu larbs-dwmblocks larbs-scripts
    xorg.xinit xrdb xprop xwininfo xset setxkbmap xbacklight xorg.xrandr slop
    xclip xdotool xcape xwallpaper picom unclutter-xfixes maim slock
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
