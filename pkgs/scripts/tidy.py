"""tidy — clean up your home folder and Downloads.

  tidy              both: loose files in ~ go where they belong, then
                    Downloads is sorted into folders by type
  tidy --home       only the home folder
  tidy --downloads  only Downloads (what `tidy-downloads` does)
  tidy --dry-run    show what it would do, change nothing (combine with the above)
  tidy --undo       put everything from the last run back

Home folder: only loose FILES at the top of ~ are moved — never folders,
dotfiles, links, or files you were working on in the last minute.
    screenshots (screenshot tools' names)  → ~/Pictures/screenshots
    screen recordings                      → ~/Videos/recordings
    pictures / videos / music / documents  → ~/Pictures, ~/Videos, ~/Music, ~/Documents
    everything else (installers, archives, code, unknown…)  → ~/Downloads,
    which the Downloads step then sorts like any other download.
Downloads: loose files go into Images/, Documents/, Installers/… folders.
A file whose CONTENT is already where it's headed (sha256, not the name)
goes to Downloads/Duplicates/ instead — nothing is ever deleted. Files still
downloading (.part/.crdownload) are left alone.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
KINDS = {
    "Images": "jpg jpeg png gif webp bmp svg heic heif tif tiff avif ico raw cr2 nef",
    "Videos": "mp4 mkv webm mov avi m4v flv wmv mpg mpeg",
    "Audio": "mp3 flac wav ogg opus m4a aac wma",
    "Documents": "pdf doc docx odt rtf txt md epub mobi azw3 xls xlsx ods csv ppt pptx odp tex",
    "Archives": "zip tar gz tgz bz2 xz zst 7z rar",
    "Installers": "appimage deb rpm iso img exe msi flatpakref dmg",
    "Code": "py js ts sh json yaml yml toml nix c h cpp hpp rs go java html css ipynb",
    "3D & CAD": "stl 3mf obj step stp gcode bgcode f3d scad fcstd",
    "Electronics": "kicad_pcb kicad_sch kicad_pro gbr drl brd sch ino",
    "Torrents": "torrent",
}
EXT = {e: kind for kind, exts in KINDS.items() for e in exts.split()}
PARTIAL = (".part", ".crdownload", ".download", ".tmp", ".partial")
DUPES = "Duplicates"
SCREENSHOT = re.compile(r"^(pic-(full|selected|window)-|screenshot|scrot|shot[-_ ]|\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d)", re.I)
RECORDING = re.compile(r"^(screencast|recording|video-?\d|webcam|audio-?\d)", re.I)
KEEP_IN_HOME = {"SYSTEM.md"}          # Neb's note — the system rewrites it there every rebuild
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state")) / "tidy"
LOG = STATE / "last-run.json"


def user_dir(name: str, fallback: str) -> Path:
    try:
        d = subprocess.run(["xdg-user-dir", name], capture_output=True, text=True, timeout=3).stdout.strip()
        if d and d != str(HOME):
            return Path(d)
    except (OSError, subprocess.SubprocessError):
        pass
    return HOME / fallback


def kind_of(p: Path) -> str:
    name = p.name.lower()
    for ext in sorted(EXT, key=len, reverse=True):    # longest first: kicad_pcb before pcb, tar.gz → gz
        if name.endswith("." + ext):
            return EXT[ext]
    return "Other"


def sha(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def free_name(dest: Path) -> Path:
    """dest, or 'name (2).ext' etc. if something different already has that name."""
    if not dest.exists():
        return dest
    stem, suf, n = dest.stem, dest.suffix, 2
    while (dest.parent / f"{stem} ({n}){suf}").exists():
        n += 1
    return dest.parent / f"{stem} ({n}){suf}"


def show(p: Path) -> str:
    try:
        return "~/" + str(p.relative_to(HOME))
    except ValueError:
        return str(p)


def notify(msg: str) -> None:
    print(msg)
    try:
        subprocess.run(["notify-send", "-a", "Tidy", "-i", "folder", "Tidy", msg], timeout=3)
    except (OSError, subprocess.SubprocessError):
        pass


def loose_files(folder: Path, now: float) -> list:
    return [p for p in folder.iterdir()
            if p.is_file() and not p.is_symlink() and not p.name.startswith(".")
            and not p.name.lower().endswith(PARTIAL) and now - p.stat().st_mtime > 60]


class Seen:
    """Content hashes of files already in a folder, found cheaply: only files
    whose SIZE matches something being moved get hashed."""

    def __init__(self):
        self.by_size: dict = {}
        self.hashed: dict = {}
        self.scanned: set = set()

    def scan(self, folder: Path) -> None:
        if folder in self.scanned or not folder.is_dir():
            return
        self.scanned.add(folder)
        for p in folder.rglob("*"):
            if p.is_file() and not p.is_symlink() and not p.name.startswith("."):
                self.by_size.setdefault(p.stat().st_size, []).append(p)

    def has(self, p: Path, digest: str) -> bool:
        for other in self.by_size.get(p.stat().st_size, []):
            if other == p:
                continue
            if other not in self.hashed:
                self.hashed[other] = sha(other)
            if self.hashed[other] == digest:
                return True
        return False

    def add(self, dest: Path, size: int, digest: str) -> None:
        self.by_size.setdefault(size, []).append(dest)
        self.hashed[dest] = digest


def plan_home(now: float, downloads: Path) -> list:
    pics, vids = user_dir("PICTURES", "Pictures"), user_dir("VIDEOS", "Videos")
    target = {
        "Images": pics, "Videos": vids, "Audio": user_dir("MUSIC", "Music"),
        "Documents": user_dir("DOCUMENTS", "Documents"),
    }
    out = []
    for p in loose_files(HOME, now):
        if p.name in KEEP_IN_HOME:
            continue
        kind = kind_of(p)
        if kind == "Images" and SCREENSHOT.match(p.name):
            dest_dir = pics / "screenshots"
        elif kind in ("Videos", "Audio") and RECORDING.match(p.name):
            dest_dir = vids / "recordings"
        else:
            dest_dir = target.get(kind, downloads)        # anything else: Downloads sorts it next
        out.append((p, dest_dir))
    return out


def plan_downloads(now: float, downloads: Path, extra: list) -> list:
    files = (loose_files(downloads, now) if downloads.is_dir() else []) + extra
    return [(p, downloads / kind_of(p)) for p in files]


def run(do_home: bool, do_downloads: bool, dry: bool) -> int:
    now = time.time()
    downloads = user_dir("DOWNLOAD", "Downloads")
    seen = Seen()
    moves, dupes, done = [], 0, []

    home_plan = plan_home(now, downloads) if do_home else []
    # files headed for Downloads skip the stop-over and go straight to their type folder
    via_downloads = [p for p, d in home_plan if d == downloads] if do_downloads else []
    plan = [(p, d) for p, d in home_plan if not (d == downloads and do_downloads)]
    plan += plan_downloads(now, downloads, via_downloads) if do_downloads else []
    if not plan:
        notify("Already tidy.")
        return 0

    for p, dest_dir in sorted(plan, key=lambda x: x[0].stat().st_mtime):   # oldest keeps the name
        seen.scan(dest_dir)
        digest = sha(p)
        if seen.has(p, digest):
            dest, dupes = free_name(downloads / DUPES / p.name), dupes + 1
        else:
            dest = free_name(dest_dir / p.name)
            seen.add(dest, p.stat().st_size, digest)
        moves.append((p, dest))

    for src, dest in moves:
        print(f"{'would move' if dry else 'move'}  {show(src)}  →  {show(dest)}")
    if dry:
        return 0
    created = []
    for src, dest in moves:
        d = dest.parent
        while not d.exists():                      # remember folders this run makes, for --undo
            created.append(str(d))
            d = d.parent
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dest))
        done.append([str(src), str(dest)])
    STATE.mkdir(parents=True, exist_ok=True)
    LOG.write_text(json.dumps({"time": int(now), "moves": done, "created": created}, indent=1))
    n = len(done) - dupes
    notify(f"Tidied {n} file{'s' * (n != 1)}"
           + (f", {dupes} duplicate{'s' * (dupes != 1)} → Downloads/{DUPES}" if dupes else "")
           + ".  (undo: tidy --undo)")
    return 0


def undo() -> int:
    log_file = LOG
    old = user_dir("DOWNLOAD", "Downloads") / ".tidy-log"      # from the old tidy-downloads
    if not log_file.exists() and old.exists():
        log_file = old
    try:
        log = json.loads(log_file.read_text())
    except (OSError, ValueError):
        notify("Nothing to undo.")
        return 0
    back, made = 0, set()
    for src, dest in reversed(log["moves"]):
        s, d = Path(src), Path(dest)
        if d.exists() and not s.exists():
            shutil.move(str(d), str(s))
            back += 1
            made.add(d.parent)
    # Remove the folders the run created (only if they're empty again); the old
    # tidy-downloads log has no list, so fall back to the folders files came out of.
    created = [Path(c) for c in log.get("created", [])] or list(made)
    for folder in sorted(created, key=lambda f: len(f.parts), reverse=True):
        try:
            folder.rmdir()
        except OSError:
            pass
    log_file.unlink(missing_ok=True)
    notify(f"Put {back} file{'s' * (back != 1)} back.")
    return 0


def main(argv: list) -> int:
    if "-h" in argv or "--help" in argv:
        print(__doc__.strip())
        return 0
    if "--undo" in argv:
        return undo()
    home, dls = "--home" in argv, "--downloads" in argv
    if not home and not dls:
        home = dls = True
    return run(home, dls, "--dry-run" in argv or "-n" in argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
