# Draws nix²'s fastfetch logo, an eye, as terminal art: half-block
# characters (▀▄) in 24-bit colour, two pixels per character cell, so it
# looks solid in any font. Writes one file per eyelid position:
#   eye.py OUTDIR  →  OUTDIR/eye-0.txt (open) … eye-4.txt (closed),
#                     OUTDIR/space.txt (the blank logo fastfetch lays out)
# The fastfetch wrapper (pkgs/fastfetch/fastfetch.sh) draws eye-0 into the
# blank and plays the others in place to blink.
import math
import os
import sys

OUT = sys.argv[1]
W, H = 36, 22                 # pixels; H must be even (two per cell)
CX, CY = W / 2 - 0.5, 12.0    # eye centre
RX, RY = 16.5, 8.2            # almond half-width / half-height
FRAMES = [0.0, 0.3, 0.6, 0.85, 1.0]   # how far the upper lid has come down

SCLERA_HI, SCLERA_LO = (236, 238, 244), (170, 176, 192)
IRIS_IN, IRIS_OUT = (120, 205, 255), (28, 78, 150)
PUPIL = (10, 12, 20)
LID = (52, 60, 84)
LINER = (16, 18, 28)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def upper(x, t):
    """y of the upper lid edge at x (t=0 open, 1 closed)."""
    u = max(0.0, 1 - ((x - CX) / RX) ** 2)
    open_y = CY - RY * u ** 0.85
    shut_y = CY + RY * 0.75 * u ** 0.85 + 0.2   # closed: meets the lower lid
    return open_y + (shut_y - open_y) * t


def lower(x):
    u = max(0.0, 1 - ((x - CX) / RX) ** 2)
    return CY + RY * 0.75 * u ** 0.85


def pixel(x, y, t):
    """Colour of pixel (x, y) at lid position t, or None for background."""
    px, py = x + 0.5, y + 0.5
    if abs(px - CX) > RX + 0.6:
        return None
    up0, up, lo = upper(px, 0), upper(px, t), lower(px)
    # eyelashes: short strokes above the lid edge, following it down
    for k in range(-3, 4):
        lx = CX + k * 3.6
        if abs(px - lx) < 0.6 and abs(lx - CX) < RX - 2:
            edge = upper(lx, t)
            tip = edge - (2.2 - abs(k) * 0.25)
            if t >= 0.99:                      # closed: lashes hang down
                edge, tip = edge + 0.6, edge + 2.4 - abs(k) * 0.25
            if min(edge, tip) - 0.3 <= py <= max(edge, tip):
                return LINER
    if py < up0 - 1.0 or py > lo + 1.0:
        return None
    if abs(py - up) < 0.75 or abs(py - lo) < 0.6 and py <= lo + 0.6:
        return LINER                            # eyeliner along both lids
    if up0 - 1.0 <= py < up:
        return LID                              # the closing lid
    if up <= py <= lo:
        d = math.hypot(px - CX, py - CY)
        if d < 2.4:
            if math.hypot(px - (CX + 2.6), py - (CY - 2.6)) < 1.2:
                return (255, 255, 255)          # highlight
            return PUPIL
        if d < 6.8:
            if math.hypot(px - (CX + 2.6), py - (CY - 2.6)) < 1.2:
                return (255, 255, 255)
            a = math.atan2(py - CY, px - CX)
            streak = 0.12 * math.sin(a * 11) + 0.08 * math.sin(a * 23 + 1)
            c = lerp(IRIS_IN, IRIS_OUT, min(1, max(0, (d - 2.4) / 4.4 + streak)))
            if py - up < 2.5:                   # lid's shadow
                c = lerp(c, PUPIL, 0.35 * (1 - (py - up) / 2.5))
            return c
        if d < 7.4:
            return IRIS_OUT
        shade = min(1, abs(px - CX) / RX) ** 2
        c = lerp(SCLERA_HI, SCLERA_LO, shade)
        if py - up < 2.5:
            c = lerp(c, LID, 0.45 * (1 - (py - up) / 2.5))
        return c
    return None


def fg(c):
    return f"\x1b[38;2;{c[0]};{c[1]};{c[2]}m"


def bg(c):
    return f"\x1b[48;2;{c[0]};{c[1]};{c[2]}m"


def render(t):
    rows = []
    for r in range(H // 2):
        s = ""
        for x in range(W):
            top, bot = pixel(x, 2 * r, t), pixel(x, 2 * r + 1, t)
            if top is None and bot is None:
                s += "\x1b[0m "
            elif bot is None:
                s += "\x1b[0m" + fg(top) + "▀"
            elif top is None:
                s += "\x1b[0m" + fg(bot) + "▄"
            else:
                s += fg(top) + bg(bot) + "▀"
        rows.append(s + "\x1b[0m")
    return "\n".join(rows) + "\n"


os.makedirs(OUT, exist_ok=True)
for i, t in enumerate(FRAMES):
    with open(os.path.join(OUT, f"eye-{i}.txt"), "w") as f:
        f.write(render(t))
# The logo fastfetch lays out: blank where the eye goes (the wrapper draws
# it there afterwards), then the name. A row of spaces would be trimmed, so
# each row ends in a braille blank, which takes up a column and shows nothing.
with open(os.path.join(OUT, "space.txt"), "w") as f:
    f.write(("$1" + " " * (W - 1) + "\u2800\n") * (H // 2))
    f.write("\n$2" + " " * ((W - 7) // 2) + "n i x ²\n")
print(f"{len(FRAMES)} frames, {W} columns × {H // 2} rows")
