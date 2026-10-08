# AI tooling: Grok Bot (xAI/Cursor desktop agent), grok CLI, Claude Code.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    grok-bot        # desktop agent → `grok-bot`
    grok-build      # xAI's official CLI → `grok`
    claude-code
  ];
}
