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

  grubTheme = pkgs.runCommand "grub-theme-parajynx" { nativeBuildInputs = [ pkgs.grub2 ]; } ''
    mkdir -p $out
    grub-mkfont -s 18 -o $out/dejavu-18.pf2 ${font}
    grub-mkfont -s 14 -o $out/dejavu-14.pf2 ${font}
    ${if have "grub-background.png" then "cp ${./grub-background.png} $out/background.png" else ''
      ${magick} -size 1920x1080 xc:'${c.background}' \
        \( ${logo} -resize 220x220 \) -gravity center -geometry +0-150 -composite \
        -font ${font} -pointsize 44 -fill '${c.text}' -gravity center -annotate +0+0 '${b.name}' \
        $out/background.png
    ''}
    cat > $out/theme.txt <<'EOF'
    title-text: ""
    desktop-image: "background.png"
    desktop-color: "${c.background}"
    terminal-font: "DejaVu Sans Regular 14"

    + boot_menu {
      left = 35%
      width = 30%
      top = 58%
      height = 28%
      item_font = "DejaVu Sans Regular 18"
      item_color = "${c.dim}"
      selected_item_font = "DejaVu Sans Regular 18"
      selected_item_color = "${c.accent}"
      item_height = 38
      item_padding = 6
      item_spacing = 6
      scrollbar = false
    }
    + label {
      id = "__timeout__"
      left = 0
      width = 100%
      top = 92%
      align = "center"
      font = "DejaVu Sans Regular 14"
      color = "${c.dim}"
      text = "Starting in %d s · ↑↓ to choose, Enter to start"
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
