# Boot and login screens: the GRUB menu, the Plymouth splash and the ly login
# screen, all from this folder: branding.nix (name, tagline, colours) and the
# ASCII art (chip.txt, wordmark.txt), rendered at build time by render.py.
# Drop a logo.png / wordmark.png / grub-background.png here to use your own
# pictures instead. Imported by core.nix.
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  b = import ./branding.nix;
  c = b.colors;
  have = f: builtins.pathExists (./. + "/${f}");

  # "#33ff99" → "0.2, 1, 0.6" (Plymouth wants 0–1 per channel); → "0x0033FF99" (ly)
  ch = hex: i: let v = lib.fromHexString (builtins.substring (1 + 2 * i) 2 hex);
               in builtins.toString (v / 255.0);
  rgb = hex: "${ch hex 0}, ${ch hex 1}, ${ch hex 2}";
  lyColor = hex: "0x00" + lib.toUpper (builtins.substring 1 6 hex);

  fonts = "${pkgs.dejavu_fonts}/share/fonts/truetype";
  magick = "${pkgs.imagemagick}/bin/magick";
  py = pkgs.python3.withPackages (p: [ p.pillow ]);
  render = "${py}/bin/python3 -I ${./render.py}";
  tagline = lib.toUpper b.tagline;

  # The pictures: ASCII art in phosphor green with a glow (or yours).
  logo = if have "logo.png" then ./logo.png else pkgs.runCommand "moore-logo.png" { } ''
    ${render} png ${./chip.txt} $out ${fonts}/DejaVuSansMono.ttf 60
  '';
  wordmark = if have "wordmark.png" then ./wordmark.png else pkgs.runCommand "moore-wordmark.png" { } ''
    ${render} png ${./wordmark.txt} $out ${fonts}/DejaVuSansMono.ttf 40
  '';
  dot = pkgs.runCommand "dot.png" { } ''
    ${magick} -size 14x14 xc:none -fill '${c.accent}' -draw "circle 7,7 7,1" -depth 8 PNG32:$out
  '';
  # The login screen's art (ly draws .dur files: text + 256 colours).
  lyArt = pkgs.runCommand "moore-login.dur" { } ''
    ${render} dur $out ${lib.escapeShellArg b.tagline} ${./chip.txt} ${./wordmark.txt}
  '';

  # ── Plymouth: the splash while it starts ─────────────────────────────────
  plymouthTheme = pkgs.runCommand "plymouth-theme-moore" { } ''
    d=$out/share/plymouth/themes/moore
    mkdir -p $d
    cp ${logo} $d/logo.png
    cp ${wordmark} $d/wordmark.png
    cp ${dot} $d/dot.png
    cat > $d/moore.plymouth <<PLY
    [Plymouth Theme]
    Name=${b.name}
    Description=${b.name} boot splash
    ModuleName=script

    [script]
    ImageDir=$d
    ScriptFile=$d/moore.script
    PLY
    cat > $d/moore.script <<'SCRIPT'
    Window.SetBackgroundTopColor(${rgb c.background});
    Window.SetBackgroundBottomColor(${rgb c.background});
    W = Window.GetWidth(); H = Window.GetHeight();

    # The chip, then the wordmark under it, centred a little above the middle.
    chip.raw = Image("logo.png");
    cs = Math.Int(H * 0.17);
    chip.image = chip.raw.Scale(cs, cs);
    chip.sprite = Sprite(chip.image);
    chipY = Math.Int(H * 0.22);
    chip.sprite.SetPosition(Math.Int((W - cs) / 2), chipY, 1);

    wm.raw = Image("wordmark.png");
    ww = Math.Int(W * 0.36);
    wh = Math.Int(ww * wm.raw.GetHeight() / wm.raw.GetWidth());
    wm.image = wm.raw.Scale(ww, wh);
    wm.sprite = Sprite(wm.image);
    wmY = chipY + cs + Math.Int(H * 0.03);
    wm.sprite.SetPosition(Math.Int((W - ww) / 2), wmY, 1);

    tag.image = Image.Text("${tagline}", ${rgb c.dim}, 1, "Mono 13");
    tag.sprite = Sprite(tag.image);
    nameY = wmY + wh + 18;
    tag.sprite.SetPosition(Math.Int((W - tag.image.GetWidth()) / 2), nameY, 1);

    # Three dots that pulse while it loads.
    for (i = 0; i < 3; i++) {
      dots[i].sprite = Sprite(Image("dot.png"));
      dots[i].sprite.SetPosition(Math.Int(W / 2 - 37 + i * 30), nameY + 60, 1);
    }
    t = 0;
    asking = 0;
    fun refresh() {
      t++;
      for (i = 0; i < 3; i++) {
        if (global.asking) dots[i].sprite.SetOpacity(0);
        else dots[i].sprite.SetOpacity(0.2 + 0.8 * Math.Abs(Math.Sin(t / 16 - i * 0.7)));
      }
    }
    Plymouth.SetRefreshFunction(refresh);

    # Encrypted disk: the password prompt, as a terminal line. (Sprites must be
    # global: a function's own variables vanish, and their sprites with them.)
    fun show_password(prompt, bullets) {
      global.asking = 1;
      global.prompt_image = Image.Text("> " + prompt, ${rgb c.text}, 1, "Mono 14");
      global.prompt_sprite = Sprite(global.prompt_image);
      global.prompt_sprite.SetPosition(Math.Int((W - global.prompt_image.GetWidth()) / 2), nameY + 55, 2);
      stars = "";
      for (i = 0; i < bullets; i++) stars = stars + "*";
      global.bullets_image = Image.Text(stars + "_", ${rgb c.accent}, 1, "Mono 16");
      global.bullets_sprite = Sprite(global.bullets_image);
      global.bullets_sprite.SetPosition(Math.Int((W - global.bullets_image.GetWidth()) / 2), nameY + 90, 2);
    }
    Plymouth.SetDisplayPasswordFunction(show_password);
    fun show_normal() {
      global.asking = 0;
      global.prompt_sprite = NULL;
      global.bullets_sprite = NULL;
    }
    Plymouth.SetDisplayNormalFunction(show_normal);

    # Messages (e.g. "checking the disk") in small print at the bottom.
    fun show_message(text) {
      global.msg_image = Image.Text(text, ${rgb c.dim}, 1, "Mono 12");
      global.msg_sprite = Sprite(global.msg_image);
      global.msg_sprite.SetPosition(Math.Int((W - global.msg_image.GetWidth()) / 2), Math.Int(H * 0.92), 2);
    }
    Plymouth.SetMessageFunction(show_message);
    SCRIPT
  '';

  # ── GRUB: the boot menu ──────────────────────────────────────────────────
  # GRUB reads only 8-bit PNGs (16-bit ones come out as rainbow garbage), so
  # every picture below is written with -depth 8.
  grubTheme = pkgs.runCommand "grub-theme-moore" { nativeBuildInputs = [ pkgs.grub2 ]; } ''
    mkdir -p $out/icons
    grub-mkfont -s 16 -o $out/mono-16.pf2 ${fonts}/DejaVuSansMono.ttf
    grub-mkfont -s 20 -o $out/mono-20.pf2 ${fonts}/DejaVuSansMono.ttf
    grub-mkfont -s 20 -o $out/mono-bold-20.pf2 ${fonts}/DejaVuSansMono-Bold.ttf

    # Background: the colour, faint scanlines, the chip, the wordmark, the tagline.
    ${if have "grub-background.png" then "cp ${./grub-background.png} $out/background.png" else ''
      ${magick} -size 1920x1080 xc:'${c.background}' \
        \( -size 1920x1080 xc:none -fill '${c.accent}' -draw "circle 960,300 960,640" \
           -channel A -evaluate multiply 0.06 +channel -blur 0x170 \) -compose over -composite \
        \( -size 1x4 xc:none -fill '#000000' -draw "point 0,3" -channel A -evaluate set 30% +channel \
           -write mpr:scan +delete -size 1920x1080 tile:mpr:scan \) -compose over -composite \
        \( ${logo} -resize 170x170 \) -gravity north -geometry +0+95 -composite \
        \( ${wordmark} -resize 620x \) -gravity north -geometry +0+290 -composite \
        -font ${fonts}/DejaVuSansMono.ttf -pointsize 20 -fill '${c.dim}' \
        -gravity north -annotate +0+478 '${lib.concatStringsSep " " (lib.stringToCharacters tagline)}' \
        -depth 8 PNG24:$out/background.png
    ''}

    # The selected entry: a sharp terminal-style bar with a bright left edge.
    ${magick} -size 6x48 xc:'${c.accent}' -depth 8 PNG32:$out/select_w.png
    ${magick} -size 4x48 xc:none -fill '${c.accent}' -draw "fill-opacity 0.14 rectangle 0,0 3,47" -depth 8 PNG32:$out/select_c.png
    ${magick} -size 4x48 xc:none -fill '${c.accent}' -draw "fill-opacity 0.14 rectangle 0,0 3,47" -depth 8 PNG32:$out/select_e.png

    # Icons by menu-entry class: this system, Windows, firmware settings.
    ${magick} ${logo} -resize 64x64 -depth 8 PNG32:$out/icons/nixos.png
    cp $out/icons/nixos.png $out/icons/submenu.png      # "All configurations"
    ${magick} -size 64x64 xc:none -fill '${c.text}' \
      -draw "rectangle 8,8 30,30" -draw "rectangle 34,8 56,30" \
      -draw "rectangle 8,34 30,56" -draw "rectangle 34,34 56,56" -depth 8 PNG32:$out/icons/windows.png
    ${magick} -size 64x64 xc:none -fill none -stroke '${c.text}' -strokewidth 5 \
      -draw "circle 32,32 32,14" -draw "line 32,4 32,14" -draw "line 32,50 32,60" \
      -draw "line 4,32 14,32" -draw "line 50,32 60,32" -depth 8 PNG32:$out/icons/uefi.png

    cat > $out/theme.txt <<'EOF'
    title-text: ""
    desktop-image: "background.png"
    desktop-image-scale-method: "crop"
    desktop-color: "${c.background}"
    terminal-font: "DejaVu Sans Mono Regular 16"
    terminal-left: "10%"
    terminal-top: "10%"
    terminal-width: "80%"
    terminal-height: "80%"

    + boot_menu {
      left = 33%
      top = 53%
      width = 34%
      height = 32%
      item_font = "DejaVu Sans Mono Regular 20"
      item_color = "${c.dim}"
      selected_item_font = "DejaVu Sans Mono Bold 20"
      selected_item_color = "${c.text}"
      selected_item_pixmap_style = "select_*.png"
      icon_width = 28
      icon_height = 28
      item_icon_space = 16
      item_height = 48
      item_padding = 14
      item_spacing = 8
      scrollbar = false
    }

    # The countdown, then the keys.
    + label {
      id = "__timeout__"
      left = 0
      top = 89%
      width = 100%
      height = 30
      align = "center"
      font = "DejaVu Sans Mono Regular 16"
      color = "${c.dim}"
      text = "> booting in %d s_"
    }
    + label {
      left = 0
      top = 94%
      width = 100%
      height = 30
      align = "center"
      font = "DejaVu Sans Mono Regular 16"
      color = "${c.dim}"
      text = "[↑↓] select   [enter] boot   [e] edit"
    }
    EOF
  '';

  splash = s.bootSplash or true;
in
{
  boot.loader.grub.theme = lib.mkIf (s.useGrub or true) grubTheme;
  boot.loader.grub.splashImage = null;

  boot.plymouth = lib.mkIf splash {
    enable = true;
    theme = "moore";
    themePackages = [ plymouthTheme ];
  };
  # Quiet: the splash instead of scrolling kernel text (Esc during boot shows it).
  boot.consoleLogLevel = lib.mkIf splash 3;
  boot.initrd.verbose = lib.mkIf splash false;
  boot.kernelParams = lib.optionals splash [ "splash" "loglevel=3" "rd.udev.log_level=3" "systemd.show_status=auto" ];

  # ── ly: the login screen ─────────────────────────────────────────────────
  # The chip + MOORE at the top, the tagline on the login box, green on black.
  services.displayManager.ly.settings = {
    animation = "dur_file";
    dur_file_path = "${lyArt}";
    dur_offset_alignment = "topcenter";
    dur_y_offset = 1;
    full_color = true;
    box_title = tagline;
    fg = lyColor c.text;
    border_fg = lyColor c.accent;
    bg = "0x00000000";
    clock = "%a %d %b  %H:%M";
    hide_version_string = true;
    asterisk = "*";
  };
}
