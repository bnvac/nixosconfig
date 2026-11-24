# Branding

Everything parajynx shows before you log in comes from this folder.
Placeholders are drawn automatically until you add your own files.

| File | What it is | Size |
|---|---|---|
| `branding.nix` | the name under the logo, and the colours | |
| `logo.png` | the logo on the boot splash (and the boot menu) | square, transparent, 512×512 or bigger |
| `grub-background.png` | (optional) the boot menu's whole background | 1920×1080 (it's scaled) |

Add or change a file, then rebuild (`nixup`). With no `grub-background.png`, the
boot menu background is made from `logo.png`, the name and the colours.

The boot menu draws its own icons per entry (this system: your logo; Windows; firmware settings),
a soft accent pill on the selected entry, and a countdown. Pictures you add must be ordinary 8-bit
PNGs (GRUB can't read 16-bit ones; most apps save 8-bit already).

Where they're used: the splash while the system starts (Plymouth, which also
asks for your disk password if the disk is encrypted) and the GRUB boot menu.
Settings: `bootSplash = false;` in settings.local.nix brings back the plain
scrolling text at boot.
