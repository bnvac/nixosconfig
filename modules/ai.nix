# AI dev tooling. (Neb, the assistant itself, is the `assistant` module.)
{ pkgs, ... }:
{
  my.packages = [ pkgs.claude-code ];
}
