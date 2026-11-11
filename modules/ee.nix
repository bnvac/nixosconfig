# Hardware & electronics: design boards, program microcontrollers, build
# keyboards, 3D print. Plug a board in and it just works — no sudo, no
# fiddling with permissions:
#   - USB serial (Arduino, ESP32, Pico, USB-serial adapters): the dialout group
#   - Pico / RP2040 (picotool), debug probes (ST-Link, CMSIS-DAP, J-Link via
#     probe-rs and OpenOCD), STM32 DFU, Teensy, logic analysers (sigrok),
#     QMK/Vial keyboards (Hack Club Hackpad), RTL-SDR radios, Flipper Zero
#
#   hearth serial          pick a board by name, see its output (tio)
#   hearth new board NAME  a PlatformIO project (Pico/ESP32/Arduino):
#                          just flash · just monitor
#   hearth new micropython NAME   the same in MicroPython
{ pkgs, ... }:
let
  app = label: run: { inherit label run; needs = run; };
in
{
  my.packages = with pkgs; [
    # circuit design & simulation
    kicad ngspice qucs-s logisim-evolution gtkwave iverilog
    # logic analysers
    pulseview sigrok-cli
    # microcontrollers: build, flash, debug, talk to
    platformio arduino-ide avrdude openocd gdb
    picotool elf2uf2-rs                # Raspberry Pi Pico / RP2040
    esptool espflash                   # ESP32 / ESP8266
    probe-rs-tools stlink dfu-util     # debug probes, STM32
    mpremote thonny                    # MicroPython / CircuitPython
    tio picocom minicom                # serial terminals (tio reconnects by itself)
    flashrom                           # read/write SPI flash chips
    # keyboards (QMK firmware, Vial keymaps)
    qmk vial
    # 3D printing / CAD
    orca-slicer freecad openscad       # OrcaSlicer has Elegoo printer profiles built in
  ];

  # Permission to talk to the hardware above, for the logged-in user.
  services.udev.packages = with pkgs; [ picotool probe-rs-tools stlink openocd libsigrok teensy-udev-rules ];
  hardware.keyboard.qmk.enable = true;       # QMK keyboards and their bootloaders
  hardware.rtl-sdr.enable = true;            # cheap SDR radio dongles
  hardware.flipperzero.enable = true;
  services.udev.extraRules = ''
    # Vial / VIA keymap editors (and WebHID in the browser): raw HID, for the
    # user at the screen only (not Vial's own world-writable rule).
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", TAG+="uaccess"
    # STM32 and other chips in DFU mode (dfu-util)
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="df11", TAG+="uaccess"
    # RP2040 / RP2350 BOOTSEL mode (picotool's rules cover these too; harmless)
    SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", TAG+="uaccess"
  '';

  # In the menu next to the coding tools (each shows only if installed).
  my.menu."Code & engineering" = [
    { label = "Serial monitor (pick a board)"; run = "hearth serial"; mode = "tty"; }
    { label = "New board project (Pico, ESP32, Arduino…)"; run = "hearth new board"; mode = "term"; }
    (app "KiCad (circuit boards)" "kicad")
    (app "FreeCAD (3D CAD)" "freecad")
    (app "OpenSCAD (code-based CAD)" "openscad")
    (app "OrcaSlicer (3D printing)" "orca-slicer")
    (app "PulseView (logic analyser)" "pulseview")
    (app "Logisim (digital logic)" "logisim-evolution")
    (app "Arduino IDE" "arduino-ide")
    (app "Thonny (MicroPython / CircuitPython)" "thonny")
    { label = "Vial (keyboard keymaps)"; run = "Vial"; needs = "Vial"; }
  ];
}
