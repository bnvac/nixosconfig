# Draws nix²'s built-in wallpapers (original work, MIT like the rest).
# Run at build time: wallpapers-gen.py OUTDIR [WIDTH HEIGHT]
# Every image comes from a fixed random seed, so builds are reproducible.
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
W = int(sys.argv[2]) if len(sys.argv) > 2 else 3840
H = int(sys.argv[3]) if len(sys.argv) > 3 else 2160
S = W / 3840                                   # designs are drawn at 3840×2160


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def vgradient(top, bottom, curve=1.0):
    t = np.linspace(0, 1, H)[:, None] ** curve
    a, b = np.array(rgb(top), float), np.array(rgb(bottom), float)
    img = a + (b - a) * t[..., None]
    return np.broadcast_to(img, (H, W, 3)).copy()


def stars(arr, rng, n, maxr=1.6):
    img = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x, y = rng.uniform(0, W), rng.uniform(0, H * 0.7)
        r = rng.uniform(0.4, maxr) * S
        a = int(rng.uniform(90, 230))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(a, a, min(255, a + 15)))
    return np.asarray(img).astype(float)


def ridge(rng, base, amp, octaves=5, rough=0.55):
    x = np.linspace(0, 1, W)
    y = np.full(W, base, float)
    for o in range(octaves):
        f = 2 ** o * rng.uniform(1.5, 2.5)
        y += amp * (rough ** o) * np.sin(2 * math.pi * (f * x + rng.uniform(0, 1)))
    return y * H


def fill_below(arr, ys, color, alpha=1.0):
    rows = np.arange(H)[:, None]
    mask = rows >= ys[None, :]
    c = np.array(rgb(color), float)
    arr[mask] = arr[mask] * (1 - alpha) + c * alpha
    return arr


def save(arr, name):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name), optimize=True)


def aurora():
    rng = np.random.default_rng(11)
    a = vgradient("#03060f", "#0d2333", 1.3)
    a = stars(a, rng, int(900 * S * S) + 300)
    yy, xx = np.mgrid[0:H, 0:W] / H
    glow = np.zeros((H, W))
    for k, (cy, amp, freq, width) in enumerate([(0.30, .06, 1.3, .045), (0.38, .05, 2.1, .03), (0.25, .04, 3.0, .025)]):
        center = cy + amp * np.sin(2 * math.pi * freq * xx * H / W + k * 1.7) + .02 * np.sin(9 * xx * H / W + k)
        d = (yy - center) / width
        curtain = np.exp(-np.clip(d, 0, None) ** 2 * .35) * np.exp(-np.clip(-d, 0, None) ** 2 * 6)
        glow += curtain * (0.55 + 0.45 * np.sin(31 * xx * H / W + k * 2.3) ** 2)
    glow = np.clip(glow, 0, 1.4)
    green, teal = np.array(rgb("#4fe0a0")), np.array(rgb("#5ab4ff"))
    mix = np.clip(yy * 2.4 - 0.4, 0, 1)[..., None]
    col = green * (1 - mix) + teal * mix
    a = a + glow[..., None] * col * 0.75
    a = fill_below(a, ridge(rng, .74, .035), "#0a1726")
    a = fill_below(a, ridge(rng, .82, .03), "#071019")
    save(a, "aurora.png")


def dusk():
    rng = np.random.default_rng(5)
    a = vgradient("#1d2a4d", "#e9a07a", 1.6)
    layers = ["#4b4f7c", "#3a3c66", "#2b2c50", "#1e1f3b", "#131429"]
    for i, c in enumerate(layers):
        a = fill_below(a, ridge(rng, .52 + i * .085, .045 - i * .004, rough=.5), c)
    # a low sun behind the haze
    img = Image.fromarray(a.astype(np.uint8))
    sun = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sun).ellipse([W * .62, H * .38, W * .62 + 160 * S, H * .38 + 160 * S], fill=170)
    sun = sun.filter(ImageFilter.GaussianBlur(40 * S))
    img = Image.composite(Image.new("RGB", (W, H), rgb("#ffd9b0")), img, sun)
    save(np.asarray(img).astype(float), "dusk.png")


