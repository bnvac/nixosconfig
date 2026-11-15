# homelab — run this desktop as a 24/7 home server, reachable over Tailscale.
#
#   Pi-hole      DNS ad-blocking for your LAN (port 53) + its admin page :8053
#   Gitea        your own git server                       :3002  (ssh :2222)
#   Nextcloud    calendar, contacts, files                 :8091
#   FreshRSS     RSS reader (works with phone RSS apps)    :8090
#   Transmission torrents, web UI                          :9091
#   SearXNG      private metasearch                        :8888
#
# Each one is a switch in settings.local.nix (all on by default once the module
# is on):  homelab.git = false;
#
# Turn it on:  mod on homelab   then   homelab setup   (prints what to do next).
#
# Who can reach what: the web pages are open ONLY on the Tailscale interface
# (your devices, from anywhere), never to the internet. Set homelab.lan = true
# to also open them to your home network. Pi-hole's DNS port is the exception:
# it's open on the LAN, because that's what lets the router point at it.
#
# 24/7: sleep and suspend are switched off while this module is on, every
# service starts at boot with nobody logged in, and they restart if they crash.
# Also set your BIOS to "Restore on AC power loss: Power On" so a power cut
# doesn't leave it off.
#
# Passwords are made on this machine the first time (never in git) and kept in
# /var/lib/homelab/secrets. `homelab passwords` shows them.
#
# Dashboard: with homelab.benos.url set, the BenOS agent reports these services
# (up/down, uptime) to your BenOS Lab page and registers them there by itself.
{ config, pkgs, lib, ... }:
let
  s = import ../settings.nix;
  h = s.homelab or { };
  on = name: h.${name} or true;
  # The name your other devices use to reach this machine: its Tailscale
  # MagicDNS name by default (e.g. "nix2" or "nix2.tail1234.ts.net").
  addr = h.address or s.hostName;
  lan = h.lan or false;
  dataDir = h.dataDir or "/srv";
  secrets = "/var/lib/homelab/secrets";
  benosUrl = h.benos.url or "";

  ports = {
    pihole = 8053; git = 3002; gitSsh = 2222; cloud = 8091;
    rss = 8090; torrent = 9091; search = 8888;
  };
  url = p: "http://${addr}:${toString p}";

  # Everything this module serves: name, what you open, what the agent probes.
  # Probes go to 127.0.0.1 on this machine, so they test the service itself.
  services = lib.filter (x: x.enable) [
    { key = "pihole"; enable = on "pihole"; name = "Pi-hole"; port = ports.pihole;
      url = "${url ports.pihole}/admin/"; check = "tcp://127.0.0.1:53"; }
    { key = "gitea"; enable = on "git"; name = "Gitea"; port = ports.git;
      url = url ports.git; check = "http://127.0.0.1:${toString ports.git}/api/healthz"; }
    { key = "nextcloud"; enable = on "cloud"; name = "Nextcloud"; port = ports.cloud;
      url = url ports.cloud; check = "http://127.0.0.1:${toString ports.cloud}/status.php"; }
    { key = "freshrss"; enable = on "rss"; name = "FreshRSS"; port = ports.rss;
      url = url ports.rss; check = "http://127.0.0.1:${toString ports.rss}/"; }
    # The web UI asks for a password (401), so probe the port instead.
    { key = "transmission"; enable = on "torrent"; name = "Transmission"; port = ports.torrent;
      url = url ports.torrent; check = "tcp://127.0.0.1:${toString ports.torrent}"; }
    { key = "searxng"; enable = on "search"; name = "SearXNG"; port = ports.search;
      url = url ports.search; check = "http://127.0.0.1:${toString ports.search}/healthz"; }
  ];
  webPorts = map (x: x.port) services ++ lib.optional (on "git") ports.gitSsh;

  # What the BenOS agent registers on your Lab page. Add your own in settings:
  #   homelab.dashboard = [ { key = "jellyfin"; name = "Jellyfin"; url = "http://nix2:8096"; check = "http://127.0.0.1:8096/health"; } ];
  dashboard = map (x: { inherit (x) key name url check; group = "Homelab"; }) services
    ++ map (x: { group = "Homelab"; } // x) (h.dashboard or [ ]);
  servicesJson = pkgs.writeText "benos-services.json" (builtins.toJSON dashboard);

  # First boot: make every password this module needs, once. Never overwrites.
  makeSecrets = pkgs.writeShellScript "homelab-secrets" ''
    set -eu
    umask 077
    mkdir -p ${secrets}
    chmod 0711 ${secrets}                   # services may open their own file, not list the folder
    gen() { ${pkgs.openssl}/bin/openssl rand -base64 24 | tr -d '/+=' | head -c 24; }
    put() { [ -s "${secrets}/$1" ] || printf '%s' "$2" > "${secrets}/$1"; }
    put nextcloud-admin "$(gen)"
    put freshrss "$(gen)"
    put searx.env "SEARX_SECRET_KEY=$(gen)$(gen)"
    put transmission-password "$(gen)"
    # Transmission wants its credentials as JSON merged into settings.json.
    printf '{"rpc-username":"%s","rpc-password":"%s"}' "${s.username}" "$(cat ${secrets}/transmission-password)" \
      > ${secrets}/transmission.json
    ${lib.optionalString (on "rss") "chown freshrss ${secrets}/freshrss"}
  '';

  homelab = pkgs.writeShellApplication {
    name = "homelab";
    runtimeInputs = with pkgs; [ coreutils systemd curl gnugrep ];
    text = ''
      units=(${lib.concatStringsSep " " (
        lib.optional (on "pihole") "pihole-ftl"
        ++ lib.optional (on "git") "gitea"
        ++ lib.optionals (on "cloud") [ "phpfpm-nextcloud" "nginx" ]
        ++ lib.optional (on "rss") "phpfpm-freshrss"
        ++ lib.optional (on "torrent") "transmission"
        ++ lib.optional (on "search") "searx"
        ++ [ "tailscaled" ]
        ++ lib.optional (benosUrl != "") "benos-agent"
      )})
      show() { printf '  %-14s %s\n' "$1" "$2"; }
      case "''${1:-status}" in
        status)
          echo "Services:"
          for u in "''${units[@]}"; do show "$u" "$(systemctl is-active "$u" 2>/dev/null || true)"; done
          echo; echo "Open from any device on your tailnet:"
          ${lib.concatMapStrings (x: "show ${lib.escapeShellArg x.name} ${lib.escapeShellArg x.url}\n") services}
          ;;
        passwords)
          sudo=/run/wrappers/bin/sudo
          echo "Usernames are '${s.username}' unless noted."
          ${lib.optionalString (on "cloud") ''show Nextcloud "admin / $($sudo cat ${secrets}/nextcloud-admin)"''}
          ${lib.optionalString (on "rss") ''show FreshRSS "$($sudo cat ${secrets}/freshrss)"''}
          ${lib.optionalString (on "torrent") ''show Transmission "$($sudo cat ${secrets}/transmission-password)"''}
          ${lib.optionalString (on "pihole") ''show Pi-hole "no password: only your tailnet can reach it"''}
          ${lib.optionalString (on "git") ''show Gitea "make your account: homelab git-admin"''}
          ;;
        git-admin)
          user="''${2:-${s.username}}"
          email="''${3:-${s.username}@localhost}"
          pw=$(${pkgs.openssl}/bin/openssl rand -base64 18)
          /run/wrappers/bin/sudo -u gitea ${pkgs.gitea}/bin/gitea admin user create \
            --config ${config.services.gitea.customDir}/conf/app.ini \
            --username "$user" --email "$email" --password "$pw" --admin --must-change-password
          echo "Gitea admin '$user' created. First password: $pw (you'll be asked to change it)."
          ;;
        setup)
          cat <<EOF
      1. Join Tailscale (once):   sudo tailscale up
      2. Passwords:               homelab passwords
      3. Gitea account:           homelab git-admin
      4. Pi-hole for the house:   set your router's DNS server to this machine's LAN address.
         Pi-hole on your phone, anywhere: Tailscale admin → DNS → add this machine's
         100.x address as a nameserver and turn on "Override local DNS".
      5. Dashboard:               ${if benosUrl == "" then "set homelab.benos.url in settings.local.nix, then see step 6"
                                   else "BenOS Lab → Add a server (address: ${addr}) → copy the agent token, then:"}
      6.   echo 'BENOS_AGENT_TOKEN=benos_agent_...' | sudo tee /etc/benos-agent.env >/dev/null
           sudo chmod 600 /etc/benos-agent.env && sudo systemctl restart benos-agent
         Your services then appear on the Lab page by themselves.
      EOF
          ;;
        *) echo "usage: homelab [status|passwords|git-admin [name] [email]|setup]"; exit 2 ;;
      esac
    '';
  };
