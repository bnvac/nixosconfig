# Jarvis foundation — a local AI stack that runs offline and keeps data local.
#
#   ollama       local LLM server (the brain)         http://127.0.0.1:11434
#   open-webui   ChatGPT-style web UI over ollama     http://127.0.0.1:8088
#   jarvis       push-to-talk voice assistant         Super+Shift+` (backtick)
#   whisper-cpp  speech-to-text (ears)  ·  piper-tts   text-to-speech (voice)
#   uv + python  for building the agent itself
#
# When your bot has a repo, package it in pkgs/default.nix (copy backoffice) and
# add it to the ai module. It can read ~/SYSTEM.md for live machine context.
{ config, pkgs, lib, ... }:
let
  # Push-to-talk: press the keybind, speak, it stops on silence, transcribes,
  # asks the local model (with ~/SYSTEM.md as context), and speaks the reply.
  # Speech + voice models download themselves to ~/.local/share/jarvis on first
  # run. Change the model with:  JARVIS_MODEL=qwen2.5 jarvis
  jarvis = pkgs.writeShellScriptBin "jarvis" ''
    export PATH=${lib.makeBinPath (with pkgs; [
      sox whisper-cpp piper-tts curl jq libnotify coreutils gnused gnugrep
    ])}:$PATH
    set -eu
    dir="''${XDG_DATA_HOME:-$HOME/.local/share}/jarvis"; mkdir -p "$dir"
    wm="$dir/ggml-base.en.bin"; pm="$dir/voice.onnx"
    model="''${JARVIS_MODEL:-llama3.1}"

    [ -f "$wm" ] || { notify-send "Jarvis" "Downloading speech model…"
      whisper-cpp-download-ggml-model base.en "$dir" >/dev/null 2>&1 || true; }
    [ -f "$pm" ] || { notify-send "Jarvis" "Downloading voice…"
      base=https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium
      curl -fsSL "$base/en_US-lessac-medium.onnx"      -o "$pm"
      curl -fsSL "$base/en_US-lessac-medium.onnx.json" -o "$pm.json"; }

    notify-send "🎙 Jarvis" "Listening… (stops when you pause)"
    rec -q -r 16000 -c 1 "$dir/in.wav" silence 1 0.1 3% 1 2.0 3% trim 0 15 2>/dev/null
    text=$(whisper-cli -m "$wm" -f "$dir/in.wav" -nt -np 2>/dev/null | tr '\n' ' ' | sed 's/^ *//;s/ *$//')
    [ -n "$text" ] || { notify-send "Jarvis" "Didn't catch that."; exit 0; }
    notify-send "🗣 You said" "$text"

    sys="You are Jarvis, $USER's terminal assistant on a NixOS machine. Be concise and spoken-friendly."
    [ -f "$HOME/SYSTEM.md" ] && sys="$sys Machine notes:
$(cat "$HOME/SYSTEM.md")"
    reply=$(curl -fsS http://127.0.0.1:11434/api/generate \
      -d "$(jq -n --arg m "$model" --arg p "$text" --arg s "$sys" \
            '{model:$m,prompt:$p,system:$s,stream:false}')" | jq -r '.response')
    [ -n "$reply" ] || { notify-send "Jarvis" "No reply (is a model pulled? 'ollama pull $model')"; exit 0; }
    notify-send "🤖 Jarvis" "$reply"
    printf '%s' "$reply" | piper --model "$pm" --output_file "$dir/out.wav" 2>/dev/null
    play -q "$dir/out.wav" 2>/dev/null
  '';
in
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;   # AMD GPU build (26.05 picks accel by package)
    # RX 6750 XT is gfx1031 (Navi 22), which ROCm doesn't list. Tell it to act
    # as the supported gfx1030 — the standard, reliable fix for this card.
    rocmOverrideGfx = "10.3.0";
  };

  services.open-webui = {
    enable = true;
    port = 8088;                       # 8080 is backoffice
    openFirewall = false;
    environment = {
      OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
      WEBUI_AUTH = "False";
    };
  };

  environment.systemPackages = with pkgs; [
    jarvis
    whisper-cpp piper-tts sox alsa-utils   # voice I/O
    uv python3                             # agent dev
  ];
}