def blueprint():
    a = vgradient("#123a7a", "#0d2c60", 1.0)
    img = Image.fromarray(a.astype(np.uint8)).convert("RGBA")
    over = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(over)
    step = int(48 * S)
    for x in range(0, W, step):
        d.line([(x, 0), (x, H)], fill=(255, 255, 255, 40 if x % (step * 5) else 70), width=max(1, int(S)))
    for y in range(0, H, step):
        d.line([(0, y), (W, y)], fill=(255, 255, 255, 40 if y % (step * 5) else 70), width=max(1, int(S)))
    line = (220, 235, 255, 170)
    lw = max(2, int(3 * S))
    cx, cy, r = W * .68, H * .5, 420 * S
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=line, width=lw)
    d.ellipse([cx - r * .45, cy - r * .45, cx + r * .45, cy + r * .45], outline=line, width=lw)
    for k in range(12):                                     # a gear's teeth
        t = k * math.pi / 6
        p = [(cx + math.cos(t + s) * r * f, cy + math.sin(t + s) * r * f) for s, f in ((-.09, 1), (-.06, 1.12), (.06, 1.12), (.09, 1))]
        d.line(p, fill=line, width=lw)
    d.line([(cx - r * 1.3, cy), (cx + r * 1.3, cy)], fill=(220, 235, 255, 90), width=max(1, int(2 * S)))
    d.line([(cx, cy - r * 1.3), (cx, cy + r * 1.3)], fill=(220, 235, 255, 90), width=max(1, int(2 * S)))
    y0 = cy + r * 1.45                                      # a dimension line under it
    d.line([(cx - r, y0), (cx + r, y0)], fill=line, width=lw)
    for x in (cx - r, cx + r):
        d.line([(x, y0 - 22 * S), (x, y0 + 22 * S)], fill=line, width=lw)
    bx, by, bw, bh = W * .14, H * .3, 900 * S, 560 * S       # a box with a hole pattern
    d.rectangle([bx, by, bx + bw, by + bh], outline=line, width=lw)
    for i in range(4):
        for j in range(2):
            hx, hy = bx + bw * (.2 + .2 * i), by + bh * (.33 + .34 * j)
            d.ellipse([hx - 34 * S, hy - 34 * S, hx + 34 * S, hy + 34 * S], outline=line, width=lw)
    img = Image.alpha_composite(img, over).convert("RGB")
    save(np.asarray(img).astype(float), "blueprint.png")


def topo():
    rng = np.random.default_rng(3)
    a = vgradient("#0f1a1c", "#13262a", 1.0)
    h = 900                                                  # height field at low res, then scaled
    w = int(h * W / H)
    yy, xx = np.mgrid[0:h, 0:w] / h
    f = np.zeros((h, w))
    for _ in range(6):                                       # broad rolling land
        kx, ky = rng.normal(0, 0.9, 2)
        f += np.sin(2 * math.pi * (kx * xx + ky * yy) + rng.uniform(0, 6.28)) * rng.uniform(.2, .6)
    for _ in range(14):                                      # hills and hollows
        cx, cy, s = rng.uniform(-.1, w / h + .1), rng.uniform(-.1, 1.1), rng.uniform(.06, .22)
        f += rng.choice([-1, 1]) * rng.uniform(.8, 2.2) * np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * s * s))
    levels = 28
    q = np.floor((f - f.min()) / (f.max() - f.min()) * levels)
    edge = (np.abs(np.diff(q, axis=0, prepend=q[:1])) + np.abs(np.diff(q, axis=1, prepend=q[:, :1]))) > 0
    major = edge & (q % 5 == 0)
    lines = Image.fromarray((edge * 120 + major * 135).clip(0, 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)
    lines = lines.filter(ImageFilter.GaussianBlur(0.8 * S))
    m = np.asarray(lines).astype(float)[..., None] / 255
    a = a * (1 - m * .9) + np.array(rgb("#7fd0c8"), float) * m * .9
    save(a, "topography.png")


def circuit():
    rng = np.random.default_rng(8)
    a = vgradient("#071613", "#0b221d", 1.0)
    img = Image.fromarray(a.astype(np.uint8)).convert("RGBA")
    over = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(over)
    g = 40 * S
    cols, rows = int(W / g), int(H / g)
    used = set()
    copper = (64, 196, 150, 150)
    lw = max(2, int(4 * S))
    for _ in range(int(140 * S) + 60):
        x, y = int(rng.integers(0, cols)), int(rng.integers(0, rows))
        pts = [(x, y)]
        dx, dy = [(1, 0), (0, 1), (1, 1), (1, -1)][int(rng.integers(0, 4))]
        for _ in range(int(rng.integers(4, 18))):
            if rng.random() < .25:
                dx, dy = [(1, 0), (0, 1), (1, 1), (1, -1)][int(rng.integers(0, 4))]
            x, y = x + dx, y + dy
            if (x, y) in used or not (0 <= x < cols and 0 <= y < rows):
                break
            used.add((x, y))
            pts.append((x, y))
        if len(pts) < 3:
            continue
        P = [(px * g, py * g) for px, py in pts]
        d.line(P, fill=copper, width=lw, joint="curve")
        for (px, py) in (P[0], P[-1]):
            r = 9 * S
            d.ellipse([px - r, py - r, px + r, py + r], outline=copper, width=lw)
    for _ in range(6):                                       # a few chips
        x, y = rng.uniform(.1, .85) * W, rng.uniform(.1, .8) * H
        cw, ch = rng.uniform(160, 320) * S, rng.uniform(120, 220) * S
        d.rounded_rectangle([x, y, x + cw, y + ch], radius=10 * S, fill=(10, 30, 26, 255), outline=(64, 196, 150, 200), width=lw)
        for k in range(int(cw / (22 * S))):
            px = x + 14 * S + k * 22 * S
            d.line([(px, y - 16 * S), (px, y)], fill=(160, 170, 170, 200), width=lw)
            d.line([(px, y + ch), (px, y + ch + 16 * S)], fill=(160, 170, 170, 200), width=lw)
    img = Image.alpha_composite(img, over.filter(ImageFilter.GaussianBlur(0.6 * S))).convert("RGB")
    save(np.asarray(img).astype(float), "circuit.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in (aurora, dusk, blueprint, topo, circuit):
        f()
        print("drew", f.__name__)
