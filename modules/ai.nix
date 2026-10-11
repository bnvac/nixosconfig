# AI tooling: Claude Code, xAI's grok CLI, and room for your own assistant.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    claude-code
    grok-build      # xAI's official coding CLI → `grok`  (not the Grok Bot app)
    # When your Jarvis bot has a repo, package it in pkgs/default.nix like
    # backoffice and add it here. The self-generated /etc/jarvis/SYSTEM.md
    # (see core.nix) is written for exactly that bot to read.
  ];
}
