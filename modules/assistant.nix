# Jarvis foundation — a local AI stack that runs offline and keeps data local.
#
#   ollama       local LLM server (the brain)         http://127.0.0.1:11434
#   open-webui   ChatGPT-style web UI over ollama     http://127.0.0.1:8088
#   whisper-cpp  speech-to-text  (the "ears")
#   piper-tts    text-to-speech  (the "voice")
#   uv + python  for building the agent itself
#
# When your bot has a repo, package it in pkgs/default.nix (copy the backoffice
# block) and add it to the ai module. It can read ~/SYSTEM.md for live context.
{ config, pkgs, lib, ... }:
{
  services.ollama = {
    enable = true;
    # acceleration = "cuda";   # NVIDIA. use "rocm" for AMD. leave unset = CPU.
    # pull a model once installed:  ollama pull llama3.1   (or qwen2.5, mistral…)
  };

  services.open-webui = {
    enable = true;
    port = 8088;                       # 8080 is taken by backoffice
    openFirewall = false;              # localhost only
    environment = {
      OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
      WEBUI_AUTH = "False";            # single-user local box; drop for multi-user
    };
  };

  environment.systemPackages = with pkgs; [
    whisper-cpp        # STT  → `whisper-cpp`
    piper-tts          # TTS  → `piper`
    uv python3         # agent dev
  ];
}
