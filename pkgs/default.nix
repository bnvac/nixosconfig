# Custom packages built from source / upstream binaries. One overlay.
final: prev:
let
  gh = prev.fetchFromGitHub;
  # shell tool from pkgs/scripts/NAME.sh: deps on PATH, shellcheck at build
  sh = name: deps: file: final.writeShellApplication { inherit name; runtimeInputs = deps; text = builtins.readFile file; };
  py = name: file: final.writeScriptBin name ("#!${final.python3}/bin/python3 -I\n" + builtins.readFile file);
in
{
  # ── LARBS suckless desktop (Luke Smith's pinned forks) ─────────────────────
  larbs-dwm = prev.stdenv.mkDerivation {
    pname = "larbs-dwm"; version = "6.5-larbs";
    src = gh { owner = "LukeSmithxyz"; repo = "dwm";
      rev = "ee3354d54a51a14449a9ba93fe978c8a3a66db45";
      hash = "sha256-fQyhMa4gDD6EXH0hLDwU8tU7X4KUsuRlQu8saaoxfVM="; };
    nativeBuildInputs = [ prev.pkg-config ];
    buildInputs = with prev; [ libx11 libxinerama libxft libxcb fontconfig freetype ];
    postPatch = ''
      substituteInPlace config.h --replace-fail '#define BROWSER "librewolf"' '#define BROWSER "firefox"'
      substituteInPlace config.h --replace-fail "/usr/local/share/dwm/larbs.mom" "$out/share/dwm/larbs.mom"
      substituteInPlace config.h \
        --replace-fail '{ "xbacklight", "-inc", "15", NULL }' '{ "brightnessctl", "set", "10%+", NULL }' \
        --replace-fail '{ "xbacklight", "-dec", "15", NULL }' '{ "brightnessctl", "set", "10%-", NULL }'
      # Stock keys repointed: Super+e opened neomutt (not installed) → Thunar;
      # Super+F9/F10 ran the sudo-based mounter/unmounter → the udisks `drives`.
      # (Super+Space and Super+Enter are stock again: zoom, and a terminal.)
      substituteInPlace config.h \
        --replace-fail 'SHCMD(TERMINAL " -e neomutt ; pkill -RTMIN+12 dwmblocks")' '{.v = (const char*[]){ "thunar", NULL } }' \
        --replace-fail '{ "mounter", NULL }'   '{ "drives", "mount", NULL }' \
        --replace-fail '{ "unmounter", NULL }' '{ "drives", "unmount", NULL }'
      # Live wallpaper: xsnow makes an ordinary window, which dwm would tile like
      # an app (half the screen, black). Windows of class Xsnow are instead
      # sized to the whole screen, mapped, pushed to the very bottom and never
      # managed — a true background
      # layer. Checked in maprequest (new windows) and scan (dwm restarts).
      substituteInPlace dwm.c \
        --replace-fail $'void\nmaprequest(XEvent *e)\n{' $'static int\nisbackground(Window w)\n{\n\tXClassHint ch = { NULL, NULL };\n\tint bg = 0;\n\n\tif (XGetClassHint(dpy, w, &ch)) {\n\t\tbg = ch.res_class && !strcmp(ch.res_class, "Xsnow");\n\t\tif (ch.res_class)\n\t\t\tXFree(ch.res_class);\n\t\tif (ch.res_name)\n\t\t\tXFree(ch.res_name);\n\t}\n\treturn bg;\n}\n\nvoid\nmaprequest(XEvent *e)\n{' \
        --replace-fail $'\tif (!wintoclient(ev->window))\n\t\tmanage(ev->window, &wa);' $'\tif (isbackground(ev->window)) {\n\t\tXMoveResizeWindow(dpy, ev->window, 0, 0, sw, sh);\n\t\tXMapWindow(dpy, ev->window);\n\t\tXLowerWindow(dpy, ev->window);\n\t\treturn;\n\t}\n\tif (!wintoclient(ev->window))\n\t\tmanage(ev->window, &wa);' \
        --replace-fail '|| wa.override_redirect || XGetTransientForHint(dpy, wins[i], &d1))' '|| wa.override_redirect || XGetTransientForHint(dpy, wins[i], &d1) || isbackground(wins[i]))'
      # Neb's own workspace: his terminal (st -n neb) always lives on tag 9.
      substituteInPlace config.h --replace-fail 'static const Rule rules[] = {' 'static const Rule rules[] = {
        { TERMCLASS, "neb", NULL, 1 << 8, 0, 1, 0, -1 },'
      # All MY OWN functions live under Super+Alt (Mod1). Stock LARBS binds
      # nothing with Mod1Mask, so these can't collide (checked at this rev).
      # Super+Alt+Shift+n is bound twice on purpose: dwm runs every matching
      # binding, so one press switches to tag 9 AND opens Neb's terminal there.
      cat > larbs-extra-keys.h <<'KEYS'
      { MODKEY|Mod1Mask,           XK_space,  spawn, {.v = (const char*[]){ "nixmenu", NULL } } },
      { MODKEY|Mod1Mask,           XK_n,      spawn, {.v = (const char*[]){ "neb-voice", NULL } } },
      { MODKEY|Mod1Mask|ShiftMask, XK_n,      view,  {.ui = 1 << 8} },
      { MODKEY|Mod1Mask|ShiftMask, XK_n,      spawn, {.v = (const char*[]){ "neb-space", NULL } } },
      { MODKEY|Mod1Mask,           XK_a,      spawn, {.v = (const char*[]){ "apps", NULL } } },
      { MODKEY|Mod1Mask,           XK_e,      spawn, {.v = (const char*[]){ "thunar", NULL } } },
      { MODKEY|Mod1Mask,           XK_m,      spawn, {.v = (const char*[]){ "drives", NULL } } },
      { MODKEY|Mod1Mask,           XK_l,      spawn, {.v = (const char*[]){ "lock", NULL } } },
      { MODKEY|Mod1Mask,           XK_d,      spawn, {.v = (const char*[]){ "dash", NULL } } },
      { MODKEY|Mod1Mask,           XK_b,      spawn, {.v = (const char*[]){ "blueman-manager", NULL } } },
      { MODKEY|Mod1Mask,           XK_t,      spawn, {.v = (const char*[]){ "tor-browser", NULL } } },
      { MODKEY|Mod1Mask,           XK_Return, spawn, {.v = (const char*[]){ TERMINAL, "-e", "tmux", "new-session", "-A", "-s", "main", NULL } } },
      { MODKEY|Mod1Mask,           XK_i,      spawn, SHCMD(TERMINAL " -e sh -c 'fastfetch; read -r _'") },
      { MODKEY|Mod1Mask,           XK_F1,     spawn, SHCMD(TERMINAL " -e sh -c 'mykeys; read -r _'") },
      KEYS
      substituteInPlace config.h --replace-fail 'static const Key keys[] = {' 'static const Key keys[] = {
      #include "larbs-extra-keys.h"'
    '';
    makeFlags = [ "PREFIX=$(out)" "CC=cc" "FREETYPEINC=${prev.freetype.dev}/include/freetype2"
      "X11INC=${prev.libx11.dev}/include" "X11LIB=${prev.libx11}/lib" ];
    meta.mainProgram = "dwm";
  };

  larbs-st = prev.stdenv.mkDerivation {
    pname = "larbs-st"; version = "0.8.5-larbs";
    src = gh { owner = "LukeSmithxyz"; repo = "st";
      rev = "48b8ee6e181643800fe83353ec554f503020a8fa";
      hash = "sha256-XFf48+6I3IHcRKGHRJIJb9u2sTKWyuWTb5lN+BILYYc="; };
    nativeBuildInputs = [ prev.pkg-config prev.ncurses ];
    buildInputs = with prev; [ libx11 libxft fontconfig freetype harfbuzz libxrender ];
    # Opaque surface: the compositor (picom) owns terminal opacity now, so a
    # fullscreen terminal can be forced fully opaque. See modules/desktop.nix.
    postPatch = ''substituteInPlace config.h --replace-fail 'float alpha = 0.8;' 'float alpha = 1.0;' '';
    makeFlags = [ "PREFIX=$(out)" "CC=cc" ];
    preInstall = ''export TERMINFO=$out/share/terminfo; mkdir -p "$TERMINFO"'';
    meta.mainProgram = "st";
  };

  larbs-dmenu = prev.stdenv.mkDerivation {
    pname = "larbs-dmenu"; version = "5.0-larbs";
    src = gh { owner = "LukeSmithxyz"; repo = "dmenu";
      rev = "c1819f18c07df6984bbfd2ca7207295eec85806f";
      hash = "sha256-QcnsD8h0uDjttqOHZwMWVA3Qp1eH/og5RrSeopnMILM="; };
    nativeBuildInputs = [ prev.pkg-config ];
    buildInputs = with prev; [ libx11 libxinerama libxft fontconfig freetype libxrender ];
    makeFlags = [ "PREFIX=$(out)" "CC=cc" "FREETYPEINC=${prev.freetype.dev}/include/freetype2"
      "X11INC=${prev.libx11.dev}/include" "X11LIB=${prev.libx11}/lib" ];
    meta.mainProgram = "dmenu";
  };

  larbs-dwmblocks = prev.stdenv.mkDerivation {
    pname = "larbs-dwmblocks"; version = "0-unstable";
    src = gh { owner = "LukeSmithxyz"; repo = "dwmblocks";
      rev = "1c9744ac7ded4fff8171169bc0b9736f3acd4cfe";
      hash = "sha256-gT2PXaQ0VdqlA77jpoXBjuFM5UTuGiIZ5eYzXFVm9TU="; };
    buildInputs = [ prev.libx11 ];
    # Status bar blocks. Upstream's reference the voidrice sb-* scripts (now
    # flattened onto PATH by larbs-scripts); the clock is inline `date` so the
    # TIME always shows even if a script is missing. Edit this to taste.
    postPatch = ''
      cat > config.h <<'CFG'
      static const Block blocks[] = {
        {"", "sb-internet 2>/dev/null",            10, 4},
        {"", "sb-volume 2>/dev/null",               0, 10},
        {"", "sb-battery 2>/dev/null",              5, 3},
        {"", "date '+%a %d %b  %H:%M'",            30, 1},
      };
      static char *delim = " | ";
      CFG
    '';
    makeFlags = [ "PREFIX=$(out)" "CC=cc" ];
    meta.mainProgram = "dwmblocks";
  };

  larbs-scripts = prev.stdenv.mkDerivation {
    pname = "larbs-scripts"; version = "0-unstable";
    src = gh { owner = "LukeSmithxyz"; repo = "voidrice";
      rev = "ad944910efb2fd3086255767632ec8f0e8f5c06d";
      hash = "sha256-qu0nK4aWYjMSheA4tUO/C5mdmdyQRMEvLM63ObepZns="; };
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share/larbs $out/share/larbs-dotfiles
      cp -r .local/bin/. $out/bin/
      cp -r .local/share/larbs/. $out/share/larbs/ 2>/dev/null || true
      # flatten statusbar/sb-* onto PATH so dwmblocks finds them by name
      for f in $out/bin/statusbar/*; do [ -f "$f" ] && ln -sf "$f" "$out/bin/$(basename "$f")"; done
      cp -r .config $out/share/larbs-dotfiles/config
      chmod -R +w $out/share/larbs-dotfiles
      substituteInPlace $out/share/larbs-dotfiles/config/x11/xresources \
        --replace-fail '*.alpha: 0.8' '*.alpha: 1.0'
      chmod -R +w $out/bin
      # sysact's lock used slock (needs a setuid wrapper we don't ship); use
      # our `lock`. Sleep/hibernate no longer wrap in slock: xss-lock locks
      # the screen on every suspend anyway.
      substituteInPlace $out/bin/sysact \
        --replace-fail 'slock $ctl hibernate -i' '$ctl hibernate -i' \
        --replace-fail 'slock $ctl suspend -i' '$ctl suspend -i' \
        --replace-fail $'\tslock' $'\tlock'
      find $out/bin -type f -exec sed -i '1s|^#!/usr/bin/sh|#!/bin/sh|' {} +
      patchShebangs $out/bin
      runHook postInstall
    '';
  };

  xp-bliss-grub-theme = prev.stdenvNoCC.mkDerivation {
    pname = "xp-bliss-grub-theme"; version = "0-unstable";
    src = gh { owner = "hashirsajid58200p"; repo = "windows-xp-bliss-grub-theme";
      rev = "4766f2e94f9be8f6b7e890d62c751eedc746c3dc";
      hash = "sha256-Vj2RU1doZGXM+y9MDe1t87jSvdACUULzQImg41o/+P8="; };
    dontBuild = true;
    installPhase = ''
      mkdir -p $out; cp -r . $out/; chmod -R +w $out
      cp "$out/No watermark version – rename and place in assets folder.jpg" "$out/assets/background.jpg"
      rm -f "$out/No watermark version – rename and place in assets folder.jpg" \
            "$out/background.jpg" "$out/preview.jpg" "$out/install.sh" "$out/README.md" "$out/LICENSE"
    '';
  };

  # ── devlink — link two machines over Syncthing, send anything between them ──
  devlink = final.python3Packages.buildPythonApplication {
    pname = "devlink"; version = "0.1.0"; pyproject = true;
    src = ./devlink;
    build-system = [ final.python3Packages.hatchling ];
    dependencies = [ ];           # stdlib only
    doCheck = false;
    meta.mainProgram = "devlink";
  };

  # ── small tools (sources in pkgs/scripts/, shellchecked at build) ─────────
  rebuild         = sh "rebuild" [ final.nix-output-monitor ] ./scripts/rebuild.sh;
  apps-menu       = sh "apps" (with final; [ larbs-dmenu gawk coreutils gnused libnotify util-linux ]) ./scripts/apps.sh;
  snow            = sh "snow" (with final; [ xsnow procps util-linux ]) ./scripts/snow.sh;
  neb-space       = sh "neb-space" (with final; [ xdotool util-linux ]) ./scripts/neb-space.sh;
  backoffice-sync = sh "backoffice-sync" (with final; [ sqlite coreutils util-linux libnotify systemd ]) ./scripts/backoffice-sync.sh;
  desk = sh "desk" (with final; [ final.apps-menu final.lock-screen xdotool xprop jq gawk coreutils gnused
                                  procps wireplumber playerctl brightnessctl libnotify maim util-linux ]) ./scripts/desk.sh;
  lock-screen = final.writeShellApplication {
    name = "lock"; runtimeInputs = with final; [ i3lock-color file coreutils ];
    text = "LOCK_IMAGE=${final.snow-wallpaper}\n" + builtins.readFile ./scripts/lock.sh;
  };
  neb-voice       = py "neb-voice" ./scripts/neb-voice.py;
  tidy-downloads  = py "tidy-downloads" ./scripts/tidy-downloads.py;
  browser-sync    = py "browser-sync" ./scripts/browser-sync.py;
  snow-wallpaper  = final.runCommand "snow-wallpaper.png" { nativeBuildInputs = [ final.imagemagick ]; }
    "bash ${./scripts/snow-wallpaper.sh} $out";

  # ── Neb — the user's local voice assistant (stdlib-only Python) ────────────
  neb = final.python3Packages.buildPythonApplication {
    pname = "neb"; version = "0.1.0"; pyproject = true;
    src = gh { owner = "bnvac"; repo = "neb";
      rev = "e75b6e00f68201fd0555eee2f815170e792c93a5";
      hash = "sha256-QrR/xkJ007306UTaAlzhasifymFQjuz8+6p2OTm3KtE="; };
    # Two small local changes (worth upstreaming to bnvac/neb):
    #  - In Neb's terminal, Enter on an empty line talks out loud (runs
    #    neb-voice: listen → answer in a corner notification).
    #  - Ollama `think` comes from settings, so thinking models (qwen3.5,
    #    gemma4) can answer straight away instead of reasoning first.
    postPatch = ''
      substituteInPlace neb/tui.py \
        --replace-fail 'import shutil' $'import shutil\nimport subprocess' \
        --replace-fail '    ("/tools", "what Neb can call"),' $'    ("Enter (empty line)", "talk out loud: Neb listens, answers in a corner notification"),\n    ("/tools", "what Neb can call"),' \
        --replace-fail $'            if not line:\n                continue' $'            if not line:\n                if shutil.which("neb-voice"):\n                    subprocess.Popen(["neb-voice"], start_new_session=True, stdin=subprocess.DEVNULL,\n                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n                continue'
      substituteInPlace neb/backends.py \
        --replace-fail '        self.num_ctx = int(cfg.get("num_ctx") or 0)' $'        self.num_ctx = int(cfg.get("num_ctx") or 0)\n        self.think = cfg.get("think")' \
        --replace-fail '            body["options"] = {"num_ctx": self.num_ctx}' $'            body["options"] = {"num_ctx": self.num_ctx}\n        if self.think is not None:\n            body["think"] = bool(self.think)'
    '';
    build-system = [ final.python3Packages.hatchling ];
    dependencies = [ ];           # stdlib only
    doCheck = false;
    meta.mainProgram = "neb";
  };

  # ── the user's parts-inventory app → `backoffice` ──────────────────────────
  backoffice = prev.buildGoModule {
    pname = "backoffice"; version = "0-unstable";
    src = gh { owner = "bnvac"; repo = "backoffice";
      rev = "8ec9c6416cfe8bdbf122eb6525bc62d72dafe0a8";
      hash = "sha256-C/6MRfs8rboLsYODuTnKuXUACZnLPdbjTKeVnFD+1zI="; };
    vendorHash = "sha256-GzzJb8jVsck8Gji9/NvPq3b7TazjDq5o5zrZWH7gxjM=";
    env.CGO_ENABLED = 0; doCheck = false;
    meta.mainProgram = "backoffice";
  };

  # ── OSINT TUI cheat-sheet ──────────────────────────────────────────────────
  osint-tools-cli = prev.rustPlatform.buildRustPackage {
    pname = "osint-tools-cli"; version = "0.2.0";
    src = gh { owner = "Coordinate-Cat"; repo = "osint-tools-cli";
      rev = "dd730b5dcff84eeecb23ffa1c3e796ea2101319f";
      hash = "sha256-wsq+E6f4EnspVsl1Re61Bv4fHf+GIHwKj+X1KgTFaeE="; };
    postPatch = ''[ -f cargo.toml ] && mv cargo.toml Cargo.toml || true'';
    cargoHash = "sha256-ggn+MOfYEKJxuQP14jM0BYjK3/aMT2ddU0YnTx/l4gI=";
    doCheck = false; meta.mainProgram = "osint-tools-cli";
  };

  # ── SpiderFoot from source against current libs ────────────────────────────
  spiderfoot =
    let
      adblockparser = final.python3.pkgs.buildPythonPackage {
        pname = "adblockparser"; version = "0.7"; format = "setuptools";
        src = gh { owner = "scrapinghub"; repo = "adblockparser";
          rev = "4089612d65018d38dbb88dd7f697bcb07814014d";
          hash = "sha256-3Wx/VmOCaEWWvhxKBqA+IBjp67rjqrDTaqpeXaIE8pQ="; };
        doCheck = false;
      };
      pygexf = final.python3.pkgs.buildPythonPackage {
        pname = "pygexf"; version = "0.2.2"; format = "setuptools";
        src = gh { owner = "paulgirard"; repo = "pygexf";
          rev = "4ec08e9b8c381e030c30f86a562712b681d97e55";
          hash = "sha256-tMJSRjZ2sXBmeYLHKUQMG33orBAnTtObb+x2d8IBKNA="; };
        propagatedBuildInputs = with final.python3.pkgs; [ lxml setuptools ];
        doCheck = false;
      };
      pyenv = final.python3.withPackages (ps: with ps; [
        adblockparser pygexf dnspython exifread cherrypy cherrypy-cors mako
        beautifulsoup4 lxml netaddr pysocks requests ipwhois ipaddr phonenumbers
        pypdf2 python-whois secure pyopenssl python-docx python-pptx networkx
        cryptography publicsuffixlist openpyxl pyyaml
      ]);
    in prev.stdenvNoCC.mkDerivation {
      pname = "spiderfoot"; version = "0-unstable";
      src = gh { owner = "smicallef"; repo = "spiderfoot";
        rev = "0f815a203afebf05c98b605dba5cf0475a0ee5fd";
        hash = "sha256-LsaLgz+tZyTUBLxa7FoJusGgMa3sgLUMZMVPZUpvWdY="; };
      nativeBuildInputs = [ prev.makeWrapper ]; dontBuild = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/libexec/spiderfoot $out/bin
        cp -r . $out/libexec/spiderfoot/
        for e in sf:spiderfoot sfcli:spiderfoot-cli; do
          makeWrapper ${pyenv}/bin/python $out/bin/''${e##*:} \
            --add-flags "$out/libexec/spiderfoot/''${e%%:*}.py" --chdir "$out/libexec/spiderfoot"
        done
        runHook postInstall
      '';
      meta.mainProgram = "spiderfoot";
    };
}
