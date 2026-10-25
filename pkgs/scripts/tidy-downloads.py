"""tidy-downloads — sort ~/Downloads into folders and catch duplicates.

  tidy-downloads            sort loose files into Images/, Documents/, …
  tidy-downloads --dry-run  show what it would do, change nothing
  tidy-downloads --undo     put the last run's files back where they were

Only loose files at the top of Downloads are moved; your folders are left
alone. A file whose CONTENT matches one already there (sha256, not the name)
goes to Duplicates/ — nothing is ever deleted. Files still downloading
(.part/.crdownload, or touched in the last minute) are skipped. Every move is
logged to .tidy-log so --undo can reverse it.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

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
DUPES, LOG = "Duplicates", ".tidy-log"


def downloads() -> Path:
    try:
        d = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True).stdout.strip()
        if d and d != str(Path.home()):
            return Path(d)
    except OSError:
        pass
    return Path.home() / "Downloads"


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


def notify(msg: str) -> None:
    print(msg)
    try:
        subprocess.run(["notify-send", "-i", "folder-download", "Downloads", msg], timeout=3)
    except (OSError, subprocess.SubprocessError):
        pass


def tidy(root: Path, dry: bool) -> int:
    if not root.is_dir():
        notify(f"No {root} folder.")
        return 1
    now = time.time()
    loose = [p for p in root.iterdir()
             if p.is_file() and not p.is_symlink() and not p.name.startswith(".")
             and not p.name.lower().endswith(PARTIAL) and now - p.stat().st_mtime > 60]
    if not loose:
        notify("Downloads is already tidy.")
        return 0

    # hashes of everything already sorted, so a new file matching an old one is caught
    known: dict[str, Path] = {}
    for kind in [*KINDS, "Other", DUPES]:
        d = root / kind
        if d.is_dir():
            for p in d.rglob("*"):
                if p.is_file() and not p.is_symlink():
                    known.setdefault(sha(p), p)

    moves, dupes = [], 0
    for p in sorted(loose, key=lambda q: q.stat().st_mtime):     # oldest first keeps the original
        digest = sha(p)
        if digest in known:
            dest, dupes = free_name(root / DUPES / p.name), dupes + 1
        else:
            dest = free_name(root / kind_of(p) / p.name)
            known[digest] = dest
        moves.append((p, dest))

    for src, dest in moves:
        print(f"{'would move' if dry else 'move'}  {src.name}  →  {dest.relative_to(root)}")
    if dry:
        return 0
    done = []
    for src, dest in moves:
        dest.parent.mkdir(exist_ok=True)
        shutil.move(str(src), str(dest))
        done.append([str(src), str(dest)])
    (root / LOG).write_text(json.dumps({"time": int(now), "moves": done}, indent=1))
    sorted_n = len(done) - dupes
    notify(f"Sorted {sorted_n} file{'s' * (sorted_n != 1)} into folders"
           + (f", moved {dupes} duplicate{'s' * (dupes != 1)} to {DUPES}/" if dupes else "")
           + ".  (undo: tidy-downloads --undo)")
    return 0


def undo(root: Path) -> int:
    try:
        log = json.loads((root / LOG).read_text())
    except (OSError, ValueError):
        notify("Nothing to undo.")
        return 0
    back = 0
    for src, dest in reversed(log["moves"]):
        s, d = Path(src), Path(dest)
        if d.exists() and not s.exists():
            shutil.move(str(d), str(s))
            back += 1
    for kind in [*KINDS, "Other", DUPES]:                       # drop folders the run created, if empty
        try:
            (root / kind).rmdir()
        except OSError:
            pass
    (root / LOG).unlink(missing_ok=True)
    notify(f"Put {back} file{'s' * (back != 1)} back.")
    return 0


def main(argv: list) -> int:
    root = Path(os.environ.get("TIDY_DIR") or downloads())
    if "--undo" in argv:
        return undo(root)
    return tidy(root, "--dry-run" in argv or "-n" in argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
