# rice — change how the desktop looks, live. (Super+Alt+r, or menu → System.)
#
#   rice                      the window: pick a theme, move the sliders
#   rice list                 the themes
#   rice theme NAME           switch theme (rice theme nord)
#   rice wallpaper-colours    make a theme from the current wallpaper
#   rice dark | light         dark or light apps (GTK)
#   rice opacity 0.8          how see-through terminals are (0.3–1.0)
#   rice corners 10           rounded window corners, in pixels (0 = square)
#   rice gaps 12              space between windows, in pixels
#   rice border 2             window border width, in pixels
#   rice reset                back to nix²'s stock look
#   rice apply                re-apply what's saved (the session runs this at login)
#
# A theme is 16 terminal colours plus background and text. Switching one
# recolours, without logging out: the bar and window borders (dwm), menus
# (dmenu), notifications (dunst), every open terminal and new ones (st).
# What you choose is kept in ~/.config/nix2/rice.json; the files it writes
# for the programs live next to it and in their own config folders.
import colorsys
import glob
import json
import os
import shutil
import signal
import subprocess
import sys

HOME = os.path.expanduser("~")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")))
DIR = os.path.join(CONF, "nix2")
STATE = os.path.join(DIR, "rice.json")
XRES = os.path.join(DIR, "theme.xresources")
PICOM = os.path.join(DIR, "picom.conf")
DUNST = os.path.join(CONF, "dunst", "dunstrc.d", "90-nix2-theme.conf")
XSETTINGS = os.path.join(CONF, "xsettingsd", "xsettingsd.conf")
GTK3 = os.path.join(CONF, "gtk-3.0", "settings.ini")
BG = os.path.join(HOME, ".local", "share", "bg")

DEFAULTS = {"theme": None, "palette": None, "dark": True, "opacity": None,
            "corners": 0, "gaps": None, "border": None}
# Stock opacity comes from settings.termOpacity (the session exports it).
STOCK_OPACITY = float(os.environ.get("NIX2_TERM_OPACITY", "0.72") or 0.72)


def T(bg, fg, colors, light=False, accent=4):
    return {"bg": bg, "fg": fg, "colors": colors.split(), "light": light, "accent": accent}


