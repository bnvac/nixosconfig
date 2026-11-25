# Branding (MooreOS)

Everything shown before you're logged in comes from this folder, and so does
fastfetch's logo:

| Screen | What it shows |
|---|---|
| Boot menu (GRUB) | the dodecahedron inside a thin ring, viewfinder corners, the menu |
| Load screen (Plymouth) | the dodecahedron tumbling inside the ring, boot messages scrolling like a terminal log, a dotted waveform; on an encrypted disk, `> Password for the disk` |
| Login screen (ly) | the dodecahedron tumbling above the login box |
| fastfetch | the dodecahedron spins for a moment, then stops at a random angle |

| File | What it is |
|---|---|
| `branding.nix` | the name (MooreOS), the tagline (Moore Performance Industries), the colours (monochrome) |
| `dodeca.py` | the logo: draws a dodecahedron in ASCII, cell by cell (each face shaded by how much light it catches, edges bright), as text frames, pictures, or the login screen's animation |
| `boot.nix` | puts it all together at build time |

Change the colours or tagline in `branding.nix`, or the solid's look in
`dodeca.py` (`RAMP` = the shading characters, `AXIS`/`TILT` = how it tumbles),
then `menu update` (or `rebuild`). `bootSplash = false;` in settings.local.nix
brings back plain scrolling text at boot.
