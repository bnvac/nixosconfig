# wallpapers — pick your wallpaper (Super+Alt+w).
#   Built in          nix²'s own wallpapers (snowy night, aurora, dusk, …)
#   My pictures       your images in ~/Pictures/wallpapers
#   Live              your Wallpaper Engine wallpapers from the Steam Workshop,
#                     played on every screen by the wallpaper-live service
# Above the grid: the current wallpaper, how it fits the screen, Shuffle, and
# the falling-snow switch. A picture choice sticks across logins (setbg); the
# fit is saved in ~/.config/wallpapers/fit.
import glob
import json
import os
import random
import shutil
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango  # noqa: E402

HOME = os.path.expanduser("~")
PICS = os.environ.get("WALLPAPER_DIR", os.path.join(HOME, "Pictures", "wallpapers"))
BUILTIN_DIR = os.environ.get("WALLPAPER_BUILTIN_DIR", "")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "wallpapers")
LIVE = os.path.join(CONF, "live")
FIT = os.path.join(CONF, "fit")
CURRENT_BG = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.join(HOME, ".local", "share")), "bg")
WE_APP = "431960"
STEAM_ROOTS = [os.path.join(HOME, ".local", "share", "Steam"), os.path.join(HOME, ".steam", "steam")]
IMAGES = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif")
TW, TH = 232, 131                     # thumbnail size (16:9)
FITS = [("Fill the screen", "zoom"), ("Fit inside", "maximize"), ("Centre", "center"),
        ("Tile", "tile"), ("Stretch", "stretch")]
NAMES = {"snowy-night": "Snowy night", "aurora": "Aurora", "dusk": "Dusk ridge",
         "blueprint": "Blueprint", "topography": "Topography", "circuit": "Circuit board"}

CSS = b"""
.side { background: alpha(@theme_bg_color, .6); border-right: 1px solid alpha(@theme_fg_color, .08); }
.side row { padding: 10px 16px; border-radius: 8px; margin: 2px 8px; }
.hero { padding: 18px 22px; border-bottom: 1px solid alpha(@theme_fg_color, .08); }
.hero-title { font-size: 20px; font-weight: 700; }
.hero-sub { opacity: .65; }
.card { padding: 6px; border-radius: 12px; border: 2px solid transparent; background: transparent; }
.card:hover { background: alpha(@theme_fg_color, .05); }
.card.current { border-color: #7c9ff4; background: alpha(#7c9ff4, .10); }
.card label { margin-top: 6px; }
.badge { background: #7c9ff4; color: #0b1020; border-radius: 99px; padding: 1px 8px; font-size: 11px; font-weight: 700; }
.empty { opacity: .7; }
.bar { padding: 8px 14px; }
.notice { background: alpha(#f0b77c, .14); border: 1px solid alpha(#f0b77c, .4); border-radius: 10px; padding: 10px 14px; margin: 12px 14px 0; }
"""


def spawn(*cmd):
    try:
        subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
    except FileNotFoundError:
        return ""