# name → background, text, colours 0-15 (black red green yellow blue magenta
# cyan white, then the bright row). `accent` is the colour the bar and menus
# highlight with.
THEMES = {
    "snowy-night": T("#0b1a2e", "#e8f0f8",
                     "#13263f #ff8a8a #7fe0a8 #ffd98a #5ab4ff #c9a4ff #7fd8e8 #c8d6e6 "
                     "#4a6585 #ffa8a8 #a0f0c0 #ffe6ad #8accff #dcc4ff #a5e8f2 #ffffff"),
    "gruvbox": T("#282828", "#ebdbb2",
                 "#282828 #cc241d #98971a #d79921 #458588 #b16286 #689d6a #a89984 "
                 "#928374 #fb4934 #b8bb26 #fabd2f #83a598 #d3869b #8ec07c #ebdbb2", accent=3),
    "gruvbox-light": T("#fbf1c7", "#3c3836",
                       "#ebdbb2 #cc241d #98971a #d79921 #458588 #b16286 #689d6a #7c6f64 "
                       "#928374 #9d0006 #79740e #b57614 #076678 #8f3f71 #427b58 #3c3836", light=True, accent=12),
    "nord": T("#2e3440", "#d8dee9",
              "#3b4252 #bf616a #a3be8c #ebcb8b #81a1c1 #b48ead #88c0d0 #e5e9f0 "
              "#4c566a #bf616a #a3be8c #ebcb8b #81a1c1 #b48ead #8fbcbb #eceff4", accent=6),
    "catppuccin": T("#1e1e2e", "#cdd6f4",
                    "#45475a #f38ba8 #a6e3a1 #f9e2af #89b4fa #f5c2e7 #94e2d5 #bac2de "
                    "#585b70 #f38ba8 #a6e3a1 #f9e2af #89b4fa #f5c2e7 #94e2d5 #a6adc8", accent=5),
    "catppuccin-latte": T("#eff1f5", "#4c4f69",
                          "#dce0e8 #d20f39 #40a02b #df8e1d #1e66f5 #ea76cb #179299 #5c5f77 "
                          "#9ca0b0 #d20f39 #40a02b #df8e1d #1e66f5 #ea76cb #179299 #4c4f69", light=True),
    "tokyo-night": T("#1a1b26", "#c0caf5",
                     "#15161e #f7768e #9ece6a #e0af68 #7aa2f7 #bb9af7 #7dcfff #a9b1d6 "
                     "#414868 #f7768e #9ece6a #e0af68 #7aa2f7 #bb9af7 #7dcfff #c0caf5"),
    "dracula": T("#282a36", "#f8f8f2",
                 "#21222c #ff5555 #50fa7b #f1fa8c #bd93f9 #ff79c6 #8be9fd #f8f8f2 "
                 "#6272a4 #ff6e6e #69ff94 #ffffa5 #d6acff #ff92df #a4ffff #ffffff"),
    "everforest": T("#2d353b", "#d3c6aa",
                    "#475258 #e67e80 #a7c080 #dbbc7f #7fbbb3 #d699b6 #83c092 #d3c6aa "
                    "#859289 #e67e80 #a7c080 #dbbc7f #7fbbb3 #d699b6 #83c092 #e6dcc4", accent=2),
    "rose-pine": T("#191724", "#e0def4",
                   "#26233a #eb6f92 #31748f #f6c177 #9ccfd8 #c4a7e7 #ebbcba #e0def4 "
                   "#6e6a86 #eb6f92 #31748f #f6c177 #9ccfd8 #c4a7e7 #ebbcba #e0def4", accent=5),
    "one-dark": T("#282c34", "#abb2bf",
                  "#282c34 #e06c75 #98c379 #e5c07b #61afef #c678dd #56b6c2 #abb2bf "
                  "#5c6370 #e06c75 #98c379 #e5c07b #61afef #c678dd #56b6c2 #ffffff"),
    "kanagawa": T("#1f1f28", "#dcd7ba",
                  "#16161d #c34043 #76946a #c0a36e #7e9cd8 #957fb8 #6a9589 #c8c093 "
                  "#727169 #e82424 #98bb6c #e6c384 #7fb4ca #938aa9 #7aa89f #dcd7ba"),
    "solarized": T("#002b36", "#93a1a1",
                   "#073642 #dc322f #859900 #b58900 #268bd2 #d33682 #2aa198 #eee8d5 "
                   "#586e75 #e35d5b #a3b61a #d4a51a #4ea3de #dd5c9a #4dbdb4 #fdf6e3"),
    "solarized-light": T("#fdf6e3", "#586e75",
                         "#eee8d5 #dc322f #859900 #b58900 #268bd2 #d33682 #2aa198 #586e75 "
                         "#93a1a1 #cb4b16 #6c8a00 #a57800 #1f73b0 #b82d72 #20857e #073642", light=True),
    "paper": T("#f7f7f5", "#2b2b2b",
               "#e4e4e0 #b3261e #2e7d32 #9a6700 #1a56b0 #8e3a9d #0b7285 #555555 "
               "#8a8a86 #d0342c #3a9a40 #b77d00 #2a6fd6 #a84fb8 #1291a8 #1a1a1a", light=True),
    "midnight": T("#000000", "#d0d0d0",
                  "#161616 #ff5f5f #5fd787 #ffd75f #5fafff #d787ff #5fd7d7 #c6c6c6 "
                  "#585858 #ff8787 #87ffaf #ffff87 #87c7ff #e4afff #87ffff #ffffff"),
}


# ── colour helpers ──────────────────────────────────────────────────────────
def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexc(r, g, b):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in (r, g, b))


def mix(a, b, t):
    """a moved a fraction t of the way to b."""
    ra, rb = rgb(a), rgb(b)
    return hexc(*(x + (y - x) * t for x, y in zip(ra, rb)))


def hls(h):
    r, g, b = (v / 255 for v in rgb(h))
    return colorsys.rgb_to_hls(r, g, b)


def from_hls(h, l, s):
    return hexc(*(v * 255 for v in colorsys.hls_to_rgb(h % 1.0, max(0, min(1, l)), max(0, min(1, s)))))


def luminance(h):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(v) for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def readable(colour, bg, want=4.0):
    """colour, nudged lighter (dark theme) or darker (light theme) until it
    reads on bg."""
    h, l, s = hls(colour)
    step = 0.03 if luminance(bg) < 0.4 else -0.03
    for _ in range(30):
        if contrast(from_hls(h, l, s), bg) >= want:
            break
        l += step
    return from_hls(h, l, s)


