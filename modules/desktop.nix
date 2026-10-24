# LARBS dwm desktop: X11, dwm, dotfile seeding, X utilities, files & drives.
{ pkgs, lib, ... }:
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

  # `drives` — mount / unlock / unmount from dmenu (Super+Alt+m, Super+F9/F10).
  # Nothing ever mounts on its own: you pick the drive. udisks2 does the work as
  # your user (no sudo) under /run/media/<you>/<label>; LUKS drives ask for the
  # passphrase in a dmenu password prompt. The same udisks2 backs Thunar's
  # sidebar, so a drive mounted either way shows up in both.
  drives = pkgs.writeShellScriptBin "drives" ''
    export PATH=${lib.makeBinPath (with pkgs; [ larbs-dmenu udisks util-linux jq libnotify coreutils gawk gnugrep ])}:$PATH
    say() { notify-send -i drive-removable-media "Drives" "$1" 2>/dev/null || echo "$1"; }
    want=''${1:-any}                              # mount | unmount | any

    # one row per actionable device:  ACTION <tab> DEVICE <tab> what dmenu shows
    rows=$(lsblk -Jpo NAME,TYPE,SIZE,LABEL,FSTYPE,MOUNTPOINT | jq -r --arg want "$want" '
      [.blockdevices[] | recurse(.children[]?)][]
      | select(.type != "loop" and .fstype != null and .fstype != "swap")
      | (.label // .fstype) as $what
      | if .fstype == "crypto_LUKS" then
          if ((.children // []) | length) == 0 and $want != "unmount"
          then "unlock\t\(.name)\t🔒 \(.name)  \(.size)  \($what) (locked)" else empty end
        elif .mountpoint == null then
          if $want != "unmount" then "mount\t\(.name)\t💾 \(.name)  \(.size)  \($what)" else empty end
        elif (.mountpoint | startswith("/run/media/")) and $want != "mount" then
          "unmount\t\(.name)\t⏏ \(.mountpoint)  \(.size)"
        else empty end')
    [ -n "$rows" ] || { say "Nothing to $( [ "$want" = any ] && echo "mount or unmount" || echo "$want" )."; exit 0; }

    pick=$(printf '%s\n' "$rows" | cut -f3 | dmenu -i -l 12 -p "drives:") || exit 0
    row=$(printf '%s\n' "$rows" | awk -F'\t' -v p="$pick" '$3 == p { print; exit }')
    [ -n "$row" ] || exit 0
    action=$(printf '%s' "$row" | cut -f1); dev=$(printf '%s' "$row" | cut -f2)

    case "$action" in
      mount)
        out=$(udisksctl mount -b "$dev" 2>&1) && say "$out" || say "Couldn't mount $dev: $out" ;;
      unlock)
        pw=$(dmenu -P -p "Passphrase for $dev:" <&-) || exit 0
        out=$(printf '%s' "$pw" | udisksctl unlock -b "$dev" --key-file /dev/stdin 2>&1); unset pw
        clear=$(printf '%s' "$out" | grep -o '/dev/dm-[0-9]*') || { say "Couldn't unlock $dev: $out"; exit 1; }
        out=$(udisksctl mount -b "$clear" 2>&1) && say "Unlocked. $out" || say "Unlocked, but couldn't mount: $out" ;;
      unmount)
        out=$(udisksctl unmount -b "$dev" 2>&1) || { say "Couldn't unmount $dev: $out (a program may still be using it)"; exit 1; }
        if [ "$(lsblk -no TYPE "$dev")" = crypt ]; then        # was a LUKS drive: lock it again
          backing=$(lsblk -npo PKNAME "$dev")
          udisksctl lock -b "$backing" >/dev/null 2>&1 && out="$out, and locked $backing"
        fi
        say "$out. Safe to unplug." ;;
    esac
  '';

  # `mykeys` — a printable cheat sheet of MY custom keybinds (Super+Alt+F1, and
  # an entry in nixmenu). Stock LARBS keys stay on Super+F1's manual.
  mykeys = pkgs.writeShellScriptBin "mykeys" ''
    cat <<'SHEET'

      MY KEYBINDS   (Super = the key that used to be CapsLock)

      Super + Space          talk to Neb  (listen → answer → speak)
      Super + Alt + Space    nixmenu — the menu of everything below
      Super + Alt + e        file manager (Thunar)
      Super + Alt + m        drives: mount / unlock / unmount
      Super + Alt + d        dashboards
      Super + Alt + b        Bluetooth
      Super + Alt + t        Tor Browser
      Super + Alt + Return   tmux session
      Super + Alt + i        system info (fastfetch)
      Super + Alt + F1       this sheet

      Stock keys I changed:
      Super + e              file manager (it opened neomutt, which is gone)
      Super + F9 / F10       drives: mount / unmount
      Super + r              lf, the terminal file manager (unchanged)

      Everything else is stock LARBS — press Super + F1 for that manual.

    SHEET
  '';

  # `nixmenu` — Super+Alt+Space. A dmenu of this system's own actions. Entries
  # only appear when the command behind them exists (its module is on), so it
  # stays honest as modules come and go. Terminal actions open in st and wait
  # for Enter, so you can read the result before the window closes.
  nixmenu = pkgs.writeShellScriptBin "nixmenu" ''
    export PATH=${lib.makeBinPath [ pkgs.larbs-dmenu pkgs.larbs-st pkgs.coreutils ]}:/run/current-system/sw/bin:$PATH
    have() { command -v "$1" >/dev/null 2>&1; }
    term() { exec st -e sh -c "$1; echo; printf '[enter] '; read -r _"; }
    labels=("Setup / modules (TUI)" "Update system (pull + rebuild)" "Files" "Drives: mount / unmount")
    have dash            && labels+=("Dashboards")
    have devlink-window  && labels+=("DeviceLink (send files)")
    have devlink         && labels+=("Share my screen (VNC)" "View other screen (VNC)")
    have blueman-manager && labels+=("Bluetooth devices")
    have neb             && labels+=("Ask Neb")
    have elegoo-slicer   && labels+=("Elegoo Slicer")
    have tormode         && labels+=("Tor: route everything ON" "Tor: stop routing")
    labels+=("My keybinds" "Suspend")
    sel=$(printf '%s\n' "''${labels[@]}" | dmenu -i -l 16 -p "nix:") || exit 0
    case "$sel" in
      "Setup / modules (TUI)")     term modtui ;;
      Update*)                     term nixup ;;
      Files)                       exec thunar ;;
      Drives*)                     exec drives ;;
      Dashboards)                  exec dash ;;
      DeviceLink*)                 exec devlink-window ;;
      "Share my screen (VNC)")     term "devlink screen" ;;
      "View other screen (VNC)")   exec devlink view ;;
      Bluetooth*)                  exec blueman-manager ;;
      "Ask Neb")                   exec neb hotkey ;;
      "Elegoo Slicer")             exec elegoo-slicer ;;
      "Tor: route everything ON")  term "tormode on" ;;
      "Tor: stop routing")         term "tormode off" ;;
      "My keybinds")               term mykeys ;;
      Suspend)                     exec zzz ;;
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
        ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1 &   # password prompts (drives, etc.)
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
  services.blueman.enable = true;            # Bluetooth GUI (Super+Alt+b)

  # ── files & drives ─────────────────────────────────────────────────────────
  # Thunar is the GUI file manager; lf (Super+r) stays the terminal one. No
  # automounting anywhere (no thunar-volman, no udiskie): click a drive in
  # Thunar's sidebar, or use `drives`. Both go through udisks2 as your user.
  programs.thunar = { enable = true; plugins = [ pkgs.thunar-archive-plugin ]; };
  services.udisks2.enable = true;
  services.gvfs.enable = true;               # Thunar's drive sidebar, trash, phones (MTP/iPhone)
  services.tumbler.enable = true;            # thumbnails
  xdg.mime.defaultApplications."inode/directory" = "thunar.desktop";   # "open folder" → Thunar

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

  environment.systemPackages = [ dash drives nixmenu mykeys ] ++ dashItems ++ (with pkgs; [
    larbs-st larbs-dmenu larbs-dwmblocks larbs-scripts
    xinit xrdb xprop xwininfo xset setxkbmap xbacklight xrandr slop
    xclip xdotool xcape xwallpaper picom unclutter-xfixes maim slock
    dunst libnotify arandr screenkey tesseract wmctrl groff feh imagemagick
    brightnessctl xev lf ueberzugpp zathura nsxiv
    gruvbox-gtk-theme papirus-icon-theme lxappearance
    xarchiver ntfs3g exfatprogs dosfstools   # archives (Thunar plugin) + fs tools for drives
    (writeShellScriptBin "zzz" ''exec systemctl suspend "$@"'')
  ]);
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.gnupg.agent = { enable = true; pinentryPackage = pkgs.pinentry-gtk2; };
  environment.pathsToLink = [ "/share/terminfo" ];
}