def quiet(*cmd):
    try:
        return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    except FileNotFoundError:
        return 127


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def pretty(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    return NAMES.get(stem, stem.replace("-", " ").replace("_", " ").capitalize())


# ── where wallpapers come from ──────────────────────────────────────────────
def builtins():
    if not BUILTIN_DIR or not os.path.isdir(BUILTIN_DIR):
        return []
    order = list(NAMES)
    files = [f for f in os.listdir(BUILTIN_DIR) if f.lower().endswith(IMAGES)]
    files.sort(key=lambda f: (order.index(os.path.splitext(f)[0]) if os.path.splitext(f)[0] in order else 99, f))
    return [(pretty(f), os.path.join(BUILTIN_DIR, f)) for f in files]


def mine():
    os.makedirs(PICS, exist_ok=True)
    return [(pretty(f), os.path.join(PICS, f)) for f in sorted(os.listdir(PICS), key=str.lower)
            if os.path.isfile(os.path.join(PICS, f)) and f.lower().endswith(IMAGES)]


def steam_root():
    for r in STEAM_ROOTS:
        if os.path.isdir(os.path.join(r, "steamapps")):
            return os.path.realpath(r)
    return None


def we_installed(root):
    return bool(root) and os.path.isdir(os.path.join(root, "steamapps", "common", "wallpaper_engine", "assets"))


def workshop_items(root):
    items = []
    for d in sorted(glob.glob(os.path.join(root or "/nonexistent", "steamapps", "workshop", "content", WE_APP, "*"))):
        title, preview = os.path.basename(d), None
        try:
            with open(os.path.join(d, "project.json"), encoding="utf-8") as f:
                p = json.load(f)
            title = p.get("title") or title
            if p.get("preview"):
                preview = os.path.join(d, p["preview"])
        except (OSError, ValueError):
            pass
        if not preview or not os.path.exists(preview):
            found = [x for x in glob.glob(os.path.join(d, "preview.*")) if x.lower().endswith(IMAGES)]
            preview = found[0] if found else None
        items.append((title, preview, d))
    return items


def live_problem():
    """Why the live wallpaper isn't showing, in words — or None if it is."""
    if not read(LIVE):
        return None
    if quiet("systemctl", "--user", "is-active", "--quiet", "wallpaper-live.service") == 0:
        return None
    last = run("journalctl", "--user", "-u", "wallpaper-live.service", "-n", "1", "-o", "cat", "--no-pager")
    return last or "The live wallpaper service isn't running."


def snow_running():
    return quiet("pgrep", "-f", "(^|/)xsnow( |$)") == 0


# ── a thumbnail with rounded corners ────────────────────────────────────────
class Thumb(Gtk.DrawingArea):
    def __init__(self, w, h, radius=10):
        super().__init__()
        self.pix, self.radius = None, radius
        self.set_size_request(w, h)
        self.connect("draw", self.on_draw)

    def set_pixbuf(self, pix):
        self.pix = pix
        self.queue_draw()

    def on_draw(self, _w, cr):
        w, h, r = self.get_allocated_width(), self.get_allocated_height(), self.radius
        cr.new_sub_path()
        for cx, cy, a in ((w - r, r, -90), (w - r, h - r, 0), (r, h - r, 90), (r, r, 180)):
            cr.arc(cx, cy, r, a * 3.14159 / 180, (a + 90) * 3.14159 / 180)
        cr.close_path()
        cr.clip()
        if self.pix:
            pw, ph = self.pix.get_width(), self.pix.get_height()
            s = max(w / pw, h / ph)                      # cover, centred
            cr.translate((w - pw * s) / 2, (h - ph * s) / 2)
            cr.scale(s, s)
            Gdk.cairo_set_source_pixbuf(cr, self.pix, 0, 0)
        else:
            cr.set_source_rgba(.5, .55, .65, .18)
        cr.paint()
        return False


# ── the window ──────────────────────────────────────────────────────────────
class Wallpapers(Gtk.Window):
    def __init__(self):
        super().__init__(title="Wallpapers")
        self.set_default_size(1180, 780)
        Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", True)
        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.header = Gtk.HeaderBar(title="Wallpapers", show_close_button=True)
        self.set_titlebar(self.header)
        add = Gtk.Button(label="Add pictures…")
        add.connect("clicked", lambda _b: self.add_pictures())
        self.header.pack_start(add)

        self.queue, self.cards = [], {}
        outer = Gtk.Box()
        self.add(outer)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, hexpand=True)
        side = Gtk.StackSidebar(stack=self.stack)
        side.set_size_request(190, -1)
        side.get_style_context().add_class("side")
        outer.pack_start(side, False, False, 0)
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.pack_start(right, True, True, 0)
        right.pack_start(self.build_hero(), False, False, 0)
        right.pack_start(self.stack, True, True, 0)

        self.pages = {}
        for key, title in (("builtin", "Built in"), ("mine", "My pictures"), ("live", "Live")):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            self.pages[key] = box
            self.stack.add_titled(box, key, title)
        self.refresh()

    # top: the current wallpaper and its settings
    def build_hero(self):
        hero = Gtk.Box(spacing=22)
        hero.get_style_context().add_class("hero")
        self.preview = Thumb(352, 198, radius=12)
        hero.pack_start(self.preview, False, False, 0)
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, valign=Gtk.Align.CENTER)
        hero.pack_start(info, True, True, 0)
        self.now_title = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.now_title.get_style_context().add_class("hero-title")
        self.now_sub = Gtk.Label(xalign=0)
        self.now_sub.get_style_context().add_class("hero-sub")
        info.pack_start(self.now_title, False, False, 0)
        info.pack_start(self.now_sub, False, False, 0)

        row = Gtk.Box(spacing=10, margin_top=6)
        info.pack_start(row, False, False, 0)
        row.pack_start(Gtk.Label(label="Fit"), False, False, 0)
        self.fit = Gtk.ComboBoxText()
        for label, mode in FITS:
            self.fit.append(mode, label)
        self.fit.set_active_id(read(FIT) or "zoom")
        self.fit.connect("changed", lambda c: self.set_fit(c.get_active_id()))
        row.pack_start(self.fit, False, False, 0)
        shuffle = Gtk.Button(label="Shuffle")
        shuffle.connect("clicked", lambda _b: self.shuffle())
        row.pack_start(shuffle, False, False, 0)

        row2 = Gtk.Box(spacing=10)
        info.pack_start(row2, False, False, 0)
        row2.pack_start(Gtk.Label(label="Falling snow"), False, False, 0)
        snow = Gtk.Switch(active=snow_running(), valign=Gtk.Align.CENTER)
        snow.connect("notify::active", lambda s, _p: spawn("snow", "on" if s.get_active() else "off"))
        row2.pack_start(snow, False, False, 0)
        return hero

    def show_current(self):
        live = read(LIVE)
        if live:
            title = next((t for t, _p, d in workshop_items(steam_root()) if d == live), os.path.basename(live))
            prev = next((p for t, p, d in workshop_items(steam_root()) if d == live), None)
            self.now_title.set_text(title)
            self.now_sub.set_text("Live wallpaper (Wallpaper Engine)")
        else:
            path = os.path.realpath(CURRENT_BG) if os.path.exists(CURRENT_BG) else None
            prev = path
            self.now_title.set_text(pretty(path) if path else "No wallpaper set")
            self.now_sub.set_text("Picture" if path else "Pick one below")
        self.preview.set_pixbuf(self.load(prev, 704, 396) if prev else None)
        self.header.set_subtitle("Now: " + self.now_title.get_text())
        for path, card in self.cards.items():
            ctx = card.get_style_context()
            (ctx.add_class if path in (live, os.path.realpath(CURRENT_BG) if os.path.exists(CURRENT_BG) else "") else ctx.remove_class)("current")

    # grids
    def refresh(self):
        self.queue.clear()
        self.cards.clear()
        b = builtins()
        self.fill(self.pages["builtin"], [(t, p, p) for t, p in b], self.set_picture,
                  "The built-in wallpapers are missing from this build.")
        m = mine()
        self.fill(self.pages["mine"], [(t, p, p) for t, p in m], self.set_picture,
                  f"Your pictures go in {PICS.replace(HOME, '~')}.\nUse “Add pictures…” or drop images into that folder.",
                  bar=[("Open folder", lambda: spawn("xdg-open", PICS)), ("Refresh", self.refresh)])
        self.fill_live()
        self.show_current()
        GLib.idle_add(self.load_next)
        self.show_all()

    def fill(self, page, entries, on_pick, empty, bar=None, notice=None):
        for c in page.get_children():
            page.remove(c)
        if notice:
            n = Gtk.Label(label=notice, xalign=0, wrap=True)
            n.get_style_context().add_class("notice")
            page.pack_start(n, False, False, 0)
        if bar:
            row = Gtk.Box(spacing=8)
            row.get_style_context().add_class("bar")
            for label, cb in bar:
                btn = Gtk.Button(label=label)
                btn.connect("clicked", lambda _b, f=cb: f())
                row.pack_start(btn, False, False, 0)
            page.pack_start(row, False, False, 0)
        if not entries:
            lab = Gtk.Label(label=empty, justify=Gtk.Justification.LEFT, wrap=True, vexpand=True, halign=Gtk.Align.CENTER)
            lab.get_style_context().add_class("empty")
            page.pack_start(lab, True, True, 0)
            return
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True, max_children_per_line=8,
                           row_spacing=8, column_spacing=8, margin=14, valign=Gtk.Align.START)
        for title, preview, value in entries:
            thumb = Thumb(TW, TH)
            label = Gtk.Label(label=title, max_width_chars=26, ellipsize=Pango.EllipsizeMode.END, xalign=0)
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            inner.pack_start(thumb, False, False, 0)
            inner.pack_start(label, False, False, 0)
            card = Gtk.Button(relief=Gtk.ReliefStyle.NONE, tooltip_text=title)
            card.get_style_context().add_class("card")
            card.add(inner)
            card.connect("clicked", lambda _b, v=value, t=title: on_pick(v, t))
            flow.add(card)
            self.cards[value] = card
            if preview:
                self.queue.append((thumb, preview))
        scroll = Gtk.ScrolledWindow(vexpand=True)
        scroll.add(flow)
        page.pack_start(scroll, True, True, 0)

    def fill_live(self):
        root = steam_root()
        store = lambda: spawn("xdg-open", f"steam://store/{WE_APP}")                    # noqa: E731
        workshop = lambda: spawn("xdg-open", f"steam://url/SteamWorkshopPage/{WE_APP}")  # noqa: E731
        if not we_installed(root):
            self.fill(self.pages["live"], [], None,
                      "Animated wallpapers from Wallpaper Engine play here, on every screen —\n"
                      "muted, at 30 fps, and paused while a game is fullscreen.\n\n"
                      "1.  Buy and install Wallpaper Engine in Steam (Steam Play is on, so the\n"
                      "     Windows app installs fine — you never need to open it).\n"
                      "2.  Subscribe to wallpapers in the Steam Workshop.\n"
                      "3.  They appear in this tab.",
                      bar=[("Get Wallpaper Engine", store), ("Check again", self.refresh)])
            return
        items = workshop_items(root)
        problem = live_problem()
        self.fill(self.pages["live"], [(t, p, d) for t, p, d in items], self.set_live,
                  "No wallpapers yet. Subscribe to some in the Steam Workshop;\nthey appear here once Steam has downloaded them.",
                  bar=[("Stop live wallpaper", self.stop_live), ("Browse the Workshop", workshop), ("Refresh", self.refresh)],
                  notice=("The live wallpaper isn't running: " + problem) if problem else None)

    def load(self, path, w, h):
        try:
            return GdkPixbuf.Pixbuf.new_from_file_at_scale(path, w, h, True)
        except GLib.Error:
            return None

    def load_next(self):
        if not self.queue:
            return False
        thumb, path = self.queue.pop(0)
        thumb.set_pixbuf(self.load(path, TW * 2, TH * 2))
        return True

    # actions
    def set_picture(self, path, _title):
        self.stop_live(quiet_status=True)
        spawn("setbg", path)
        GLib.timeout_add(400, lambda: (spawn("xwallpaper", "--" + (read(FIT) or "zoom"), CURRENT_BG), False)[1])
        GLib.timeout_add(450, lambda: (self.show_current(), False)[1])

    def set_fit(self, mode):
        os.makedirs(CONF, exist_ok=True)
        with open(FIT, "w", encoding="utf-8") as f:
            f.write(mode + "\n")
        if not read(LIVE) and os.path.exists(CURRENT_BG):
            spawn("xwallpaper", "--" + mode, CURRENT_BG)

    def shuffle(self):
        pool = [p for _t, p in builtins() + mine() if p != os.path.realpath(CURRENT_BG)]
        if pool:
            p = random.choice(pool)
            self.set_picture(p, pretty(p))

    def set_live(self, path, _title):
        os.makedirs(CONF, exist_ok=True)
        with open(LIVE, "w", encoding="utf-8") as f:
            f.write(path + "\n")
        spawn("systemctl", "--user", "restart", "wallpaper-live.service")
        GLib.timeout_add(3000, lambda: (self.refresh(), False)[1])     # shows a notice if it failed to start
        self.show_current()

    def stop_live(self, quiet_status=False):
        try:
            os.remove(LIVE)
        except OSError:
            pass
        quiet("systemctl", "--user", "stop", "wallpaper-live.service")
        if not quiet_status:
            spawn("setbg")
            self.show_current()

    def add_pictures(self):
        d = Gtk.FileChooserDialog(title="Add wallpapers", parent=self, action=Gtk.FileChooserAction.OPEN)
        d.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Add", Gtk.ResponseType.OK)
        d.set_select_multiple(True)
        f = Gtk.FileFilter()
        f.set_name("Images")
        for ext in IMAGES:
            f.add_pattern("*" + ext)
            f.add_pattern("*" + ext.upper())
        d.add_filter(f)
        if d.run() == Gtk.ResponseType.OK:
            os.makedirs(PICS, exist_ok=True)
            for src in d.get_filenames():
                try:
                    shutil.copy2(src, PICS)
                except OSError:
                    pass
        d.destroy()
        self.refresh()
        self.stack.set_visible_child_name("mine")


def main():
    w = Wallpapers()
    w.connect("destroy", Gtk.main_quit)
    w.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
