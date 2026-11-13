# nix²'s settings: every value you can change, with its default.
#
# DON'T EDIT THIS FILE for your own machine. Your values live in
# settings.local.nix next to it (not in git, so updates never clash with
# them). `nix2-setup` writes it for you, and `modtui` → Edit settings, `mod`
# and `debloat remove` change it. Any name below can go there, one per line:
#
#   username = "ada";
#   gpu = "nvidia";
#   location.latitude = 51.5;
#   modules.virt = true;          # switch a module on (or false: off)
#
# Values from settings.local.nix replace the defaults here; nested ones
# (location, menu, modules…) merge key by key.
let
  defaults = {
    # ── You and this machine (nix2-setup asks for these) ────────────────────
    username = "user";
    fullName = "nix² user";
    hostName = "nix2";
    timeZone = "UTC";
    # "desktop" or "laptop" — laptops get battery/thermal tuning (`power`).
    device = "desktop";
    # Keyboard layout: "us", "gb", "de", "fr", "es", "it", "se", "br"… plus an
    # optional variant ("dvorak", "colemak", "intl", "nodeadkeys"). It applies
    # everywhere you type: the desktop, the login screen and, on an encrypted
    # disk, the password prompt at start-up.
    keyboardLayout = "us";
    keyboardVariant = "";
    # Language and formats (dates, numbers, paper size): "en_US.UTF-8",
    # "en_GB.UTF-8", "de_DE.UTF-8"…
    locale = "en_US.UTF-8";
    # Graphics: "amd", "intel", "nvidia" (adds NVIDIA's own driver) or "none".
    gpu = "amd";
    # NVIDIA only: the open kernel module (RTX 20-series / GTX 16-series and
    # newer). false = the older closed one, for GTX 10-series and before.
    nvidiaOpen = true;
    # Run AI models on this machine's GPU (the `assistant` module). Default:
    # on for a desktop with a GPU; laptops use an API key instead.
    # localAI = true;

    # ── Look ──────────────────────────────────────────────────────────────────
    # Terminal opacity, 0.0–1.0 (1.0 = fully opaque). The compositor (picom)
    # applies it; a FULLSCREEN terminal (Super+f) is always forced fully opaque.
    termOpacity = "0.72";
    liveSnow = true;           # falling snow over the wallpaper (`snow off` for now)
    # Night light: warmer screen colours after sunset (`nightlight` toggles it).
    # Sunset is worked out from where you are — rough is fine (city level).
    nightLight = true;
    location = { latitude = 40.7; longitude = -74.0; };
    # The key that takes screenshots (with Shift: the screenshot menu). Print
    # always does; set this when your laptop's screenshot key sends something
    # else. Find out with: nix-shell -p xorg.xev --run "xev -event keyboard"
    # (press it; the name after "keysym 0x…," is what goes here, e.g. "F10").
    screenshotKey = "Print";

    # ── Modules ───────────────────────────────────────────────────────────────
    # Which are on comes from the marker files in mods/ (nix²'s defaults),
    # and here you override any of them: modules.gaming = false;
    modules = { };

    # ── Updates ───────────────────────────────────────────────────────────────
    # `nixup` pulls this repo (cloned at /etc/nixos) and rebuilds — no re-cloning.
    # autoUpdate = true adds a weekly timer that pulls + rebuilds on its own.
    autoUpdate = false;
    # Apps built from git (settings.gitApps, and the optional neb, backoffice,
    # intraweb) check for new commits daily and update when one builds.
    autoUpdateMine = true;
    # New NixOS packages (the channel) are fetched and pre-built in the background
    # at idle priority on this schedule, so `rebuild` stays quick: "weekly",
    # "daily", or "never" (then only `rebuild --upgrade` moves you forward).
    channelUpdates = "weekly";

    # ── Speed & space ─────────────────────────────────────────────────────────
    # Kernel: "zen" (tuned for desktop snappiness), "latest", or "lts".
    kernel = "zen";
    # Apps to leave out of EVERY module, by name (`debloat list` shows them;
    # `debloat remove <name>` adds to this for you).
    removePackages = [ ];
    # Coding toolkit (devtools module): the lean set is always in. true adds the
    # big apps too — VSCodium, Helix, Ghidra, Octave, gnuplot, OBS (~3 GB).
    devExtras = false;
    # Share builds between your machines (`devtools` module): one machine
    # builds, the others download the result over your home network instead of
    # compiling it again. On the machine that builds: shareBuilds.serve = true;
    # then `nix2-setup share` prints the two lines to put on the others.
    shareBuilds = { serve = false; from = ""; key = ""; };

    # Folders made in your home on boot (never deleted). Nested is fine: "projects/work".
    homeFolders = [ "projects" "notes" "junk" ];

    # ── The menu (Super+Alt+Space) ─────────────────────────────────────────────
    # Every module adds its own entries. Here you can reorder the categories,
    # hide entries by label, and add your own. (Or edit ~/.config/nixmenu/menu —
    # same idea, no rebuild; its header explains the format.)
    menu = {
      order = [ ];             # e.g. [ "Self-hosted" "System" ] — listed ones go first
      hide = [ ];              # e.g. [ "Toggle live snow" ]
      extra = {
        # "My stuff" = [
        #   { label = "Notes";        run = "nvim ~/notes"; mode = "tty"; }
        #   { label = "Home server";  run = "http://192.168.1.10:9000"; mode = "url"; }
        #   { label = "Disk usage";   run = "df -h"; mode = "term"; }
        # ];
      };
    };
    # Web apps you run elsewhere, added to the menu's Self-hosted section
    # (this machine's own are added by their modules, and running Docker
    # containers show up by themselves).
    selfhosted = {
      # "Jellyfin" = "http://192.168.1.10:8096";
    };

    # ── Apps from any git repo (`platform` module) ─────────────────────────────
    # name = { repo = "owner/repo"; type = "…"; } — or url = "https://any.git/server/repo"
    # for GitLab/Codeberg/self-hosted. update-mine keeps each on its newest
    # commit (`rebuild` runs it first, plus a daily timer) and only switches to a
    # commit that builds. Types: rust · go · node · python · make · script ·
    # docker (runs the repo's compose file). Optional: branch, bin (command
    # name), url (adds it to Self-hosted), service = true (keep it running),
    # args, pythonDeps / buildInputs / nativeBuildInputs (nixpkgs names),
    # subPackages (go), files (script), compose (docker), enable = false.
    # Point a built-in at your fork the same way: neb = { repo = "you/neb"; };
    gitApps = {
      # tldr-pages = { repo = "tldr-pages/tlrc"; type = "rust"; bin = "tldr"; };
      # uptime     = { repo = "louislam/uptime-kuma"; type = "docker"; url = "http://127.0.0.1:3001"; };
    };

    # ── Boot ──────────────────────────────────────────────────────────────────
    # espMountPoint must match hardware-configuration.nix (checked at build).
    espMountPoint = "/boot";
    useGrub = true;            # GRUB = themeable; false = systemd-boot

    # ── Backups (`backups` module): restic to an external drive ────────────────
    # The restic repository on your backup drive. Default: a drive labelled
    # BACKUP, /run/media/<username>/BACKUP/restic. Backups run only while it's
    # mounted — unplugged, you get a reminder, not a failure.
    # backupRepo = "/run/media/ada/BACKUP/restic";

    # ── 3D printers (`printing` module): Moonraker URLs to watch ───────────────
    # A desktop notification when a print finishes or fails. Empty = none.
    #   e.g. [ "http://ender.local:7125" "http://voron.local:7125" ]
    printers = [ ];

    # ── Two machines (`sync` module) ───────────────────────────────────────────
    # Syncthing device IDs, filled in after the first boot of each machine
    # (run `syncthing` once, open http://127.0.0.1:8384, Actions → Show ID).
    # Until both are set, pair by hand in the web UI.
    syncIds = { desktop = ""; laptop = ""; };
  };

  localFile = ./settings.local.nix;
  hasLocal = builtins.pathExists localFile;
  local = if hasLocal then import localFile else { };

  # Recursive merge: attribute sets merge key by key; anything else replaces.
  merge = a: b: a // builtins.mapAttrs
    (k: v: if builtins.isAttrs v && builtins.isAttrs (a.${k} or null) then merge a.${k} v else v) b;
in
merge defaults local // { inherit hasLocal; }
