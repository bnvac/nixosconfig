# dodeca.py — MooreOS's logo: a dodecahedron tumbling in ASCII.
#
# Each frame is drawn like a terminal would draw it: every character cell asks
# which face of the solid is in front of it, how much light that face catches,
# and picks a denser character for brighter light. Edges are drawn bright,
# hidden edges faint. The loop is seamless (one full turn about a tilted axis).
#
#   dodeca.py text ROWS N OUT              N frames as text, separated by form feeds
#   dodeca.py pngs ROWS N OUTDIR FONT PX   N frames as grey glyph pictures (boot splash)
#   dodeca.py still ROWS OUT.png FONT PX [FRAME]   one picture (boot menu, icons)
#   dodeca.py dur ROWS N OUT TAGLINE       the login screen's animation (ly .dur)
import gzip
import json
import math
import sys

PHI = (1 + 5 ** 0.5) / 2
RAMP = " .:-=+*%#"          # light → character (face shading)
EDGE = "@"                   # front edges
HIDDEN = "·"                 # (unused inside the solid: a convex shape hides its back edges)


def solid():
    v = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    for a in (-1, 1):
        for b in (-1, 1):
            v += [(0, a / PHI, b * PHI), (a / PHI, b * PHI, 0), (a * PHI, 0, b / PHI)]
    # face centres point along the icosahedron's vertices
    normals = []
    for a in (-1, 1):
        for b in (-1, 1):
            normals += [(0, a * PHI, b), (a * PHI, b, 0), (b, 0, a * PHI)]
    faces = []
    for n in normals:
        d = sorted(range(20), key=lambda i: -dot(v[i], n))[:5]
        faces.append((n, d))
    edges = set()
    for _, d in faces:
        ring = order(v, d)
        for i in range(5):
            edges.add(tuple(sorted((ring[i], ring[(i + 1) % 5]))))
    return v, [(n, order(v, d)) for n, d in faces], sorted(edges)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def norm(a):
    l = math.sqrt(dot(a, a))
    return (a[0] / l, a[1] / l, a[2] / l)


def order(v, idx):
    """The face's five corners in order around it."""
    c = [sum(v[i][k] for i in idx) / 5 for k in range(3)]
    n = norm(c)
    u = norm(tuple(v[idx[0]][k] - c[k] for k in range(3)))
    w = (n[1] * u[2] - n[2] * u[1], n[2] * u[0] - n[0] * u[2], n[0] * u[1] - n[1] * u[0])
    def ang(i):
        p = tuple(v[i][k] - c[k] for k in range(3))
        return math.atan2(dot(p, w), dot(p, u))
    return sorted(idx, key=ang)


def rotate(p, axis, t):
    """Rodrigues: p turned by t radians about the unit axis."""
    c, s = math.cos(t), math.sin(t)
    k = axis
    cross = (k[1] * p[2] - k[2] * p[1], k[2] * p[0] - k[0] * p[2], k[0] * p[1] - k[1] * p[0])
    kd = dot(k, p)
    return tuple(p[i] * c + cross[i] * s + k[i] * kd * (1 - c) for i in range(3))


AXIS = norm((0.35, 1.0, 0.25))       # tilted, so it tumbles rather than spins
TILT = norm((1.0, 0.0, 0.3))          # and a slow wobble of that axis: it revolves
LIGHT = norm((-0.5, 0.7, 0.9))


def frame(rows, f, n):
    cols = rows * 2                    # a character cell is about twice as tall as wide
    v, faces, edges = solid()
    t = 2 * math.pi * f / n
    axis = rotate(AXIS, TILT, 0.35 * math.sin(t))          # wobble: same at t=0 and t=2π
    pts = [rotate(p, axis, t) for p in v]
    R = 1.95                                               # fits the circumradius (√3)
    def to_screen(p):
        return ((p[0] / R + 1) * cols / 2, (1 - p[1] / R) * rows / 2)
    scr = [to_screen(p) for p in pts]
    grid = [[" "] * cols for _ in range(rows)]
    # shaded faces (front-facing only; a convex solid never overlaps itself)
    for n0, ring in faces:
        nn = norm(rotate(n0, axis, t))
        if nn[2] <= 0.02:
            continue
        light = max(0.0, dot(nn, LIGHT))
        ch = RAMP[min(len(RAMP) - 1, int((0.12 + 0.88 * light) * (len(RAMP) - 1) + 0.5))]
        poly = [scr[i] for i in ring]
        ys = [p[1] for p in poly]
        for r in range(max(0, int(min(ys))), min(rows, int(max(ys)) + 1)):
            for c in range(cols):
                if inside((c + 0.5, r + 0.5), poly):
                    grid[r][c] = ch
    # edges: front ones bright, back ones as faint dots where nothing's drawn
    front = set()
    for n0, ring in faces:
        if norm(rotate(n0, axis, t))[2] > 0.02:
            for i in range(5):
                front.add(tuple(sorted((ring[i], ring[(i + 1) % 5]))))
    for a, b in edges:
        (x0, y0), (x1, y1) = scr[a], scr[b]
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for s in range(steps + 1):
            x = x0 + (x1 - x0) * s / steps
            y = y0 + (y1 - y0) * s / steps
            r, c = int(y), int(x)
            if 0 <= r < rows and 0 <= c < cols:
                if (a, b) in front:
                    grid[r][c] = EDGE
                elif grid[r][c] == " ":
                    grid[r][c] = HIDDEN
    return ["".join(row) for row in grid]


