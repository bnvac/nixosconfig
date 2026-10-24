# AI dev tooling. (Neb, the assistant itself, is the `assistant` module.)
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.claude-code ];
}
