# The few values you'd actually change. Imported by the modules.
{
  username = "samadams";
  fullName = "Sam Adams";
  hostName = "live";
  timeZone = "America/New_York";

  # Terminal opacity, 0.0–1.0 (1.0 = fully opaque). The compositor (picom)
  # applies it; a FULLSCREEN terminal (Super+f) is always forced fully opaque.
  termOpacity = "0.72";
  liveSnow = true;           # falling snow over the wallpaper (`snow off` for now)

  # `nixup` pulls this repo (cloned at /etc/nixos) and rebuilds — no re-cloning.
  # autoUpdate = true adds a weekly timer that pulls + rebuilds on its own.
  autoUpdate = false;

  # Boot. espMountPoint must match hardware-configuration.nix (checked at build).
  espMountPoint = "/boot/efi";
  useGrub = true;            # GRUB = themeable; false = systemd-boot

  # ── Backups (`backups` module): restic to an external drive ────────────────
  # The restic repository on your backup drive. Backups run only while the drive
  # is mounted — if it isn't plugged in you get a reminder, not a failure. The
  # repo password lives in a file (see the module header); `backup` wraps restic
  # (snapshots / restore / check), `backup now` runs one immediately.
  backupRepo = "/run/media/samadams/BACKUP/restic";

  # ── 3D printers (`printing` module): Moonraker URLs to watch ───────────────
  # Each printer's Moonraker API base URL. A desktop notification pops when a
  # print finishes or fails. Empty = nothing watched.
  #   e.g. [ "http://ender.local:7125" "http://voron.local:7125" ]
  printers = [ ];

  # ── WHICH MACHINE IS THIS? ─────────────────────────────────────────────────
  # Set this per machine (it's the only line that differs between them).
  #   "desktop" — has the RX 6750 XT: Neb runs a LOCAL model (Ollama, free).
  #   "laptop"  — no GPU: Neb uses an API brain (Anthropic/OpenAI key).
  device = "desktop";

  # ── Syncthing device IDs (for the `sync` module) ───────────────────────────
  # Fill these in AFTER the first boot on each machine:
  #   run `syncthing` once, open http://127.0.0.1:8384, Actions → Show ID,
  #   and paste each machine's ID here. Until both are set, Syncthing still runs
  #   and you can pair by hand in the web UI — this just makes it declarative.
  syncIds = {
    desktop = "";   # paste the desktop's Syncthing ID
    laptop  = "";   # paste the laptop's Syncthing ID
  };
}
