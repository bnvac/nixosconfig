# The few values you'd actually change. Imported by the modules.
{
  username = "samadams";
  fullName = "Sam Adams";
  hostName = "live";
  timeZone = "America/New_York";

  stAlpha = "0.72";          # terminal transparency (1.0 = opaque)

  # `nixup` pulls this repo (cloned at /etc/nixos) and rebuilds — no re-cloning.
  # autoUpdate = true adds a weekly timer that pulls + rebuilds on its own.
  autoUpdate = false;

  # Boot. espMountPoint must match hardware-configuration.nix (checked at build).
  espMountPoint = "/boot/efi";
  useGrub = true;            # GRUB = themeable; false = systemd-boot

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
