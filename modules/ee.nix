# Electrical engineering + 3D printing / CAD.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # EDA / EE
    kicad ngspice qucs-s pulseview sigrok-cli logisim-evolution gtkwave iverilog
    platformio arduino-ide avrdude openocd picocom minicom gdb
    # 3D printing / CAD
    orca-slicer freecad openscad
    elegoo-slicer                     # `elegoo-slicer` (self-fetching AppImage)
    (makeDesktopItem {
      name = "elegoo-slicer"; desktopName = "Elegoo Slicer";
      exec = "elegoo-slicer %F"; icon = "orca-slicer"; categories = [ "Graphics" "Engineering" ];
      comment = "Elegoo Slicer (fetched on first run)";
    })
  ];
}
