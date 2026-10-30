# Platform: run software from anywhere.
#   Docker      containers + `docker compose` (lazydocker for a TUI)
#   Flatpak     the Flathub app store, system-wide
#   AppImage    double-click or ./run any .AppImage
#   Distrobox   another distro's packages in a box (e.g. an Arch/Ubuntu shell)
#   gitApps     apps built straight from any git repo — see settings.nix
#
# All of it stays out of the way until used: Docker starts on the first
# `docker …` (socket activation, nothing at boot), Flatpak only downloads the
# runtimes an app you install needs, and Docker cleans up unused images weekly.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  apps = lib.filterAttrs (_: a: a.enable or true) (s.gitApps or { });
  tracked = import ../pkgs/tracked.nix;
  built = pkgs.gitApps;                     # only apps that have a pinned commit
  isDocker = a: (a.type or "script") == "docker";
  dockerApps = lib.filterAttrs (n: a: isDocker a && built ? ${n}) apps;
  binApps = lib.filterAttrs (n: a: !isDocker a && built ? ${n}) apps;
  serviceApps = lib.filterAttrs (_: a: a.service or false) binApps;
  waiting = lib.attrNames (lib.filterAttrs (n: _: !(built ? ${n}) && !(tracked.${n}.builtin or false)) apps);
  docker = config.virtualisation.docker.package;
in
{
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;                   # socket-activated
    autoPrune = { enable = true; dates = "weekly"; flags = [ "--all" "--filter" "until=168h" ]; };
    daemon.settings = { log-driver = "local"; log-opts = { max-size = "10m"; max-file = "3"; }; };
  };
  users.users.${s.username}.extraGroups = [ "docker" ];

  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };
  # Flathub, from a copy of its repo file kept in this config (just its URL and
  # signing key), so adding it needs no network at boot.
  system.activationScripts.flathub = ''
    ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub ${../pkgs/flathub.flatpakrepo} >/dev/null 2>&1 || true
  '';

  programs.appimage = { enable = true; binfmt = true; };

  # ── gitApps ──────────────────────────────────────────────────────────────
  warnings = map (n: "gitApps.${n}: no pinned commit yet — `rebuild` (or `sudo update-mine`) fetches it first") waiting;

  # type = "docker": copy the repo to /var/lib/gitapps/<name> and run its
  # compose file. Files the containers create there (data, .env) are kept
  # across updates; a new commit restarts it on the next switch.
  systemd.services = lib.mapAttrs' (n: a: lib.nameValuePair "gitapp-${n}" {
    description = "${n} (docker compose, from ${tracked.${n}.url})";
    wantedBy = [ "multi-user.target" ];
    requires = [ "docker.service" ];
    after = [ "docker.service" "network.target" ];
    path = [ docker pkgs.coreutils ];
    restartTriggers = [ built.${n} ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "gitapps/${n}";
      WorkingDirectory = "/var/lib/gitapps/${n}";
      ExecStop = "${docker}/bin/docker compose -p ${n} down";
    };
    script = ''
      cp -rT --no-preserve=mode,ownership ${built.${n}} /var/lib/gitapps/${n}
      docker compose -p ${n} ${lib.optionalString (a ? compose) "-f ${a.compose}"} up -d --build --remove-orphans
    '';
  }) dockerApps;

  # service = true: keep the app running as you (restarts if it crashes).
  systemd.user.services = lib.mapAttrs' (n: a: lib.nameValuePair "gitapp-${n}" {
    description = "${n} (from ${tracked.${n}.url})";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${built.${n}}/bin/${a.bin or n} ${a.args or ""}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  }) serviceApps;

  my.selfhosted = lib.mapAttrs (_: a: a.url) (lib.filterAttrs (n: a: a ? url && built ? ${n}) apps);

  my.menu."Containers & apps" = [
    { label = "Docker dashboard (lazydocker)"; run = "lazydocker"; mode = "tty"; }
    { label = "Running containers"; run = "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'"; mode = "term"; }
    { label = "Flathub: browse apps"; run = "https://flathub.org"; mode = "url"; }
    { label = "Flatpak: installed apps"; run = "flatpak list --app"; mode = "term"; }
    { label = "Flatpak: update all"; run = "flatpak update -y"; mode = "term"; }
    { label = "Distrobox: my boxes"; run = "distrobox list"; mode = "term"; }
    { label = "Git apps: what's new upstream"; run = "update-mine --status"; mode = "term"; }
  ];

  my.packages = (with pkgs; [ lazydocker dive distrobox ]) ++ lib.attrValues (lib.mapAttrs (n: _: built.${n}) binApps);
}
