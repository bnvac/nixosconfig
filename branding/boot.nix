# The boot screen: GRUB menu + Plymouth splash, from ./branding.nix and the
# pictures next to it (placeholders when they're missing). Imported by core.nix.
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  b = import ./branding.nix;
  c = b.colors;
  have = f: builtins.pathExists (./. + "/${f}");

  # "#8aa4c8" → "0.541" (Plymouth wants 0–1 per channel)
  ch = hex: i: let v = lib.fromHexString (builtins.substring (1 + 2 * i) 2 hex);
               in builtins.toString (v / 255.0);
  rgb = hex: "${ch hex 0}, ${ch hex 1}, ${ch hex 2}";

  font = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf";
  magick = "${pkgs.imagemagick}/bin/magick";

  # Placeholder logo: a ring with two parallel bars (并行, "in parallel").
  logo = if have "logo.png" then ./logo.png else pkgs.runCommand "parajynx-logo.png" { } ''
    ${magick} -size 512x512 xc:none -fill none -stroke '${c.accent}' -strokewidth 22 \
      -draw "circle 256,256 256,40" -stroke none -fill '${c.text}' \
      -draw "roundrectangle 196,150 232,362 14,14" -draw "roundrectangle 280,150 316,362 14,14" \
      PNG32:$out
  '';
  dot = pkgs.runCommand "dot.png" { } ''
    ${magick} -size 14x14 xc:none -fill '${c.accent}' -draw "circle 7,7 7,1" PNG32:$out
  '';

  plymouthTheme = pkgs.runCommand "plymouth-theme-parajynx" { } ''
    d=$out/share/plymouth/themes/parajynx
    mkdir -p $d
    cp ${logo} $d/logo.png
    cp ${dot} $d/dot.png
    cat > $d/parajynx.plymouth <<PLY
    [Plymouth Theme]
    Name=${b.name}
    Description=${b.name} boot splash
    ModuleName=script

    [script]
    ImageDir=$d
    ScriptFile=$d/parajynx.script
    PLY
    cat > $d/parajynx.script <<'SCRIPT'
    Window.SetBackgroundTopColor(${rgb c.background});
    Window.SetBackgroundBottomColor(${rgb c.background});
    W = Window.GetWidth(); H = Window.GetHeight();

    # The logo: a quarter of the screen's height, centred a little above the middle.
    logo.raw = Image("logo.png");
    size = Math.Int(H / 4);
    logo.image = logo.raw.Scale(size, size);
    logo.sprite = Sprite(logo.image);
    logo.sprite.SetPosition(Math.Int((W - size) / 2), Math.Int(H * 0.42 - size / 2), 1);

    name.image = Image.Text("${b.name}", ${rgb c.text}, 1, "Sans 22");
    name.sprite = Sprite(name.image);
    nameY = Math.Int(H * 0.42 + size / 2 + 28);
    name.sprite.SetPosition(Math.Int((W - name.image.GetWidth()) / 2), nameY, 1);

    # Three dots that breathe while it loads.
    for (i = 0; i < 3; i++) {
      dots[i].sprite = Sprite(Image("dot.png"));
      dots[i].sprite.SetPosition(Math.Int(W / 2 - 37 + i * 30), nameY + 70, 1);
    }
    t = 0;
    asking = 0;
    fun refresh() {
      t++;
      for (i = 0; i < 3; i++) {
        if (global.asking) dots[i].sprite.SetOpacity(0);
        else dots[i].sprite.SetOpacity(0.25 + 0.75 * Math.Abs(Math.Sin(t / 18 - i * 0.7)));
      }
    }
    Plymouth.SetRefreshFunction(refresh);

    # Encrypted disk: the password prompt, in the same style. (Sprites must be
    # global: a function's own variables vanish, and their sprites with them.)
    fun show_password(prompt, bullets) {
      global.asking = 1;
      global.prompt_image = Image.Text(prompt, ${rgb c.text}, 1, "Sans 14");
      global.prompt_sprite = Sprite(global.prompt_image);
      global.prompt_sprite.SetPosition(Math.Int((W - global.prompt_image.GetWidth()) / 2), nameY + 60, 2);
      stars = "";
      for (i = 0; i < bullets; i++) stars = stars + "● ";
      if (bullets == 0) stars = "_";
      global.bullets_image = Image.Text(stars, ${rgb c.accent}, 1, "Sans 16");
      global.bullets_sprite = Sprite(global.bullets_image);
      global.bullets_sprite.SetPosition(Math.Int((W - global.bullets_image.GetWidth()) / 2), nameY + 95, 2);
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
      global.msg_image = Image.Text(text, ${rgb c.dim}, 1, "Sans 12");
      global.msg_sprite = Sprite(global.msg_image);
      global.msg_sprite.SetPosition(Math.Int((W - global.msg_image.GetWidth()) / 2), Math.Int(H * 0.92), 2);
    }
    Plymouth.SetMessageFunction(show_message);
    SCRIPT
  '';

  # GRUB reads only 8-bit PNGs (16-bit ones come out as rainbow garbage), so
  # every picture below is written with -depth 8.
  # The boot menu. Centred on the logo and name, entries with an icon each,
  # the selected one in a soft accent pill, and the countdown underneath.
  fontBold = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf";
  grubTheme = pkgs.runCommand "grub-theme-parajynx" { nativeBuildInputs = [ pkgs.grub2 ]; } ''
    mkdir -p $out/icons
    grub-mkfont -s 16 -o $out/dejavu-16.pf2 ${font}
    grub-mkfont -s 20 -o $out/dejavu-20.pf2 ${font}
    grub-mkfont -s 20 -o $out/dejavu-bold-20.pf2 ${fontBold}

    # Background: the colour, a faint glow behind the logo, a few parallel
    # lines (并行) along the bottom, the logo and the name.
    ${if have "grub-background.png" then "cp ${./grub-background.png} $out/background.png" else ''
      ${magick} -size 1920x1080 xc:'${c.background}' \
        \( -size 1920x1080 xc:none -fill '${c.accent}' -draw "circle 960,330 960,700" \
           -channel A -evaluate multiply 0.09 +channel -blur 0x160 \) -compose over -composite \
        -stroke '${c.accent}' -strokewidth 2 -fill none \
        -draw "stroke-opacity 0.10 line -100,1080 700,760" \
        -draw "stroke-opacity 0.07 line -40,1080 760,760" \
        -draw "stroke-opacity 0.10 line 1220,320 2020,0" \
        -draw "stroke-opacity 0.07 line 1280,320 2080,0" \
        \( ${logo} -resize 150x150 \) -gravity north -geometry +0+190 -compose over -composite \
        -font ${fontBold} -pointsize 40 -fill '${c.text}' -gravity north -annotate +0+360 '${b.name}' \
        -depth 8 PNG24:$out/background.png
    ''}

    # The selected entry: a rounded pill (left cap, middle, right cap).
    ${magick} -size 52x52 xc:none -fill '${c.accent}' -draw "fill-opacity 0.20 circle 26,26 26,0" -crop 26x52+0+0 +repage -depth 8 PNG32:$out/select_w.png
    ${magick} -size 52x52 xc:none -fill '${c.accent}' -draw "fill-opacity 0.20 circle 26,26 26,0" -crop 26x52+26+0 +repage -depth 8 PNG32:$out/select_e.png
    ${magick} -size 4x52 xc:none -fill '${c.accent}' -draw "fill-opacity 0.20 rectangle 0,0 3,51" -depth 8 PNG32:$out/select_c.png

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
    terminal-font: "DejaVu Sans Regular 16"
    terminal-left: "10%"
    terminal-top: "10%"
    terminal-width: "80%"
    terminal-height: "80%"

    + boot_menu {
      left = 32%
      top = 46%
      width = 36%
      height = 38%
      item_font = "DejaVu Sans Regular 20"
      item_color = "${c.dim}"
      selected_item_font = "DejaVu Sans Bold 20"
      selected_item_color = "${c.text}"
      selected_item_pixmap_style = "select_*.png"
      icon_width = 30
      icon_height = 30
      item_icon_space = 18
      item_height = 52
      item_padding = 14
      item_spacing = 10
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
      font = "DejaVu Sans Regular 16"
      color = "${c.dim}"
      text = "Starting in %d s"
    }
    + label {
      left = 0
      top = 94%
      width = 100%
      height = 30
      align = "center"
      font = "DejaVu Sans Regular 16"
      color = "${c.dim}"
      text = "↑ ↓ choose   ·   Enter start   ·   e edit"
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
    theme = "parajynx";
    themePackages = [ plymouthTheme ];
  };
  # Quiet: the splash instead of scrolling kernel text (Esc during boot shows it).
  boot.consoleLogLevel = lib.mkIf splash 3;
  boot.initrd.verbose = lib.mkIf splash false;
  boot.kernelParams = lib.optionals splash [ "splash" "loglevel=3" "rd.udev.log_level=3" "systemd.show_status=auto" ];
}
