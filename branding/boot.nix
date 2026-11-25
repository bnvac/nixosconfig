# Boot and login screens, from this folder: branding.nix (name, tagline,
# colours) and dodeca.py (the logo: a tumbling ASCII dodecahedron), drawn at
# build time. Imported by core.nix.
#
#   GRUB      the boot menu: the solid, a thin ring, the menu below
#   Plymouth  the load screen: the solid spinning inside a thin ring, boot
#             messages scrolling like a terminal log, a dotted waveform,
#             viewfinder corners; the disk password prompt on encrypted disks
#   ly        the login screen: the solid spinning above the login box
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  b = import ./branding.nix;
  c = b.colors;

  # "#e6e6e6" → "0.9, 0.9, 0.9" (Plymouth wants 0–1 per channel); → "0x00E6E6E6" (ly)
  ch = hex: i: let v = lib.fromHexString (builtins.substring (1 + 2 * i) 2 hex);
               in builtins.toString (v / 255.0);
  rgb = hex: "${ch hex 0}, ${ch hex 1}, ${ch hex 2}";
  lyColor = hex: "0x00" + lib.toUpper (builtins.substring 1 6 hex);

  fonts = "${pkgs.dejavu_fonts}/share/fonts/truetype";
  mono = "${fonts}/DejaVuSansMono.ttf";
  magick = "${pkgs.imagemagick}/bin/magick";
  py = pkgs.python3.withPackages (p: [ p.pillow ]);
  dodeca = "${py}/bin/python3 -I ${./dodeca.py}";
  tagline = lib.toUpper b.tagline;
  spaced = str: lib.concatStringsSep " " (lib.stringToCharacters str);
  frames = 48;

  logo = pkgs.runCommand "moore-logo.png" { } "${dodeca} still 40 $out ${mono} 12";
  lyArt = pkgs.runCommand "moore-login.dur" { } "${dodeca} dur 18 36 $out ${lib.escapeShellArg b.tagline}";

  # ── Plymouth: the load screen ────────────────────────────────────────────
  plymouthTheme = pkgs.runCommand "plymouth-theme-moore" { } ''
    d=$out/share/plymouth/themes/moore
    mkdir -p $d
    ${dodeca} pngs 40 ${toString frames} $d ${mono} 11
    # the ring, a viewfinder corner, a waveform dot
    ${magick} -size 1200x1200 xc:none -fill none -stroke '${c.dim}' -strokewidth 2 \
      -draw "circle 600,600 600,4" -depth 8 PNG32:$d/ring.png
    i=0; for pl in "1,39 1,1 39,1" "1,1 39,1 39,39" "39,1 39,39 1,39" "39,39 1,39 1,1"; do
      ${magick} -size 40x40 xc:none -fill none -stroke '${c.text}' -strokewidth 2 \
        -draw "polyline $pl" -depth 8 PNG32:$d/corner-$i.png; i=$((i + 1))
    done
    ${magick} -size 3x3 xc:'${c.text}' -depth 8 PNG32:$d/dot.png
    cat > $d/moore.plymouth <<PLY
    [Plymouth Theme]
    Name=${b.name}
    Description=${b.name} load screen
    ModuleName=script

    [script]
    ImageDir=$d
    ScriptFile=$d/moore.script
    PLY
    cat > $d/moore.script <<'SCRIPT'
    Window.SetBackgroundTopColor(${rgb c.background});
    Window.SetBackgroundBottomColor(${rgb c.background});
    W = Window.GetWidth(); H = Window.GetHeight();
    CX = Math.Int(W / 2); CY = Math.Int(H * 0.44);

    # The ring.
    rs = Math.Int(H * 0.74);
    ring.image = Image("ring.png").Scale(rs, rs);
    ring.sprite = Sprite(ring.image);
    ring.sprite.SetPosition(CX - Math.Int(rs / 2), CY - Math.Int(rs / 2), 1);
    ring.sprite.SetOpacity(0.6);

    # The solid: ${toString frames} frames, one full tumble.
    ds = Math.Int(H * 0.50);
    for (i = 0; i < ${toString frames}; i++) {
      n = "" + i;
      if (i < 10) n = "00" + i; else if (i < 100) n = "0" + i;
      solid[i] = Image("frame-" + n + ".png");
      solid[i] = solid[i].Scale(ds, Math.Int(ds * solid[i].GetHeight() / solid[i].GetWidth()));
    }
    dodeca.sprite = Sprite(solid[0]);
    dodeca.sprite.SetPosition(CX - Math.Int(ds / 2), CY - Math.Int(solid[0].GetHeight() / 2), 2);

    # Viewfinder corners around the solid.
    q = Math.Int(H * 0.27);
    for (i = 0; i < 4; i++) corners[i] = Sprite(Image("corner-" + i + ".png"));
    corners[0].SetPosition(CX - q, CY - q, 3);
    corners[1].SetPosition(CX + q - 40, CY - q, 3);
    corners[2].SetPosition(CX + q - 40, CY + q - 40, 3);
    corners[3].SetPosition(CX - q, CY + q - 40, 3);
    for (i = 0; i < 4; i++) corners[i].SetOpacity(0.7);

    # The tagline under the ring.
    tag.image = Image.Text("${spaced tagline}", ${rgb c.dim}, 1, "Mono 11");
    tag.sprite = Sprite(tag.image);
    tagY = CY + Math.Int(rs / 2) + 24;
    tag.sprite.SetPosition(CX - Math.Int(tag.image.GetWidth() / 2), tagY, 3);

    # A terminal log, bottom left: what's starting, as it starts.
    LOGN = 14; LX = Math.Int(W * 0.035); LY = Math.Int(H * 0.56); LH = 17;
    log_text[0] = "${b.name} // boot";
    log_text[1] = "----------------------------";
    for (i = 2; i < LOGN; i++) log_text[i] = "";
    fun draw_log() {
      for (i = 0; i < LOGN; i++) {
        global.log_img[i] = Image.Text(global.log_text[i], ${rgb c.dim}, 1, "Mono 10");
        global.log_spr[i] = Sprite(global.log_img[i]);
        global.log_spr[i].SetPosition(LX, LY + i * LH, 3);
      }
    }
    log_count = 2;
    fun add_log(line) {
      if (global.log_count < LOGN) {
        global.log_text[global.log_count] = line;
        global.log_count++;
      } else {
        for (i = 2; i < LOGN - 1; i++) global.log_text[i] = global.log_text[i + 1];
        global.log_text[LOGN - 1] = line;
      }
      draw_log();
    }
    draw_log();
    fun on_status(status) { add_log("[ ok ] " + status); }
    Plymouth.SetUpdateStatusFunction(on_status);

    # A dotted waveform, bottom right: three noisy strands drifting.
    WN = 72; WX = Math.Int(W * 0.64); WW = Math.Int(W * 0.33); WY = Math.Int(H * 0.80);
    for (i = 0; i < WN; i++) for (j = 0; j < 3; j++) {
      wave[i * 3 + j] = Sprite(Image("dot.png"));
      wave[i * 3 + j].SetOpacity(0.25 + 0.25 * j);
    }
    fun draw_wave() {
      for (i = 0; i < WN; i++) for (j = 0; j < 3; j++) {
        x = WX + Math.Int(i * WW / WN);
        a = Math.Sin(i * 0.16 + global.t * 0.045 + j) * Math.Sin(i * 0.05 - global.t * 0.02);
        y = WY + Math.Int(a * (34 - j * 8) + (Math.Random() - 0.5) * 6 + j * 9);
        global.wave[i * 3 + j].SetPosition(x, y, 3);
      }
    }

    t = 0;
    asking = 0;
    fun refresh() {
      global.t++;
      f = Math.Int(global.t / 3) % ${toString frames};
      dodeca.sprite.SetImage(solid[f]);
      if (global.t % 2 == 0) draw_wave();
      blink = Math.Int(global.t / 25) % 2;
      for (i = 0; i < 4; i++) corners[i].SetOpacity(0.45 + 0.3 * blink);
    }
    Plymouth.SetRefreshFunction(refresh);

    # Encrypted disk: the password prompt, as a terminal line under the ring.
    fun show_password(prompt, bullets) {
      global.asking = 1;
      global.prompt_image = Image.Text("> " + prompt, ${rgb c.text}, 1, "Mono 13");
      global.prompt_sprite = Sprite(global.prompt_image);
      global.prompt_sprite.SetPosition(CX - Math.Int(global.prompt_image.GetWidth() / 2), tagY + 34, 4);
      stars = "";
      for (i = 0; i < bullets; i++) stars = stars + "*";
      global.bullets_image = Image.Text(stars + "_", ${rgb c.accent}, 1, "Mono 15");
      global.bullets_sprite = Sprite(global.bullets_image);
      global.bullets_sprite.SetPosition(CX - Math.Int(global.bullets_image.GetWidth() / 2), tagY + 64, 4);
    }
    Plymouth.SetDisplayPasswordFunction(show_password);
    fun show_normal() {
      global.asking = 0;
      global.prompt_sprite = NULL;
      global.bullets_sprite = NULL;
    }
    Plymouth.SetDisplayNormalFunction(show_normal);
    fun show_message(text) { add_log("[ .. ] " + text); }
    Plymouth.SetMessageFunction(show_message);
    SCRIPT
  '';

  # ── GRUB: the boot menu ──────────────────────────────────────────────────
  # GRUB reads only 8-bit PNGs (16-bit ones come out as rainbow garbage), so
  # every picture below is written with -depth 8.
  grubTheme = pkgs.runCommand "grub-theme-moore" { nativeBuildInputs = [ pkgs.grub2 ]; } ''
    mkdir -p $out/icons
    grub-mkfont -s 16 -o $out/mono-16.pf2 ${mono}
    grub-mkfont -s 20 -o $out/mono-20.pf2 ${mono}
    grub-mkfont -s 20 -o $out/mono-bold-20.pf2 ${fonts}/DejaVuSansMono-Bold.ttf

    # Background: the solid inside a thin ring, the tagline, viewfinder corners.
    ${magick} -size 1920x1080 xc:'${c.background}' \
      -fill none -stroke '${c.dim}' -strokewidth 1.5 -draw "circle 960,300 960,40" \
      -stroke '${c.text}' -strokewidth 2 \
      -draw "polyline 790,170 790,130 830,130" -draw "polyline 1090,130 1130,130 1130,170" \
      -draw "polyline 790,430 790,470 830,470" -draw "polyline 1090,470 1130,470 1130,430" \
      -stroke none \( ${logo} -resize 340x340 \) -gravity north -geometry +0+130 -composite \
      -font ${mono} -pointsize 18 -fill '${c.dim}' \
      -gravity north -annotate +0+580 '${spaced tagline}' \
      -depth 8 PNG24:$out/background.png

    # The selected entry: a bright left edge and a faint bar.
    ${magick} -size 4x46 xc:'${c.accent}' -depth 8 PNG32:$out/select_w.png
    ${magick} -size 4x46 xc:none -fill '${c.accent}' -draw "fill-opacity 0.09 rectangle 0,0 3,45" -depth 8 PNG32:$out/select_c.png
    ${magick} -size 4x46 xc:none -fill '${c.accent}' -draw "fill-opacity 0.09 rectangle 0,0 3,45" -depth 8 PNG32:$out/select_e.png

    # Icons by menu-entry class: this system, Windows, firmware settings.
    ${magick} ${logo} -resize 64x64 -depth 8 PNG32:$out/icons/nixos.png
    cp $out/icons/nixos.png $out/icons/submenu.png
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
      left = 34%
      top = 60%
      width = 32%
      height = 27%
      item_font = "DejaVu Sans Mono Regular 20"
      item_color = "${c.dim}"
      selected_item_font = "DejaVu Sans Mono Bold 20"
      selected_item_color = "${c.text}"
      selected_item_pixmap_style = "select_*.png"
      icon_width = 26
      icon_height = 26
      item_icon_space = 16
      item_height = 46
      item_padding = 14
      item_spacing = 6
      scrollbar = false
    }
    + label {
      id = "__timeout__"
      left = 0
      top = 90%
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
  # Quiet: the load screen instead of scrolling kernel text (Esc shows it).
  boot.consoleLogLevel = lib.mkIf splash 3;
  boot.initrd.verbose = lib.mkIf splash false;
  boot.kernelParams = lib.optionals splash [ "splash" "loglevel=3" "rd.udev.log_level=3" "systemd.show_status=auto" ];

  # ── ly: the login screen ─────────────────────────────────────────────────
  services.displayManager.ly.settings = {
    animation = "dur_file";
    dur_file_path = "${lyArt}";
    dur_offset_alignment = "topcenter";
    dur_y_offset = 1;
    full_color = true;
    box_title = tagline;
    fg = lyColor c.text;
    border_fg = lyColor c.dim;
    bg = "0x00000000";
    clock = "%a %d %b  %H:%M";
    hide_version_string = true;
    asterisk = "*";
  };
}