def inside(p, poly):
    x, y = p
    sign = 0
    for i in range(len(poly)):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
        cr = (x1 - x0) * (y - y0) - (y1 - y0) * (x - x0)
        if cr != 0:
            s = 1 if cr > 0 else -1
            if sign and s != sign:
                return False
            sign = s
    return True


def shade_of(ch):
    """Grey level for a character in the pictures (0–255)."""
    if ch == EDGE:
        return 255
    if ch == HIDDEN:
        return 70
    i = RAMP.find(ch)
    return 110 + int(120 * i / (len(RAMP) - 1)) if i > 0 else 0


def picture(lines, font_path, px):
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(font_path, px)
    x0, _, x1, _ = font.getbbox("M")
    cw = x1 - x0
    ch = int(px * 1.2)
    img = Image.new("RGBA", (len(lines[0]) * cw, len(lines) * ch), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for r, line in enumerate(lines):
        for c, g in enumerate(line):
            if g != " ":
                lv = shade_of(g)
                d.text((c * cw, r * ch), g, font=font, fill=(lv, lv, lv, 255))
    return img


def main(a):
    mode = a[0]
    if mode == "text":
        rows, n, out = int(a[1]), int(a[2]), a[3]
        with open(out, "w", encoding="utf-8") as f:
            f.write("\f\n".join("\n".join(frame(rows, i, n)) + "\n" for i in range(n)))
    elif mode == "pngs":
        import os
        rows, n, outdir, font, px = int(a[1]), int(a[2]), a[3], a[4], int(a[5])
        os.makedirs(outdir, exist_ok=True)
        for i in range(n):
            picture(frame(rows, i, n), font, px).save(f"{outdir}/frame-{i:03d}.png")
    elif mode == "still":
        rows, out, font, px = int(a[1]), a[2], a[3], int(a[4])
        f = int(a[5]) if len(a) > 5 else 5
        img = picture(frame(rows, f, 60), font, px)
        w, h = img.size                      # square canvas, centred
        from PIL import Image
        s = max(w, h)
        sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        sq.paste(img, ((s - w) // 2, (s - h) // 2))
        sq.save(out)
    elif mode == "dur":
        rows, n, out, tagline = int(a[1]), int(a[2]), a[3], a[4]
        frames = []
        cols = rows * 2
        tag = " ".join(tagline.upper())
        width = max(cols, len(tag))
        for i in range(n):
            lines = [l.center(width) for l in frame(rows, i, n)] + [" " * width, tag.center(width)]
            cmap = []
            for x in range(width):
                col = []
                for y, l in enumerate(lines):
                    g = l[x]
                    if y >= rows:                       # the tagline: grey
                        fg = 244 if g != " " else 0
                    elif g == EDGE:
                        fg = 255                        # white
                    elif g == HIDDEN:
                        fg = 238
                    elif g != " ":
                        fg = 240 + int(11 * RAMP.find(g) / (len(RAMP) - 1))   # greys
                    else:
                        fg = 0
                    col.append([fg, 0])
                cmap.append(col)
            frames.append({"frameNumber": i + 1, "delay": 0, "contents": lines, "colorMap": cmap})
        movie = {"DurMovie": {
            "formatVersion": 7, "colorFormat": "256", "preferredFont": "fixed", "encoding": "utf-8",
            "name": "MooreOS", "artist": "", "framerate": 12.0, "sizeX": width,
            "sizeY": len(frames[0]["contents"]), "extra": None, "frames": frames}}
        with gzip.open(out, "wt", encoding="utf-8") as f:
            json.dump(movie, f)


if __name__ == "__main__":
    main(sys.argv[1:])
