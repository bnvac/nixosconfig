# LARBS dwm desktop: X11, dwm, dotfile seeding, X utilities, files & drives.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  clipForget = s.clipboardForgetMinutes or 30;   # minutes; 0 = never
  wallpaper = pkgs.snow-wallpaper;          # snowy night, drawn at build time (pkgs/scripts)
  kbLayout = s.keyboardLayout or "us";
  kbVariant = s.keyboardVariant or "";

  # `dash` (Super+Alt+d) — straight into the menu's Self-hosted section.
  dash = pkgs.writeShellScriptBin "dash" ''exec ${pkgs.nixmenu}/bin/nixmenu "Self-hosted"'';

  # Your home server's services in this machine's menu (settings.homelabServer).
  # The server (homelab module) publishes them at http://<server>/services.json;
  # this fetches that list at login and every 30 minutes and writes the menu's
  # generated file. Names like git.home.arpa are used when this machine can
  # resolve them (Tailscale DNS → Pi-hole), otherwise server:port.
  homelabServer = s.homelabServer or "";
  homelabDiscover = pkgs.writeShellApplication {
    name = "homelab-discover";
    runtimeInputs = with pkgs; [ curl jq coreutils glibc.bin ];
    text = ''
      server="''${1:-${homelabServer}}"
      [ -n "$server" ] || { echo "Set homelabServer in settings.local.nix (e.g. \"live\")."; exit 2; }
      out="''${XDG_STATE_HOME:-$HOME/.local/state}/nixmenu/homelab.tsv"
      mkdir -p "$(dirname "$out")"
      json=$(curl -fsS --max-time 10 "http://$server/services.json") \
        || { echo "Couldn't reach http://$server/ (Tailscale up? homelab module on there?). Keeping the last list."; exit 0; }
      tmp=$(mktemp)
      jq -r '.[] | [.name, .url, .direct] | @tsv' <<<"$json" | while IFS=$'\t' read -r name url direct; do
        host=''${url#*://}; host=''${host%%[:/]*}
        getent hosts "$host" >/dev/null 2>&1 || url=$direct
        printf 'Self-hosted\t%s (%s)\turl\t-\t%s\n' "$name" "$server" "$url"
      done > "$tmp"
      mv "$tmp" "$out"
      echo "$(wc -l < "$out") services from $server → your menu (Super+Alt+d)."
    '';
  };

  # one app-menu launcher per self-hosted web app (my.selfhosted).
  dashItems = lib.mapAttrsToList (name: url: pkgs.makeDesktopItem {
    name = "web-" + lib.toLower (builtins.replaceStrings [ " " "/" ] [ "-" "-" ] name);
    desktopName = name;
    exec = "${pkgs.brave}/bin/brave --app=${url}";
    icon = "web-browser"; categories = [ "Network" ];
  }) config.my.selfhosted;

  # ── nixmenu (Super+Alt+Space): /etc/nixmenu/menu.tsv from every module's
  # my.menu + settings.nix → menu. pkgs/scripts/nixmenu.sh reads it (plus
  # ~/.config/nixmenu/menu) and shows it as category → action.
  menuCfg = s.menu or { };
  # Top-level folders, in this order (sub-folders show inside them).
  defaultOrder = [ "System" "Apps & files" "AI" "Code & engineering" "Games" "Self-hosted" "Network & privacy" "Devices" ];
  allMenu = config.my.menu;
  catOrder = lib.unique (lib.filter (c: (allMenu.${c} or [ ]) != [ ])
    ((menuCfg.order or [ ]) ++ defaultOrder ++ lib.attrNames allMenu));
  oneLine = builtins.replaceStrings [ "\t" "\n" ] [ " " " " ];
  us = builtins.fromJSON ''"\u001f"'';        # separates a toggle's state / on / off commands
  mode = i: if i.state == null then i.mode else if i.mode == "term" then "toggleterm" else "toggle";
  runOf = i: if i.state == null then i.run else "${i.state}${us}${i.run}${us}${i.off}";
  menuTsv = lib.concatMapStrings (c: lib.concatMapStrings (i:
    lib.optionalString (!(lib.elem i.label (menuCfg.hide or [ ])))
      "${oneLine c}\t${oneLine i.label}\t${mode i}\t${if i.needs == null then "-" else i.needs}\t${oneLine (runOf i)}\n"
  ) allMenu.${c}) catOrder;

  # `welcome` — first-run setup in a window (pkgs/scripts/welcome.py): modules,
  # Tailscale, the VPN, backups, bringing files over. Opens at the first login.
  welcomeData = pkgs.writeText "welcome.json" (builtins.toJSON {
    inherit (import ../branding/branding.nix) name colors;
    hostname = s.hostName;
    homelabServer = s.homelabServer or "";
    modules = lib.filter (m: builtins.pathExists (../modules + "/${m.id}.nix")) [
      { id = "gaming"; title = "Gaming"; desc = "Steam (Windows games too), Minecraft, controllers"; }
      { id = "devtools"; title = "Code"; desc = "Git, editors, debuggers, fast builds, new-project templates"; }
      { id = "ai"; title = "AI"; desc = "Claude: the desktop app and Claude Code"; }
      { id = "ee"; title = "Electronics & CAD"; desc = "KiCad, Arduino/ESP32/Pico, FreeCAD, slicers"; }
      { id = "extras"; title = "More apps"; desc = "Discord, Slack, music, ebooks, torrents, Chromium"; }
      { id = "privacy"; title = "Proton & Tor"; desc = "Proton Mail/Pass, Tor Browser, Tor for everything"; }
      { id = "platform"; title = "Containers & Flatpak"; desc = "Docker, Flathub apps, AppImages, Distrobox"; }
      { id = "paper"; title = "Printers & scanners"; desc = "Paper printers and scanners, mostly driverless"; }
      { id = "printing"; title = "3D printers"; desc = "Klipper printers on your network, print-done alerts"; }
      { id = "sync"; title = "Sync my machines"; desc = "Syncthing folders, send files and tabs, screen sharing"; }
      { id = "virt"; title = "Virtual machines"; desc = "QEMU/KVM with virt-manager"; }
      { id = "assistant"; title = "Local AI assistant"; desc = "Neb + Ollama on your GPU (big downloads)"; }
      { id = "homelab"; title = "This is my home server"; desc = "Pi-hole, Nextcloud, Gitea, Jellyfin, Immich, backups… 24/7"; }
    ];
  });
  # `pastecheck`: run right after copying something that pastes slowly.
  pastecheck = pkgs.writeShellScriptBin "pastecheck" ''
    export PATH=${lib.makeBinPath (with pkgs; [ xclip xprop ])}:$PATH
    export PASTECHECK_LIBX11=${pkgs.libx11}/lib/libX11.so.6
    exec ${pkgs.python3}/bin/python3 -I ${../pkgs/scripts/pastecheck.py} "$@"
  '';
  welcome = pkgs.writeShellScriptBin "welcome" ''
    export WELCOME_DATA=${welcomeData}
    exec ${pkgs.python3}/bin/python3 -I ${../pkgs/scripts/welcome.py} "$@"
  '';

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

  # After the screens changed (menu displays, a monitor plugged in): the
  # wallpaper is set again for the new sizes, the live wallpaper gets its
  # windows remade (one per screen), and the snow covers the new area.
  displaysRefresh = pkgs.writeShellScriptBin "displays-refresh" ''
    bg="$HOME/.local/share/bg"
    fit=$(cat "$HOME/.config/wallpapers/fit" 2>/dev/null) || fit=zoom
    [ -e "$bg" ] && ${pkgs.xwallpaper}/bin/xwallpaper "--''${fit:-zoom}" "$bg"
    systemctl --user try-restart wallpaper-live.service 2>/dev/null || true
    if ${pkgs.procps}/bin/pgrep -f '(^|/)xsnow( |$)' >/dev/null; then
      ${pkgs.snow}/bin/snow off; ${pkgs.snow}/bin/snow on
    fi
    true
  '';

  # `nightlight` — night light (warmer screen after sunset) off for now / back on.
  nightlight = pkgs.writeShellScriptBin "nightlight" ''
    if systemctl --user is-active --quiet redshift; then
      systemctl --user stop redshift
      notify-send -a "Night light" "Night light off" "Back on at your next login, or run nightlight again."
    else
      systemctl --user start redshift
      notify-send -a "Night light" "Night light on" "Warmer colours after sunset."
    fi
  '';

  # `mykeys` — a printable cheat sheet of MY custom keybinds (Super+Alt+F1, and
  # an entry in nixmenu). Stock LARBS keys stay on Super+F1's manual.
  # settings.screenshotKey (a laptop whose screenshot key sends e.g. F10): one more line.
  shotKeyLine =
    let k = s.screenshotKey or "Print"; label = "${k} / Shift + ${k}";
        pad = lib.concatStrings (lib.genList (_: " ") (lib.max 2 (27 - builtins.stringLength label)));
    in lib.optionalString (k != "Print") "\n  ${label}${pad}the same, on this keyboard's screenshot key";
  mykeys = pkgs.writeShellScriptBin "mykeys" ''
    cat <<'SHEET'

      MY KEYBINDS   (Super = the key that used to be CapsLock)

      Super + Alt + Space        menu — the menu of everything here
      Super + Alt + n            talk to Neb (a corner notification; press again to send now)
      Super + Alt + Shift + n    Neb's workspace (tag 9) + his terminal — Enter on an empty line talks
      Super + Alt + a            apps, by category
      Super + Alt + e            file manager (Thunar)
      Super + Alt + m            drives: mount / unlock / unmount
      Super + Alt + l            lock the screen
      Super + Alt + d            self-hosted apps (menu section)
      Super + Alt + b            Bluetooth
      Super + Alt + v            audio: output/mic device, volume, mute
      Super + Alt + c            clipboard history: paste anything you copied earlier
      In the terminal:           select text = copied · right-click = paste
                                 Ctrl+Shift+C / Ctrl+Shift+V (or Alt+C / Alt+V) also work;
                                 in vim/htop hold Shift while selecting or right-clicking
      Super + Alt + s            screenshot menu (same as Shift+Print) — also screen recording
      Print / Shift + Print      screenshot: whole screen / the menu${shotKeyLine}
      Super + Alt + p            displays: mirror, extend, resolution (also Super + F3)
      Super + Alt + w            wallpapers: pictures + Wallpaper Engine (live)
      Super + Alt + r            look & feel: themes, colours from the wallpaper, gaps…
      Super + Alt + o            shutdown timer: turn off (or suspend) in 30 min, at 23:30…
      Super + Alt + y            Wi-Fi: pick a network (password asked once)
      Super + Alt + t            Tor Browser
      Super + Alt + Return       tmux session
      Super + Alt + i            system info (fastfetch)
      Super + Alt + F1           this sheet

      Stock keys I changed:
      Super + e              file manager (it opened neomutt, which is gone)
      Super + F9 / F10       drives: mount / unmount
      Stock and unchanged:   Super + Enter terminal · Super + Space zoom · Super + r lf

      Everything else is stock LARBS — press Super + F1 for that manual.

    SHEET
  '';

  # Compositor config. Terminals (class St) are translucent, but ANY fullscreen
  # window is forced fully opaque — rules match top-to-bottom and the last match
  # wins, so the fullscreen rule overrides the terminal rule when you Super+f a
  # terminal. (picom v13 `rules` syntax; `fullscreen` is a built-in condition.)
  picomConf = pkgs.writeText "picom.conf" ''
    backend = "glx";
    vsync = true;
    rules = (
      { match = "class_g = 'St'"; opacity = ${toString s.termOpacity}; },
      { match = "fullscreen";     opacity = 1.0; }
    );
  '';
in
{
  services.xserver = {
    enable = true;
    xkb = { layout = kbLayout; variant = kbVariant; options = "caps:super,altwin:menu_win"; };
    windowManager.dwm = {
      enable = true; package = pkgs.larbs-dwm;
      extraSessionCommands = ''
        export _JAVA_AWT_WM_NONREPARENTING=1
        [ -f "$HOME/.config/x11/xresources" ] && ${pkgs.xrdb}/bin/xrdb -merge "$HOME/.config/x11/xresources"
        # Your look from `rice` (theme, gaps, opacity, light/dark), on top.
        export NIX2_TERM_OPACITY=${toString s.termOpacity} NIX2_PICOM_CONF=${picomConf}
        ${pkgs.rice}/bin/rice apply --startup 2>/dev/null || true
        [ -f "$HOME/.config/xsettingsd/xsettingsd.conf" ] && ${pkgs.xsettingsd}/bin/xsettingsd &
        ${pkgs.larbs-dwmblocks}/bin/dwmblocks &
        picomconf=${picomConf}; [ -f "$HOME/.config/nix2/picom.conf" ] && picomconf="$HOME/.config/nix2/picom.conf"
        ${pkgs.picom}/bin/picom --config "$picomconf" &
        ${pkgs.unclutter-xfixes}/bin/unclutter &
        ${pkgs.dunst}/bin/dunst &
        ${pkgs.blueman}/bin/blueman-applet &
        ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1 &   # password prompts (drives, etc.)
        command -v mpd >/dev/null && mpd &        # music daemon: only with the extras module
        # First login: the welcome window (once; menu → System → Welcome / setup any time).
        (sleep 4; ${welcome}/bin/welcome --if-new) &
        # Brave is the default browser: say so once in your own defaults (a
        # browser may have claimed links there before). Change it later and it
        # stays changed.
        if [ "$(cat "$HOME/.local/state/nix2/default-browser" 2>/dev/null)" != brave ]; then
          ${pkgs.xdg-utils}/bin/xdg-mime default brave-browser.desktop x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml 2>/dev/null \
            && mkdir -p "$HOME/.local/state/nix2" && echo brave > "$HOME/.local/state/nix2/default-browser"
        fi
        # Screens (the layout you kept for this set of monitors, menu displays)
        # and then the wallpaper, alongside the desktop starting rather than
        # before it: dwm follows screen changes by itself (~0.4 s sooner).
        bg="$HOME/.local/share/bg"
        [ -e "$bg" ] || { mkdir -p "$HOME/.local/share"; ln -sfn ${wallpaper} "$bg"; }
        fit=$(cat "$HOME/.config/wallpapers/fit" 2>/dev/null) || fit=zoom   # set in `wallpapers`
        { ${pkgs.autorandr}/bin/autorandr --change >/dev/null 2>&1
          ${pkgs.xwallpaper}/bin/xwallpaper "--''${fit:-zoom}" "$bg"; } &
        ${lib.optionalString (s.liveSnow or false) "${pkgs.snow}/bin/snow on"}
        ${pkgs.larbs-scripts}/bin/remaps &
        ${pkgs.xset}/bin/xset s 600 600          # 10 idle minutes → xss-lock locks the screen
        # for user services that started before X (Neb's desktop actions, tab sets)
        printf 'DISPLAY=%s\nXAUTHORITY=%s\n' "$DISPLAY" "''${XAUTHORITY:-$HOME/.Xauthority}" \
          > "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/x-env"
        true
      '';
    };
  };
  # A layout other than plain US also applies on the text console — that's
  # the login screen (ly) and, on an encrypted disk, the password prompt at
  # start-up — so a password is typed the same way everywhere.
  console = lib.mkIf (kbLayout != "us" || kbVariant != "") { useXkbConfig = true; earlySetup = true; };
  services.libinput.enable = true;
  # Apps' own "start at login" (Proton VPN and Mail, Discord, earlyoom's
  # low-memory warnings…) are XDG autostart entries, which a bare window
  # manager never runs. This runs them when the session starts.
  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  # …a few seconds after the desktop is up, and below it in priority, so the
  # desktop is usable at once instead of fighting Proton, Discord & co. for
  # the disk. (A drop-in for every app-*@autostart.service.)
  systemd.packages = [ (pkgs.writeTextDir "lib/systemd/user/app-.service.d/parajynx-later.conf" ''
    [Service]
    ExecStartPre=${pkgs.coreutils}/bin/sleep 4
    Nice=5
    IOSchedulingClass=best-effort
    IOSchedulingPriority=6
  '') ];

  # Clipboard history (Super+Alt+c): remembers what you copy, pick it back with dmenu.
  services.clipmenu.enable = true;
  # Password managers' windows aren't recorded at all.
  #
  # It only watches: the app you copied from keeps owning the clipboard. (It
  # used to take the clipboard over right after every copy so text outlived its
  # window, but that stripped formatting and made docs apps (LibreOffice,
  # browsers) freeze when pasting. Closed the window? Super+Alt+c still has it.)
  #
  # Kept small so it never lags: only what you actually copy (not every mouse
  # highlight, which st also copies), at most 50 entries, and each one is
  # forgotten settings.clipboardForgetMinutes after you copied it. (With the
  # defaults of 1000 entries + every highlight, clipmenud re-checked its whole
  # history in a slow shell loop every few copies.)
  systemd.user.services.clipmenu.environment = {
    CM_OWN_CLIPBOARD = "0";
    CM_IGNORE_WINDOW = "Bitwarden|KeePass|Proton Pass|Password";
    CM_SELECTIONS = "clipboard";
    CM_MAX_CLIPS = "50";
  };
  systemd.user.services.clipboard-forget = lib.mkIf (clipForget > 0) {
    description = "Forget clipboard history older than ${toString clipForget} minutes";
    serviceConfig.Type = "oneshot";
    script = ''
      dir="''${XDG_RUNTIME_DIR:-/tmp}/clipmenu.6.$USER"
      cache="$dir/line_cache"
      [ -s "$cache" ] || exit 0
      exec {lock}> "$dir/lock"
      ${pkgs.util-linux}/bin/flock -x -w 5 "$lock" || exit 0
      cutoff=$(( $(date +%s) - ${toString (clipForget * 60)} ))
      # Lines are "<copy time in ns> <first line>"; keep the recent ones.
      keep=$(mktemp -p "$dir" .keep.XXXXXX)
      while IFS= read -r line; do
        t=''${line%% *}
        if [[ $t =~ ^[0-9]+$ ]] && (( t / 1000000000 >= cutoff )); then printf '%s\n' "$line"; fi
      done < "$cache" > "$keep"
      mv -- "$keep" "$cache"
      # Remove the stored text of every clip no longer listed.
      declare -A listed
      while IFS= read -r first; do listed["$(cksum <<< "$first")"]=1; done < <(cut -d' ' -f2- "$cache")
      for f in "$dir"/[0-9]*; do
        if [ -e "$f" ] && [ -z "''${listed["''${f##*/}"]-}" ]; then rm -f -- "$f"; fi
      done
    '';
  };
  systemd.user.timers.clipboard-forget = lib.mkIf (clipForget > 0) {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnActiveSec = "5min"; OnUnitActiveSec = "5min"; };
  };

  # Night light: the screen turns gradually warmer after sunset (gammastep).
  # Where you are sets sunset time: settings.nix → location. Off for now: nightlight.
  services.redshift = {
    enable = s.nightLight or true;
    package = pkgs.gammastep;
    executable = "/bin/gammastep";
    temperature = { day = 6500; night = 3800; };
  };
  location = {
    provider = "manual";
    latitude = (s.location or { }).latitude or 40.7;
    longitude = (s.location or { }).longitude or (-74.0);
  };
  # Screens (`menu displays`, Super+Alt+p): a layout you keep is saved for
  # that exact set of monitors, and autorandr puts it back when they're
  # plugged in, at login and after sleep.
  services.autorandr = {
    enable = true;
    hooks.postswitch."nix2-refresh" = "${displaysRefresh}/bin/displays-refresh";
  };
  services.displayManager.ly.enable = true;
  hardware.graphics.enable = true;
  # Graphics drivers for settings.gpu. AMD and Intel need nothing extra (Mesa);
  # NVIDIA gets its own driver (built for your kernel on the first rebuild).
  services.xserver.videoDrivers = lib.mkIf (s.gpu == "nvidia") [ "nvidia" ];
  hardware.nvidia = lib.mkIf (s.gpu == "nvidia") {
    open = s.nvidiaOpen or true;
    modesetting.enable = true;
    nvidiaSettings = true;
  };
  hardware.graphics.extraPackages = lib.optionals (s.gpu == "intel") [ pkgs.intel-media-driver ];  # video decoding
  services.blueman.enable = true;            # Bluetooth GUI (Super+Alt+b)

  # Lock screen: `lock` — username + password on a plain screen (xsecurelock).
  # xss-lock runs it on every suspend and when X's idle timer (set above)
  # fires, dimming the screen for a few seconds first so you can cancel by
  # moving the mouse; -l holds suspend until the screen is really locked.
  # Live wallpaper: whatever you picked in the Wallpaper Engine tab of
  # `wallpapers` (Super+Alt+w). Nothing picked → this does nothing.
  systemd.user.services.wallpaper-live = {
    description = "Live wallpaper (Wallpaper Engine, via linux-wallpaperengine)";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = { ExecStart = "${pkgs.wallpaper-live}/bin/wallpaper-live"; Restart = "on-failure"; RestartSec = 10; };
  };

  programs.xss-lock = {
    enable = true;
    lockerCommand = "${pkgs.lock-screen}/bin/lock";
    extraOptions = [ "-n" "${pkgs.xsecurelock}/libexec/xsecurelock/dimmer" "-l" ];
  };

  # ── files & drives ─────────────────────────────────────────────────────────
  # Thunar is the GUI file manager; lf (Super+r) stays the terminal one. No
  # automounting anywhere (no thunar-volman, no udiskie): click a drive in
  # Thunar's sidebar, or use `drives`. Both go through udisks2 as your user.
  programs.thunar = { enable = true; plugins = [ pkgs.thunar-archive-plugin ]; };
  services.udisks2.enable = true;
  services.gvfs.enable = true;               # Thunar's drive sidebar, trash, phones (MTP/iPhone)
  services.tumbler.enable = true;            # thumbnails
  # "Open folder" → Thunar; links and web pages → Brave (apps.nix). Your own
  # ~/.config/mimeapps.list still wins if you set something else there.
  xdg.mime.defaultApplications = {
    "inode/directory" = "thunar.desktop";
  } // lib.genAttrs [
    "x-scheme-handler/http" "x-scheme-handler/https" "text/html" "application/xhtml+xml"
  ] (_: "brave-browser.desktop");

  # Session-wide (PAM + systemd), not just shells: an app started at login or
  # by a service still knows which browser opens links.
  environment.sessionVariables.BROWSER = "brave";
  environment.variables = {
    TERMINAL = "st"; READER = "zathura"; FILE = "lfub";
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

  environment.etc."nixmenu/menu.tsv".text = menuTsv;
  my.selfhosted = s.selfhosted or { };
  my.menu = lib.mkMerge [
    {
      "System" = [
        { label = "Welcome / setup (modules, Tailscale, VPN, backups)"; run = "welcome"; }
        { label = "Lock screen"; run = "lock"; }
        { label = "Suspend"; run = "zzz"; }
        { label = "Shutdown timer (turn off later)"; run = "offtimer"; }
        { label = "Screenshot (area, window, text…)"; run = "screenshot"; }
        { label = "Screen recording"; state = ''p="''${XDG_RUNTIME_DIR:-/tmp}/screen-recording.pid"; [ -s "$p" ] && kill -0 "$(cat "$p")"'';
          run = "screenshot record"; off = "screenshot record-stop"; }
        { label = "Clipboard history"; run = "clipmenu -i -l 20 -p clipboard:"; }
        { label = "My keybinds"; run = "mykeys"; mode = "term"; }
      ];
      "System/Look" = [
        { label = "Wallpapers (pictures + Wallpaper Engine)"; run = "wallpapers"; }
        { label = "Look & feel (themes, colours, see-through, gaps)"; run = "rice"; }
        { label = "Live snow"; state = "pgrep -f '(^|/)xsnow( |$)'"; run = "snow on"; off = "snow off"; }
        { label = "Night light"; state = "systemctl --user is-active --quiet redshift";
          run = "systemctl --user start redshift"; off = "systemctl --user stop redshift"; }
      ];
      "Apps & files" = [
        { label = "Apps"; run = "apps"; }
        { label = "Files"; run = "thunar"; }
        { label = "Drives: mount / unmount"; run = "drives"; }
        { label = "Publish a folder to Neocities"; run = "SITE_PUSH_GUI=1 site-push"; mode = "term"; }
      ];
      "Apps & files/Tidy up" = [
        { label = "Tidy up home + Downloads (sort + find duplicates)"; run = "tidy"; mode = "term"; }
        { label = "Undo the last tidy"; run = "tidy --undo"; mode = "term"; }
      ];
      "Devices" = [
        { label = "Audio (output, mic, volume)"; run = "audio"; }
        { label = "Bluetooth"; run = "blueman-manager"; needs = "blueman-manager"; }
        { label = "Displays (mirror, extend, resolution, rotate)"; run = "menu displays"; }
      ];
      "Network & privacy" = [
        { label = "Wi-Fi (pick a network)"; run = "wifi"; }
      ];
      "Self-hosted" = lib.mapAttrsToList (name: url: { label = name; run = url; mode = "url"; })
        config.my.selfhosted;
    }
    (menuCfg.extra or { })
  ];

  systemd.user.services.homelab-discover = lib.mkIf (homelabServer != "") {
    description = "Add ${homelabServer}'s services to the menu";
    after = [ "network-online.target" ];
    serviceConfig = { Type = "oneshot"; ExecStart = "${homelabDiscover}/bin/homelab-discover"; };
  };
  systemd.user.timers.homelab-discover = lib.mkIf (homelabServer != "") {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnStartupSec = "1min"; OnUnitActiveSec = "30min"; };
  };

  my.packages = [ dash drives pkgs.nixmenu mykeys nightlight displaysRefresh homelabDiscover ] ++ dashItems ++ (with pkgs; [
    wallpapers wallpaper-live site-push rice xsettingsd sb-privacy sb-homelab welcome pastecheck
    (makeDesktopItem {
      name = "rice"; desktopName = "Look & feel"; exec = "rice";
      icon = "preferences-desktop-theme"; categories = [ "Settings" "DesktopSettings" ];
    })
    (makeDesktopItem {
      name = "wallpapers"; desktopName = "Wallpapers"; exec = "wallpapers";
      icon = "preferences-desktop-wallpaper"; categories = [ "Settings" "DesktopSettings" ];
    })
    apps-menu tidy tidy-downloads screenshot snow lock-screen audio offtimer wifi
    larbs-st larbs-dmenu larbs-dwmblocks larbs-scripts
    xinit xrdb xprop xwininfo xset setxkbmap xbacklight xrandr slop
    xclip xdotool xcape xwallpaper picom unclutter-xfixes maim slock
    dunst libnotify arandr screenkey tesseract wmctrl groff feh imagemagick
    brightnessctl xev lf ueberzugpp zathura nsxiv
    gruvbox-gtk-theme papirus-icon-theme lxappearance
    xarchiver ntfs3g exfatprogs dosfstools   # archives (Thunar plugin) + fs tools for drives
    file                                     # what kind of file is this? (LARBS scripts: setbg, lf, opout)
    (writeShellScriptBin "zzz" ''exec systemctl suspend "$@"'')
  ]);
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.gnupg.agent = { enable = true; pinentryPackage = pkgs.pinentry-gtk2; };
  environment.pathsToLink = [ "/share/terminfo" ];
}
