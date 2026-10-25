# Neb — local voice assistant — plus the AI stack it talks to.
#
#   neb serve    HTTP endpoint + dashboard   http://127.0.0.1:7000   (user service)
#   neb-voice    Super+Alt+n: listen → answer, as a small corner notification
#   neb-space    Super+Alt+Shift+n: his workspace (tag 9) + his terminal
#   neb tui / chat / ask / tools             terminal faces of the same agent
#   desk …       the desktop actions he's allowed (see `commands` below)
#
# BRAIN depends on settings.nix `device`:
#   desktop → local Ollama on the RX 6750 XT (free, offline), Vulkan backend
#   laptop  → an API brain (set a key in the dashboard, or ANTHROPIC_API_KEY)
#
# Dashboard: http://127.0.0.1:7000 — switch brains, set API keys (write-only),
# edit the command allowlist, see tools/memory. Open it with: chromium http://127.0.0.1:7000
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  isDesktop = s.device == "desktop";
  home = "/home/${s.username}";

  # tools Neb's server shells out to (mod, nixos-rebuild, sudo, systemctl, df…)
  # plus the voice tools the hotkey uses.
  nebPath = lib.makeBinPath (with pkgs; [
    sox whisper-cpp piper-tts libnotify xdotool coreutils curl jq
  ]);

  # What Neb may run (his run_command allowlist; extra words only where
  # args = true, and never flags or shell syntax). His stock 8, plus `desk`
  # for the desktop. Anything that types, presses keys or closes a window
  # needs your yes first.
  nebCommands =
    map (cmd: { inherit cmd; }) [ "uptime" "df -h" "free -h" "nixos-version" "mod list"
                                  "systemctl --failed --no-pager" ]
    ++ map (cmd: { inherit cmd; args = true; }) [ "systemctl status --no-pager"
                                                  "systemctl --user status --no-pager" ]
    ++ map (cmd: { inherit cmd; }) [ "desk apps" "desk windows" "desk workspace" "desk screenshot" "desk lock" ]
    ++ map (cmd: { inherit cmd; args = true; }) [ "desk open" "desk web" "desk search" "desk focus"
                                                  "desk volume" "desk media" "desk brightness" "desk notify" ]
    ++ map (cmd: { inherit cmd; args = true; confirm = true; }) [ "desk type" "desk key" "desk close" ];

  # Seed ~/.local/share/neb/settings.json on first run only (Neb owns it after).
  # Picks the brain by device and teaches the voice loop about st + X11 focus.
  nebSeed = pkgs.writeText "neb-settings.json" (builtins.toJSON {
    provider = if isDesktop then "ollama" else "anthropic";
    # qwen3.5:9b: strong tool use, fits the 12 GB card. Thinking off so voice
    # replies come straight back; 8k context holds his tools + notes.
    providers.ollama = { model = "qwen3.5:9b"; num_ctx = 8192; think = false; };
    commands = nebCommands;
    voice = {
      record = [ "rec" "-q" "-c" "1" "-r" "16000" "-b" "16" "{wav}"
                 "silence" "1" "0.1" "2%" "1" "1.5" "2%" "trim" "0" "30" ];
      stt = [ "whisper-cli" "-m" "~/.local/share/jarvis/ggml-base.en.bin" "-nt" "-np" "-f" "{wav}" ];
      tts = [ "piper" "--model" "~/.local/share/jarvis/voice.onnx" "--output_file" "{out}" ];
      play = [ "play" "-q" "{out}" ];
    };
    ui = {
      # st is the user's terminal (not in Neb's built-in list), dwm/X11 focus
      # is via xdotool (Neb only auto-focuses on Wayland).
      terminal = [ "st" "-n" "neb" "-t" "neb" "-e" "{cmd}" ];
      focus = [ "xdotool" "search" "--name" "^neb$" "windowactivate" ];
    };
  });
in
{
  # ── local model stack — desktop only (the laptop uses an API brain) ────────
  # Vulkan, not ROCm: the RX 6750 XT (gfx1031) isn't a supported ROCm target —
  # the override hack is fragile and Ollama silently falls back to the CPU,
  # which is what made replies crawl. Vulkan runs on the stock Mesa driver.
  services.ollama = lib.mkIf isDesktop {
    enable = true;
    package = pkgs.ollama-vulkan;
    environmentVariables.OLLAMA_VULKAN = "1";
  };
  services.open-webui = lib.mkIf isDesktop {
    enable = true; port = 8088; openFirewall = false;
    environment = { OLLAMA_API_BASE_URL = "http://127.0.0.1:11434"; WEBUI_AUTH = "False"; };
  };

  # ── voice models fetched once to ~/.local/share/jarvis (used by Neb) ───────
  systemd.user.services.neb-voice-setup = {
    description = "Fetch Neb's whisper + piper voice models";
    wantedBy = [ "default.target" ];
    serviceConfig.Type = "oneshot";
    path = with pkgs; [ whisper-cpp curl coreutils ];
    script = ''
      d="$HOME/.local/share/jarvis"; mkdir -p "$d"
      [ -f "$d/ggml-base.en.bin" ] || whisper-cpp-download-ggml-model base.en "$d" || true
      base=https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium
      [ -f "$d/voice.onnx" ] || curl -fsSL "$base/en_US-lessac-medium.onnx" -o "$d/voice.onnx" || true
      [ -f "$d/voice.onnx.json" ] || curl -fsSL "$base/en_US-lessac-medium.onnx.json" -o "$d/voice.onnx.json" || true
    '';
  };

  # ── Neb server (the dashboard + /ask endpoint) as a user service ───────────
  # Bound to the desktop session (not plain login) so he gets DISPLAY and can
  # act on the desktop; NixOS's X session wrapper starts graphical-session.
  systemd.user.services.neb = {
    description = "Neb assistant server";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "neb-voice-setup.service" "graphical-session.target" ];
    path = [ "/run/wrappers/bin" "/run/current-system/sw/bin" ];  # sudo, mod, systemctl…
    environment.PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin:${nebPath}";
    preStart = ''
      mkdir -p "$HOME/.local/share/neb"
      [ -f "$HOME/.local/share/neb/settings.json" ] || {
        install -m600 ${nebSeed} "$HOME/.local/share/neb/settings.json"; }
    '';
    serviceConfig = {
      ExecStart = "${pkgs.neb}/bin/neb serve --port 7000";
      Restart = "on-failure"; RestartSec = 3;
    };
  };

  environment.systemPackages = with pkgs; [
    neb                                   # neb / neb tui / neb ask / neb chat
    neb-voice neb-space desk              # corner-notification voice, his workspace, desktop actions
    whisper-cpp piper-tts sox alsa-utils  # voice I/O
    uv                                    # agent dev (python3 is in core)
  ];
}