in
{
  assertions = [{
    assertion = s.device == "desktop";
    message = "The homelab module keeps the machine awake 24/7; it's meant for a desktop (settings.device = \"desktop\").";
  }];

  my.packages = [ homelab ];
  my.menu."Homelab" = [
    { label = "What's running + links"; run = "homelab status"; mode = "term"; }
    { label = "Passwords"; run = "homelab passwords"; mode = "term"; }
    { label = "Setup steps"; run = "homelab setup"; mode = "term"; }
  ];
  my.selfhosted = lib.listToAttrs (map (x: lib.nameValuePair x.name "http://127.0.0.1:${toString x.port}") services);

  # ── 24/7 ───────────────────────────────────────────────────────────────────
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no"; AllowHibernation = "no";
    AllowHybridSleep = "no"; AllowSuspendThenHibernate = "no";
  };

  # ── Tailscale: the way in ─────────────────────────────────────────────────
  services.tailscale = { enable = true; useRoutingFeatures = "server"; };
  networking.firewall.checkReversePath = lib.mkDefault "loose";
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = webPorts;
  networking.firewall.allowedTCPPorts = lib.optionals lan webPorts ++ lib.optional (on "pihole") 53;
  networking.firewall.allowedUDPPorts = lib.optional (on "pihole") 53;

  systemd.services.homelab-secrets = {
    description = "Make homelab passwords (first boot only)";
    wantedBy = [ "multi-user.target" ];
    before = [ "nextcloud-setup.service" "freshrss-config.service" "transmission.service" "searx-init.service" "searx.service" ];
    requiredBy = lib.optional (on "cloud") "nextcloud-setup.service"
      ++ lib.optional (on "rss") "freshrss-config.service"
      ++ lib.optional (on "torrent") "transmission.service"
      ++ lib.optional (on "search") "searx.service";
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = makeSecrets; };
  };

  # ── Pi-hole ───────────────────────────────────────────────────────────────
  services.pihole-ftl = lib.mkIf (on "pihole") {
    enable = true;
    queryLogDeleter.enable = true;          # keeps 90 days of queries, not forever
    lists = [{
      url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
      description = "Steven Black's unified list (ads + malware)";
    }];
    settings.dns = {
      # ALL: answer the LAN *and* the tailnet (LOCAL would ignore 100.x clients).
      listeningMode = "ALL";
      upstreams = h.dnsUpstreams or [ "9.9.9.9" "149.112.112.112" ];   # Quad9
    };
  };
  services.pihole-web = lib.mkIf (on "pihole") {
    enable = true;
    hostName = addr;
    ports = [ ports.pihole ];
  };

  # ── Gitea ─────────────────────────────────────────────────────────────────
  services.gitea = lib.mkIf (on "git") {
    enable = true;
    settings = {
      server = {
        HTTP_ADDR = "0.0.0.0"; HTTP_PORT = ports.git;
        DOMAIN = addr; ROOT_URL = "${url ports.git}/";
        START_SSH_SERVER = true; SSH_PORT = ports.gitSsh; SSH_LISTEN_PORT = ports.gitSsh;
      };
      service.DISABLE_REGISTRATION = true;  # `homelab git-admin` makes your account
      session.COOKIE_SECURE = false;        # plain http inside the tailnet
    };
  };

  # ── Nextcloud ─────────────────────────────────────────────────────────────
  services.nextcloud = lib.mkIf (on "cloud") {
    enable = true;
    package = pkgs.nextcloud34;
    hostName = addr;
    database.createLocally = true;
    configureRedis = true;
    maxUploadSize = "4G";
    config = { dbtype = "pgsql"; adminuser = "admin"; adminpassFile = "${secrets}/nextcloud-admin"; };
    settings = {
      trusted_domains = [ "127.0.0.1" "localhost" s.hostName ];
      overwriteprotocol = "http";
      default_phone_region = h.phoneRegion or "US";
    };
  };
  services.nginx.virtualHosts.${addr} = lib.mkIf (on "cloud") {
    listen = [{ addr = "0.0.0.0"; port = ports.cloud; }];
  };

  # ── FreshRSS ──────────────────────────────────────────────────────────────
  services.freshrss = lib.mkIf (on "rss") {
    enable = true;
    defaultUser = s.username;
    passwordFile = "${secrets}/freshrss";
    baseUrl = url ports.rss;
    api.enable = true;                      # phone apps (Reeder, NetNewsWire, ReadYou…)
  };
  services.nginx.virtualHosts.freshrss = lib.mkIf (on "rss") {
    listen = [{ addr = "0.0.0.0"; port = ports.rss; }];
  };

  # ── Transmission ──────────────────────────────────────────────────────────
  # NOTE: this torrents from your home IP. See the module's notes / the menu.
  services.transmission = lib.mkIf (on "torrent") {
    enable = true;
    package = pkgs.transmission_4;
    credentialsFile = "${secrets}/transmission.json";
    downloadDirPermissions = "775";
    settings = {
      download-dir = "${dataDir}/torrents";
      incomplete-dir = "${dataDir}/torrents/.incomplete";
      rpc-bind-address = "0.0.0.0";
      rpc-port = ports.torrent;
      rpc-authentication-required = true;
      rpc-whitelist-enabled = true;
      rpc-whitelist = "127.0.0.1,100.*.*.*" + lib.optionalString lan ",192.168.*.*,10.*.*.*";
      rpc-host-whitelist-enabled = false;
      ratio-limit-enabled = true; ratio-limit = 2.0;
    };
  };
  users.users.${s.username}.extraGroups = lib.optional (on "torrent") "transmission";
  systemd.tmpfiles.rules = lib.optional (on "torrent") "d ${dataDir}/torrents 0775 transmission transmission -";

  # ── SearXNG ───────────────────────────────────────────────────────────────
  services.searx = lib.mkIf (on "search") {
    enable = true;
    redisCreateLocally = true;
    environmentFile = "${secrets}/searx.env";
    settings = {
      server = {
        bind_address = "0.0.0.0"; port = ports.search;
        secret_key = "$SEARX_SECRET_KEY";
        base_url = "${url ports.search}/";
        limiter = false;                    # private instance: no bot limiter needed
      };
      search.formats = [ "html" "json" ];   # json lets scripts and BenOS query it
      general.instance_name = "search";
    };
  };

  # ── BenOS agent: reports these to your dashboard's Lab page ───────────────
  # The agent script is fetched from your BenOS itself (so it always matches the
  # server), cached, and the last good copy is used if BenOS is unreachable.
  systemd.services.benos-agent = lib.mkIf (benosUrl != "") {
    description = "BenOS agent (reports homelab health to ${benosUrl})";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "tailscaled.service" ];
    unitConfig.ConditionPathExists = "/etc/benos-agent.env";   # token not set up yet → stay off
    environment = {
      BENOS_URL = benosUrl;
      BENOS_SERVICES_FILE = "${servicesJson}";
      BENOS_DISK_PATH = h.benos.diskPath or "/";
    };
    script = ''
      f="$STATE_DIRECTORY/benos-agent.mjs"
      if ${pkgs.curl}/bin/curl -fsS --max-time 20 "$BENOS_URL/agent/benos-agent.mjs" -o "$f.new"; then
        mv "$f.new" "$f"
      fi
      [ -s "$f" ] || { echo "Couldn't download the agent from $BENOS_URL yet."; exit 1; }
      exec ${pkgs.nodejs_22}/bin/node "$f"
    '';
    serviceConfig = {
      EnvironmentFile = "/etc/benos-agent.env";
      DynamicUser = true;
      StateDirectory = "benos-agent";
      Restart = "always";
      RestartSec = 30;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };
}
