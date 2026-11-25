# Renders the ASCII art in this folder into the pictures used at boot, and
# the login screen's .dur file. Run by branding/boot.nix at build time.
#
#   render.py png ART.txt OUT.png FONT [size]   glowing phosphor picture
#   render.py dur OUT.dur TAGLINE ART.txt…       ly login-screen art (Durdraw v7)
import gzip
import json
import sys

BRIGHT = set("█▀▄▐▌▪")


def png(art, out, font_path, size=40):
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
    lines = open(art, encoding="utf-8").read().rstrip("\n").split("\n")
    font = ImageFont.truetype(font_path, size)
    x0, _, x1, _ = font.getbbox("█")
    cw = x1 - x0
    asc, desc = font.getmetrics()
    ch = asc + desc
    pad = size * 2
    w = max(len(l) for l in lines) * cw + 2 * pad
    h = len(lines) * ch + 2 * pad
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for r, line in enumerate(lines):
        t = r / max(1, len(lines) - 1)
        for i, c in enumerate(line):
            if c == " ":
                continue
            # main strokes bright phosphor (lighter at the top); outlines dim
            fill = (int(140 - 110 * t), 255, int(185 - 60 * t), 255) if c in BRIGHT else (40, 150, 95, 255)
            d.text((pad + i * cw, pad + r * ch), c, font=font, fill=fill)
    glow = img.filter(ImageFilter.GaussianBlur(size * 0.45))
    glow.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.85)))
    out_img = Image.alpha_composite(glow, img)
    out_img = out_img.crop(out_img.getbbox())
    # square-ish canvas for icons: pad to a square if it's nearly square
    W, H = out_img.size
    if 0.6 < W / H < 1.6:
        s = max(W, H)
        sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        sq.paste(out_img, ((s - W) // 2, (s - H) // 2))
        out_img = sq
    out_img.convert("RGBA").save(out)   # 8-bit RGBA: GRUB can read it


def dur(out, tagline, arts):
    rows = []
    for a in arts:
        if rows:
            rows.append("")
        rows += open(a, encoding="utf-8").read().rstrip("\n").split("\n")
    rows += ["", " ".join(tagline.upper())]          # M O O R E   P E R F O R M A N C E …
    width = max(len(r) for r in rows)
    rows = [r.center(width) for r in rows]
    n = len(rows)
    grad = [121, 121, 85, 85, 49, 48, 48, 48]          # 256-colour greens, light → deep
    def fg(c, y):
        if c in BRIGHT:
            return grad[min(len(grad) - 1, int(y / max(1, n - 1) * len(grad)))]
        return 29 if c != " " else 0                    # outlines dim green; blanks default
    # colorMap is [x][y] → [fg, bg]; bg 0 = the terminal's own background
    color_map = [[[fg(rows[y][x], y), 0] for y in range(n)] for x in range(width)]
    movie = {"DurMovie": {
        "formatVersion": 7, "colorFormat": "256", "preferredFont": "fixed", "encoding": "utf-8",
        "name": "MooreOS", "artist": "", "framerate": 1.0, "sizeX": width, "sizeY": n, "extra": None,
        "frames": [{"frameNumber": 1, "delay": 0, "contents": rows, "colorMap": color_map}],
    }}
    with gzip.open(out, "wt", encoding="utf-8") as f:
        json.dump(movie, f)


if __name__ == "__main__":
    if sys.argv[1] == "png":
        png(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]) if len(sys.argv) > 5 else 40)
    elif sys.argv[1] == "dur":
        dur(sys.argv[2], sys.argv[3], sys.argv[4:])