def palette_from_image(path):
    """A theme from a picture: background and text tinted with its main
    colour, the highlight is its most vivid colour, and the six terminal
    colours keep their meaning (red stays red) but take the picture's mood."""
    from PIL import Image
    img = Image.open(path).convert("RGB")
    img.thumbnail((160, 160))
    quant = img.quantize(colors=12, method=Image.Quantize.MEDIANCUT)
    pal = quant.getpalette()[:36]
    counts = sorted(quant.getcolors(), reverse=True)
    found = [(n, hexc(*pal[i * 3:i * 3 + 3])) for n, i in counts]
    total = sum(n for n, _ in found)
    # the picture's overall darkness decides dark or light theme
    avg = sum(luminance(c) * n for n, c in found) / total
    light = avg > 0.45
    main = found[0][1]
    mh, _, ms = hls(main)
    # The highlight: the picture's most vivid family of colours. Colours are
    # grouped by hue (so a sunset's many oranges count together), and a hue
    # close to the background's own counts for less, so the highlight stands
    # out from it.
    def vivid(c):
        _, l, s = hls(c)
        return s * (1 - abs(l - 0.55))
    groups = {}
    for n, c in found:
        h, _, s = hls(c)
        if s < 0.18:
            continue                                   # greys have no hue to speak of
        groups.setdefault(round(h * 12) % 12, []).append((n, c))
    def weight(item):
        bucket, members = item
        share = sum(n for n, _ in members) / total
        near_bg = min(abs(bucket / 12 - mh), 1 - abs(bucket / 12 - mh)) < 0.09
        return sum(vivid(c) * n for n, c in members) / total * (0.45 if near_bg else 1.0) * (0.5 + min(share, 0.3))
    if groups:
        _, members = max(groups.items(), key=weight)
        accent = max(members, key=lambda m: vivid(m[1]))[1]
    else:
        accent = from_hls(mh, 0.6, 0.5)
    ah, al, a_s = hls(accent)
    tint = min(ms, 0.45)
    if light:
        bg = from_hls(mh, 0.95, tint * 0.6)
        fg = from_hls(mh, 0.20, tint * 0.5)
    else:
        bg = from_hls(mh, 0.09, tint * 0.9)
        fg = from_hls(mh, 0.88, tint * 0.35)
    # how colourful the picture is sets how colourful the terminal is
    sat = max(0.35, min(0.75, max(s for _, c in found for _, _, s in [hls(c)]) * 0.9))
    base_l = 0.42 if light else 0.66
    hues = {1: 0.0, 2: 0.33, 3: 0.14, 4: 0.60, 5: 0.82, 6: 0.50}   # red green yellow blue magenta cyan
    cols = [None] * 16
    for i, hue in hues.items():
        # pull each hue a little toward the accent so the set belongs together
        d = ((ah - hue + 0.5) % 1.0) - 0.5
        hue2 = hue + d * 0.12
        cols[i] = readable(from_hls(hue2, base_l, sat), bg)
        cols[i + 8] = readable(from_hls(hue2, base_l + (-0.08 if light else 0.10), min(1, sat + 0.1)), bg)
    cols[4] = readable(from_hls(ah, max(0.45, min(0.72, al)) if not light else 0.40, max(a_s, 0.45)), bg)
    cols[12] = readable(mix(cols[4], fg, 0.25), bg)
    cols[0] = mix(bg, fg, 0.08)
    cols[8] = mix(bg, fg, 0.40)
    cols[7] = mix(fg, bg, 0.15)
    cols[15] = fg if not light else mix(fg, "#000000", 0.3)
    return {"bg": bg, "fg": fg, "colors": cols, "light": light, "accent": 4}


# ── state ───────────────────────────────────────────────────────────────────
def load():
    s = dict(DEFAULTS)
    try:
        with open(STATE, encoding="utf-8") as f:
            s.update({k: v for k, v in json.load(f).items() if k in DEFAULTS})
    except (OSError, ValueError):
        pass
    return s


def save(s):
    os.makedirs(DIR, exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(s, f, indent=1)
    os.replace(tmp, STATE)


def palette_of(s):
    if s.get("theme") == "wallpaper" and s.get("palette"):
        return s["palette"]
    return THEMES.get(s.get("theme") or "")


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


def run(*argv, **kw):
    try:
        return subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10, **kw).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


