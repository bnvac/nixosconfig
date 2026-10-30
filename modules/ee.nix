# Electrical engineering + 3D printing / CAD.
{ pkgs, ... }:
{
  my.packages = with pkgs; [
    # EDA / EE
    kicad ngspice qucs-s pulseview sigrok-cli logisim-evolution gtkwave iverilog
    platformio arduino-ide avrdude openocd picocom minicom gdb
    # 3D printing / CAD
    orca-slicer freecad openscad      # OrcaSlicer has Elegoo printer profiles built in
  ];
}
