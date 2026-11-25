# Branding (MooreOS)

Everything shown before you're logged in comes from this folder: the boot
menu (GRUB), the splash while it starts (Plymouth, which also asks for the disk
password on an encrypted disk), and the login screen (ly). fastfetch shows the
chip too (pkgs/fastfetch/logo.txt).

| File | What it is |
|---|---|
| `branding.nix` | the name (MooreOS), the tagline (Moore Performance Industries), the colours |
| `chip.txt` | the mark: an "M" on a chip (Moore's law: transistors per chip double every ~2 years) |
| `wordmark.txt` | the MOORE banner (ANSI Shadow lettering) |
| `render.py` | turns the two text files into the glowing pictures and the login-screen art, at build time |

The art is plain text: edit `chip.txt` or `wordmark.txt` in any editor, keep the
lines the same length, rebuild (`nixup`). Block characters (█ ▀ ▄ ▐ ▌ ▪) glow
bright; line-drawing characters (╗ ║ ┤ ╷ …) are the dim outlines.

To use pictures instead, drop in `logo.png` (square, transparent),
`wordmark.png` and/or `grub-background.png` (1920×1080). They must be ordinary
8-bit PNGs: GRUB can't read 16-bit ones.

`bootSplash = false;` in settings.local.nix brings back plain scrolling text at boot.