# ── the files each program reads ────────────────────────────────────────────
def xresources(s):
    p = palette_of(s)
    out = ["! Written by `rice` — change it there (rice reset removes it)."]
    if p:
        c, acc = p["colors"], p["colors"][p.get("accent", 4)]
        out += [f"*.color{i}: {c[i]}" for i in range(16)]
        out += [f"*.background: {p['bg']}", f"*.foreground: {p['fg']}", f"*.cursorColor: {p['fg']}"]
        # dwm: bar and unfocused borders = background, text and the selected
        # tag = accent, focused window's border = accent
        out += [f"dwm.color0: {p['bg']}", f"dwm.color4: {acc}", f"dwm.color8: {acc}"]
        out += [f"dmenu.color0: {p['bg']}", f"dmenu.color4: {acc}"]
    if s.get("gaps") is not None:
        g = int(s["gaps"])
        out += [f"dwm.gappih: {g}", f"dwm.gappiv: {g}", f"dwm.gappoh: {g}", f"dwm.gappov: {g}",
                "dwm.smartgaps: 0"]
    if s.get("border") is not None:
        out.append(f"dwm.borderpx: {int(s['border'])}")
    return "\n".join(out) + "\n"


def dunstrc(p):
    c, acc = p["colors"], p["colors"][p.get("accent", 4)]
    return (
        "# Written by `rice`.\n"
        f"[global]\n    frame_color = \"{acc}\"\n    separator_color = frame\n"
        f"[urgency_low]\n    background = \"{p['bg']}\"\n    foreground = \"{mix(p['fg'], p['bg'], 0.25)}\"\n"
        f"[urgency_normal]\n    background = \"{p['bg']}\"\n    foreground = \"{p['fg']}\"\n"
        f"[urgency_critical]\n    background = \"{p['bg']}\"\n    foreground = \"{p['fg']}\"\n    frame_color = \"{c[1]}\"\n"
    )


def picom_conf(s):
    op = STOCK_OPACITY if s.get("opacity") is None else float(s["opacity"])
    corners = int(s.get("corners") or 0)
    return (
        "# Written by `rice` (opacity, corners). The stock one is in modules/desktop.nix.\n"
        'backend = "glx";\nvsync = true;\n'
        f"corner-radius = {corners};\n"
        "rules = (\n"
        f"  {{ match = \"class_g = 'St'\"; opacity = {op:.2f}; }},\n"
        "  { match = \"window_type = 'dock' || window_type = 'desktop' || class_g = 'dwm' || class_g = 'linux-wallpaperengine' || class_g = 'Xsnow'\"; corner-radius = 0; },\n"
        "  { match = \"fullscreen\"; opacity = 1.0; corner-radius = 0; }\n"
        ");\n"
    )


def gtk_files(dark):
    theme = "Adwaita-dark" if dark else "Adwaita"
    icons = "Papirus-Dark" if dark else "Papirus-Light"
    write(XSETTINGS, f'Net/ThemeName "{theme}"\nNet/IconThemeName "{icons}"\n'
                     f'Gtk/ApplicationPreferDarkTheme {1 if dark else 0}\n')
    # settings.ini: keep whatever else is in it (fonts, cursor…)
    keep = []
    try:
        with open(GTK3, encoding="utf-8") as f:
            keep = [ln.rstrip("\n") for ln in f
                    if not ln.startswith(("gtk-theme-name", "gtk-icon-theme-name", "gtk-application-prefer-dark-theme", "[Settings]"))
                    and ln.strip()]
    except OSError:
        pass
    write(GTK3, "\n".join(["[Settings]", f"gtk-theme-name={theme}", f"gtk-icon-theme-name={icons}",
                           f"gtk-application-prefer-dark-theme={'true' if dark else 'false'}"] + keep) + "\n")


