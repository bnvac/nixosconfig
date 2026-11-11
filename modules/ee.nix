# Electrical engineering + 3D printing / CAD.
{ pkgs, ... }:
let
  app = label: run: { inherit label run; needs = run; };
in
{
  my.packages = with pkgs; [
    # EDA / EE
    kicad ngspice qucs-s pulseview sigrok-cli logisim-evolution gtkwave iverilog
    platformio arduino-ide avrdude openocd picocom minicom gdb
    # 3D printing / CAD
    orca-slicer freecad openscad      # OrcaSlicer has Elegoo printer profiles built in
  ];
  # In the menu next to the coding tools (each shows only if installed).
  my.menu."Code & engineering" = [
    (app "KiCad (circuit boards)" "kicad")
    (app "FreeCAD (3D CAD)" "freecad")
    (app "OpenSCAD (code-based CAD)" "openscad")
    (app "OrcaSlicer (3D printing)" "orca-slicer")
    (app "PulseView (logic analyser)" "pulseview")
    (app "Logisim (digital logic)" "logisim-evolution")
    (app "Arduino IDE" "arduino-ide")
    { label = "Serial console (picocom, 115200)"; run = "picocom -b 115200 /dev/ttyUSB0"; mode = "tty"; needs = "picocom"; }
  ];
}
