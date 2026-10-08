# The parts-inventory web app. `backoffice` starts it at http://localhost:8080.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.backoffice ];
}
