# wallpapers — pick your wallpaper (Super+Alt+w).
#   Pictures          your images (~/Pictures/wallpapers) + the snowy default;
#                     click one to set it (LARBS setbg, so it sticks across logins)
#   Wallpaper Engine  your subscribed Steam Workshop wallpapers, played live on
#                     every screen by linux-wallpaperengine (the wallpaper-live
#                     service: muted, 30 fps, paused while a game is fullscreen)
# Plus a switch for the falling snow.
import glob
import json
import os
import random
import shutil
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Pango", "1.0")
from gi.repository import GdkPixbuf, GLib, Gtk, Pango  # noqa: E402

HOME = os.path.expanduser("~")
PICS = os.environ.get("WALLPAPER_DIR", os.path.join(HOME, "Pictures", "wallpapers"))
BUILTIN = os.environ.get("WALLPAPER_BUILTIN", "")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "wallpapers")
LIVE = os.path.join(CONF, "live")
CURRENT_BG = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.join(HOME, ".local", "share")), "bg")
WE_APP = "431960"
STEAM_ROOTS = [os.path.join(HOME, ".local", "share", "Steam"), os.path.join(HOME, ".steam", "steam")]
IMAGES = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif")
TW, TH = 256, 144


def spawn(*cmd):
    try:
        subprocess.Popen(cmd, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass


def quiet(*cmd):
    try:
        return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    except FileNotFoundError:
        return 127


def steam_root():
    for r in STEAM_ROOTS:
        if os.path.isdir(os.path.join(r, "steamapps")):
            return os.path.realpath(r)
    return None


def we_installed(root):
    return bool(root) and os.path.isdir(os.path.join(root, "steamapps", "common", "wallpaper_engine", "assets"))


def workshop_items(root):
    items = []
    if not root:
        return items
    for d in sorted(glob.glob(os.path.join(root, "steamapps", "workshop", "content", WE_APP, "*"))):
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


def pictures():
    os.makedirs(PICS, exist_ok=True)
    out = []
    if BUILTIN and os.path.exists(BUILTIN):
        out.append(("Snowy night (default)", BUILTIN))
    for f in sorted(os.listdir(PICS), key=str.lower):
        p = os.path.join(PICS, f)
        if os.path.isfile(p) and f.lower().endswith(IMAGES):
            out.append((os.path.splitext(f)[0], p))
    return out


def snow_running():
    return quiet("pgrep", "-f", "(^|/)xsnow( |$)") == 0


class Wallpapers(Gtk.Window):
    def __init__(self):
        super().__init__(title="Wallpapers")
        self.set_default_size(1100, 700)
        self.header = Gtk.HeaderBar(title="Wallpapers", show_close_button=True)
        self.set_titlebar(self.header)

        snow = Gtk.Switch(active=snow_running(), valign=Gtk.Align.CENTER)
        snow.connect("notify::active", lambda s, _: spawn("snow", "on" if s.get_active() else "off"))
        box = Gtk.Box(spacing=6)
        box.pack_start(Gtk.Label(label="Falling snow"), False, False, 0)
        box.pack_start(snow, False, False, 0)
        self.header.pack_end(box)

        self.tabs = Gtk.Notebook()
        self.add(self.tabs)
        self.pics_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.live_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.tabs.append_page(self.pics_page, Gtk.Label(label="Pictures"))
        self.tabs.append_page(self.live_page, Gtk.Label(label="Wallpaper Engine (live)"))
        self.queue = []
        self.fill_pictures()
        self.fill_live()
        self.show_status()

    # ── shared bits ─────────────────────────────────────────────────────────
    def show_status(self):
        live = ""
        try:
            with open(LIVE, encoding="utf-8") as f:
                live = f.read().strip()
        except OSError:
            pass
        if live:
            name = next((t for t, _, d in workshop_items(steam_root()) if d == live), os.path.basename(live))
            self.header.set_subtitle("Now: " + name + " (live)")
        elif os.path.exists(CURRENT_BG):
            self.header.set_subtitle("Now: " + os.path.basename(os.path.realpath(CURRENT_BG)))
        else:
            self.header.set_subtitle("")

    def toolbar(self, page, buttons):
        bar = Gtk.Box(spacing=6, margin=8)
        for label, cb in buttons:
            b = Gtk.Button(label=label)
            b.connect("clicked", lambda _b, f=cb: f())
            bar.pack_start(b, False, False, 0)
        page.pack_start(bar, False, False, 0)

    def grid(self, page, entries, on_pick):
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=True,
                           max_children_per_line=8, row_spacing=10, column_spacing=10, margin=10,
                           valign=Gtk.Align.START)
        for title, path, value in entries:
            img = Gtk.Image.new_from_icon_name("image-x-generic", Gtk.IconSize.DIALOG)
            img.set_size_request(TW, TH)
            label = Gtk.Label(label=title, max_width_chars=28, ellipsize=Pango.EllipsizeMode.END)
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            inner.pack_start(img, False, False, 0)
            inner.pack_start(label, False, False, 0)
            b = Gtk.Button(relief=Gtk.ReliefStyle.NONE)
            b.add(inner)
            b.set_tooltip_text(title)
            b.connect("clicked", lambda _b, v=value, t=title: on_pick(v, t))
            flow.add(b)
            if path:
                self.queue.append((img, path))
        scroll = Gtk.ScrolledWindow(vexpand=True)
        scroll.add(flow)
        page.pack_start(scroll, True, True, 0)
        GLib.idle_add(self.load_next)      # thumbnails load in the background

    def load_next(self):
        if not self.queue:
            return False
        img, path = self.queue.pop(0)
        try:
            img.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(path, TW, TH, True))
        except GLib.Error:
            pass
        return True

    def clear(self, page):
        for c in page.get_children():
            page.remove(c)

    def message(self, page, text, buttons):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=40,
                      valign=Gtk.Align.CENTER, halign=Gtk.Align.CENTER)
        box.pack_start(Gtk.Label(label=text, wrap=True, max_width_chars=70, justify=Gtk.Justification.CENTER), False, False, 0)
        row = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        for label, cb in buttons:
            b = Gtk.Button(label=label)
            b.connect("clicked", lambda _b, f=cb: f())
            row.pack_start(b, False, False, 0)
        box.pack_start(row, False, False, 0)
        page.pack_start(box, True, True, 0)

    # ── Pictures ────────────────────────────────────────────────────────────
    def fill_pictures(self):
        self.clear(self.pics_page)
        pics = pictures()
        self.toolbar(self.pics_page, [
            ("Add pictures…", self.add_pictures),
            ("Open folder", lambda: spawn("xdg-open", PICS)),
            ("Random", lambda: pics and self.set_picture(*random.choice(pics)[::-1])),
            ("Refresh", self.fill_pictures),
        ])
        self.grid(self.pics_page, [(t, p, p) for t, p in pics], self.set_picture)
        if len(pics) <= 1:
            hint = Gtk.Label(label=f"Drop images into {PICS} (or use “Add pictures…”) and they show up here.",
                             margin=6)
            self.pics_page.pack_start(hint, False, False, 0)
        self.pics_page.show_all()

    def set_picture(self, path, title):
        self.stop_live(quiet_status=True)
        spawn("setbg", path)
        self.header.set_subtitle("Now: " + title)

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
        self.fill_pictures()

    # ── Wallpaper Engine ────────────────────────────────────────────────────
    def fill_live(self):
        self.clear(self.live_page)
        root = steam_root()
        store = lambda: spawn("xdg-open", f"steam://store/{WE_APP}")          # noqa: E731
        workshop = lambda: spawn("xdg-open", f"steam://url/SteamWorkshopPage/{WE_APP}")  # noqa: E731
        if not we_installed(root):
            self.message(self.live_page,
                         "Wallpaper Engine wallpapers play live here, on every screen — muted, at 30 fps, "
                         "and paused while a game is fullscreen.\n\n"
                         "1. Get Wallpaper Engine on Steam (it's a paid app) and install it — Steam Play is "
                         "already switched on, so Steam will install it even though it's a Windows app. "
                         "You never need to run it.\n"
                         "2. Subscribe to wallpapers in the Steam Workshop.\n"
                         "3. They show up in this tab.",
                         [("Get it on Steam", store), ("Check again", self.fill_live)])
        else:
            items = workshop_items(root)
            self.toolbar(self.live_page, [
                ("Stop live wallpaper", self.stop_live),
                ("Browse the Workshop", workshop),
                ("Refresh", self.fill_live),
            ])
            if items:
                self.grid(self.live_page, [(t, p, d) for t, p, d in items], self.set_live)
            else:
                self.message(self.live_page, "No wallpapers yet — subscribe to some in the Steam Workshop "
                             "and they'll appear here once Steam has downloaded them.",
                             [("Browse the Workshop", workshop), ("Check again", self.fill_live)])
        self.live_page.show_all()

    def set_live(self, path, title):
        os.makedirs(CONF, exist_ok=True)
        with open(LIVE, "w", encoding="utf-8") as f:
            f.write(path + "\n")
        spawn("systemctl", "--user", "restart", "wallpaper-live.service")
        self.header.set_subtitle("Now: " + title + " (live)")

    def stop_live(self, quiet_status=False):
        try:
            os.remove(LIVE)
        except OSError:
            pass
        quiet("systemctl", "--user", "stop", "wallpaper-live.service")
        if not quiet_status:
            spawn("setbg")              # put the picture wallpaper back
            self.show_status()


def main():
    w = Wallpapers()
    w.connect("destroy", Gtk.main_quit)
    w.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