# ── applying ────────────────────────────────────────────────────────────────
def recolour_terminals(p):
    """Open terminals: tell each one its new colours (the escape codes st,
    and most terminals, understand)."""
    seq = "".join(f"\033]4;{i};{c}\007" for i, c in enumerate(p["colors"]))
    seq += f"\033]10;{p['fg']}\007\033]11;{p['bg']}\007\033]12;{p['fg']}\007"
    for pts in glob.glob("/dev/pts/[0-9]*"):
        try:
            if os.stat(pts).st_uid != os.getuid():
                continue
            fd = os.open(pts, os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
            try:
                os.write(fd, seq.encode())
            finally:
                os.close(fd)
        except OSError:
            pass


def pids(name):
    try:
        out = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", name], capture_output=True, text=True, timeout=5).stdout
        return [int(x) for x in out.split()]
    except (OSError, subprocess.SubprocessError, ValueError):
        return []


def restart(name, *argv):
    for pid in pids(name):
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    try:
        subprocess.Popen(argv, start_new_session=True, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def apply(s, what=("colours", "gtk", "picom"), startup=False):
    """Write the files for the saved look and make running programs take it."""
    have_x = bool(os.environ.get("DISPLAY"))
    p = palette_of(s)
    custom_x = p or s.get("gaps") is not None or s.get("border") is not None
    if "colours" in what:
        if custom_x:
            write(XRES, xresources(s))
        else:
            remove(XRES)
        if p:
            write(DUNST, dunstrc(p))
        else:
            remove(DUNST)
        if have_x:
            if custom_x:
                run("xrdb", "-merge", XRES)
            # (dwm re-reads colours, gaps and border by itself when xrdb changes them)
            if not startup:                     # at login dunst starts after this
                if not run("dunstctl", "reload"):
                    if pids("dunst"):
                        restart("dunst", "dunst")
            if p and not startup:
                recolour_terminals(p)
    if "gtk" in what and s.get("theme") is not None or "gtk-force" in what:
        dark = bool(s.get("dark", True))
        gtk_files(dark)
        if have_x:
            run("dconf", "write", "/org/gnome/desktop/interface/color-scheme",
                "'prefer-dark'" if dark else "'prefer-light'")
            run("dconf", "write", "/org/gnome/desktop/interface/gtk-theme",
                "'Adwaita-dark'" if dark else "'Adwaita'")
            if not startup:
                if pids("xsettingsd"):
                    for pid in pids("xsettingsd"):
                        os.kill(pid, signal.SIGHUP)
                elif shutil.which("xsettingsd"):
                    restart("xsettingsd", "xsettingsd")
    if "picom" in what:
        if s.get("opacity") is None and not s.get("corners"):
            remove(PICOM)
        else:
            write(PICOM, picom_conf(s))
        if have_x and not startup and pids("picom"):
            conf = PICOM if os.path.exists(PICOM) else os.environ.get("NIX2_PICOM_CONF", "")
            restart("picom", *(["picom", "--config", conf] if conf else ["picom"]))


def set_theme(s, name):
    if name == "wallpaper":
        path = os.path.realpath(BG)
        if not os.path.isfile(path):
            raise SystemExit("rice: no wallpaper set yet (pick one in `wallpapers`).")
        s["palette"] = palette_from_image(path)
    elif name not in THEMES:
        raise SystemExit(f"rice: no theme called '{name}'. Try: rice list")
    s["theme"] = name
    p = palette_of(s)
    s["dark"] = not p["light"]
    save(s)
    apply(s, ("colours", "gtk"))


def reset():
    s = dict(DEFAULTS)
    save(s)
    remove(XSETTINGS)
    apply(s, ("colours", "picom"))
    # back to the stock colours: the session's own Xresources, plus dwm's
    # built-in gaps and border (it keeps the last values it was given)
    stock = os.path.join(CONF, "x11", "xresources")
    if os.environ.get("DISPLAY"):
        text = ""
        if os.path.exists(stock):
            with open(stock, encoding="utf-8", errors="replace") as f:
                text = f.read()
        if "color4" not in text:           # no stock colours on this machine: the LARBS look
            g = THEMES["gruvbox"]
            text += f"\ndwm.color0: {g['bg']}\ndwm.color4: {g['colors'][3]}\ndwm.color8: {g['colors'][8]}\n"
        text += "\ndwm.gappih: 20\ndwm.gappiv: 10\ndwm.gappoh: 10\ndwm.gappov: 30\ndwm.borderpx: 3\n"
        try:
            subprocess.run(["xrdb", "-load", "-"], input=text, text=True, timeout=10,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError):
            pass
    print("rice: back to the stock look (open terminals keep their colours until you reopen them).")


def number(text, lo, hi, what):
    try:
        v = float(text)
    except ValueError:
        raise SystemExit(f"rice: {what} needs a number from {lo} to {hi}.")
    if not lo <= v <= hi:
        raise SystemExit(f"rice: {what} goes from {lo} to {hi}.")
    return v


# ── the window ──────────────────────────────────────────────────────────────
def window():
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import GLib, Gtk

    state = load()
    win = Gtk.Window(title="Look & feel")
    win.set_default_size(980, 640)
    win.set_wmclass("rice", "Rice")
    css = Gtk.CssProvider()
    css.load_from_data(b"""
        .card { border-radius: 10px; border: 2px solid transparent; padding: 0; }
        .card.current { border-color: @theme_selected_bg_color; }
        .side { padding: 16px; }
        .head { font-weight: bold; font-size: 110%; margin-top: 10px; }
        .hint { opacity: 0.65; font-size: 90%; }
    """)
    Gtk.StyleContext.add_provider_for_screen(win.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    root = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
    win.add(root)

    flow = Gtk.FlowBox(valign=Gtk.Align.START, max_children_per_line=4, min_children_per_line=2,
                       selection_mode=Gtk.SelectionMode.NONE, homogeneous=True,
                       row_spacing=10, column_spacing=10, margin=16)
    scroll = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
    scroll.add(flow)
    root.pack_start(scroll, True, True, 0)
    cards = {}

    def preview(p):
        """A little terminal drawn in the theme's colours."""
        area = Gtk.DrawingArea()
        area.set_size_request(190, 112)

        def draw(_w, cr):
            def col(h):
                r, g, b = rgb(h)
                cr.set_source_rgb(r / 255, g / 255, b / 255)
            w, h = area.get_allocated_width(), area.get_allocated_height()
            col(p["bg"]); cr.rectangle(0, 0, w, h); cr.fill()
            acc = p["colors"][p.get("accent", 4)]
            col(acc); cr.rectangle(0, 0, w, 14); cr.fill()           # the bar
            col(p["bg"]); cr.rectangle(6, 3, 22, 8); cr.fill()
            y = 26
            # lines of coloured "words": (colour number or None for plain text, width)
            for words in (((None, 26), (2, 44)), ((4, 34), (None, 50), (3, 22)),
                          ((5, 20), (None, 70)), ((6, 40), (1, 28), (None, 30))):
                x = 10
                for ci, width in words:
                    col(p["fg"] if ci is None else p["colors"][ci])
                    cr.rectangle(x, y, width, 6); cr.fill()
                    x += width + 8
                y += 14
            for i in range(8):                                        # the eight colours
                col(p["colors"][i + 8]); cr.rectangle(10 + i * 21, h - 20, 17, 10); cr.fill()
        area.connect("draw", draw)
        return area

    def card(name, title, p):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        btn = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
        btn.get_style_context().add_class("card")
        btn.add(preview(p))
        btn.connect("clicked", lambda _b: choose(name))
        box.pack_start(btn, False, False, 0)
        box.pack_start(Gtk.Label(label=title), False, False, 0)
        cards[name] = btn
        flow.add(box)

    def mark():
        for name, btn in cards.items():
            ctx = btn.get_style_context()
            (ctx.add_class if state.get("theme") == name else ctx.remove_class)("current")

    def choose(name):
        try:
            set_theme(state, name)
        except SystemExit as e:
            note.set_text(str(e))
            return
        dark.set_active(state["dark"])
        note.set_text(f"Theme: {name.replace('-', ' ')}")
        if name == "wallpaper":
            rebuild_wallpaper_card()
        mark()

    def rebuild_wallpaper_card():
        for child in list(flow.get_children()):
            flow.remove(child)
        cards.clear()
        fill()
        flow.show_all()

    def fill():
        if state.get("palette"):
            card("wallpaper", "From my wallpaper", state["palette"])
        for name, p in THEMES.items():
            card(name, name.replace("-", " ").title(), p)

    fill()

    side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    side.get_style_context().add_class("side")
    side.set_size_request(290, -1)
    root.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
    root.pack_start(side, False, False, 0)

    def head(text):
        l = Gtk.Label(label=text, xalign=0)
        l.get_style_context().add_class("head")
        side.pack_start(l, False, False, 0)

    head("Wallpaper")
    b = Gtk.Button(label="Change wallpaper…")
    b.connect("clicked", lambda _b: subprocess.Popen(["wallpapers"], start_new_session=True))
    side.pack_start(b, False, False, 0)
    b = Gtk.Button(label="Colours from my wallpaper")
    b.connect("clicked", lambda _b: choose("wallpaper"))
    side.pack_start(b, False, False, 0)

    head("Apps")
    row = Gtk.Box(spacing=8)
    row.pack_start(Gtk.Label(label="Dark apps", xalign=0), True, True, 0)
    dark = Gtk.Switch(active=bool(state.get("dark", True)))

    def on_dark(sw, _p):
        if sw.get_active() != bool(state.get("dark", True)):
            state["dark"] = sw.get_active()
            save(state)
            apply(state, ("gtk-force",))
    dark.connect("notify::active", on_dark)
    row.pack_end(dark, False, False, 0)
    side.pack_start(row, False, False, 0)

    pending = {}

    def slider(title, key, lo, hi, step, value, digits=0, what=("colours",)):
        head(title)
        sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lo, hi, step)
        sc.set_digits(digits)
        sc.set_value(value)

        def fire():
            pending.pop(key, None)
            state[key] = round(sc.get_value(), 2) if digits else int(sc.get_value())
            save(state)
            apply(state, what)
            return False

        def changed(_s):                 # wait until the slider rests for a moment
            if key in pending:
                GLib.source_remove(pending[key])
            pending[key] = GLib.timeout_add(350, fire)
        sc.connect("value-changed", changed)
        side.pack_start(sc, False, False, 0)

    slider("See-through terminals", "opacity", 0.3, 1.0, 0.02,
           STOCK_OPACITY if state.get("opacity") is None else state["opacity"], 2, ("picom",))
    slider("Rounded corners", "corners", 0, 20, 1, state.get("corners") or 0, 0, ("picom",))
    slider("Gaps between windows", "gaps", 0, 40, 1, 20 if state.get("gaps") is None else state["gaps"])
    slider("Window border", "border", 0, 8, 1, 3 if state.get("border") is None else state["border"])

    side.pack_start(Gtk.Box(), True, True, 0)
    note = Gtk.Label(label="Click a theme: it changes straight away.", xalign=0, wrap=True)
    note.get_style_context().add_class("hint")
    side.pack_start(note, False, False, 0)
    b = Gtk.Button(label="Back to the stock look")

    def on_reset(_b):
        reset()
        state.clear(); state.update(load())
        note.set_text("Back to the stock look.")
        rebuild_wallpaper_card()
        mark()
    b.connect("clicked", on_reset)
    side.pack_start(b, False, False, 0)

    mark()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()


def usage():
    with open(__file__, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#!"):
                continue
            if not line.startswith("#"):
                break
            print(line[2:].rstrip())


def main(argv):
    if not argv:
        return window()
    cmd, args = argv[0], argv[1:]
    s = load()
    if cmd in ("-h", "--help", "help"):
        usage()
    elif cmd == "list":
        for name, p in THEMES.items():
            print(f"{'*' if s.get('theme') == name else ' '} {name:<18} {'light' if p['light'] else 'dark'}")
        print(f"{'*' if s.get('theme') == 'wallpaper' else ' '} {'wallpaper':<18} made from your wallpaper (rice wallpaper-colours)")
    elif cmd == "theme":
        if not args:
            raise SystemExit("usage: rice theme NAME   (rice list shows them)")
        set_theme(s, args[0].lower())
        print(f"rice: theme {args[0].lower()}")
    elif cmd == "follow-wallpaper":         # the wallpaper changed: only matters for that theme
        if s.get("theme") == "wallpaper":
            set_theme(s, "wallpaper")
    elif cmd in ("wallpaper-colours", "wallpaper-colors"):
        set_theme(s, "wallpaper")
        print("rice: colours taken from your wallpaper")
    elif cmd in ("dark", "light"):
        s["dark"] = cmd == "dark"
        save(s)
        apply(s, ("gtk-force",))
    elif cmd in ("opacity", "corners", "gaps", "border"):
        if not args:
            raise SystemExit(f"usage: rice {cmd} NUMBER")
        lo, hi = {"opacity": (0.3, 1.0), "corners": (0, 20), "gaps": (0, 40), "border": (0, 8)}[cmd]
        v = number(args[0], lo, hi, cmd)
        s[cmd] = v if cmd == "opacity" else int(v)
        save(s)
        apply(s, ("picom",) if cmd in ("opacity", "corners") else ("colours",))
    elif cmd == "reset":
        reset()
    elif cmd == "apply":
        apply(s, ("colours", "gtk", "picom"), startup="--startup" in args)
    else:
        raise SystemExit(f"rice: unknown command '{cmd}' (rice help)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
