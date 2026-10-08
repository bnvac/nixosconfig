# Custom packages built from source / upstream binaries. One overlay.
final: prev:
let
  s = import ../settings.nix;
  gh = args: prev.fetchFromGitHub args;
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
      substituteInPlace config.h --replace-fail '#define BROWSER "librewolf"' '#define BROWSER "chromium"'
      substituteInPlace config.h --replace-fail "/usr/local/share/dwm/larbs.mom" "$out/share/dwm/larbs.mom"
      substituteInPlace config.h \
        --replace-fail '{ "xbacklight", "-inc", "15", NULL }' '{ "brightnessctl", "set", "10%+", NULL }' \
        --replace-fail '{ "xbacklight", "-dec", "15", NULL }' '{ "brightnessctl", "set", "10%-", NULL }'
      cat > larbs-extra-keys.h <<'KEYS'
      { MODKEY|ShiftMask, XK_Tab,       spawn, {.v = (const char*[]){ "tor-browser", NULL } } },
      { MODKEY|ShiftMask, XK_backslash, spawn, {.v = (const char*[]){ TERMINAL, "-e", "tmux", "new-session", "-A", "-s", "main", NULL } } },
      { MODKEY|ShiftMask, XK_Escape,    spawn, SHCMD(TERMINAL " -e sh -c 'fastfetch; read -r _'") },
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
    postPatch = ''substituteInPlace config.h --replace-fail 'float alpha = 0.8;' 'float alpha = ${s.stAlpha};' '';
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
        --replace-fail '*.alpha: 0.8' '*.alpha: ${s.stAlpha}'
      chmod -R +w $out/bin
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

  # ── Grok Bot — xAI/Cursor's official desktop agent (AppImage) ──────────────
  grok-bot = prev.appimageTools.wrapType2 rec {
    pname = "grok-bot"; version = "0.68.1";
    src = prev.fetchurl {
      url = "https://downloads.cursor.com/grokbot/stable/33103062f95061ccf9c81c5b365d37ab152c3b66/linux/x64/Grok_Bot_${version}.AppImage";
      hash = "sha256-L+fFrOzM1VehM7DGGSmX7AwTIPHp/Hvv/MprXozvuls=";
    };
    extraInstallCommands =
      let ex = prev.appimageTools.extractType2 { inherit pname version src; }; in ''
        install -Dm644 ${ex}/grok-bot.desktop -t $out/share/applications 2>/dev/null || true
        cp -r ${ex}/usr/share/icons $out/share/ 2>/dev/null || true
      '';
    meta = { description = "Grok Bot desktop agent (xAI/Cursor)"; mainProgram = "grok-bot";
             license = prev.lib.licenses.unfree; };
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
