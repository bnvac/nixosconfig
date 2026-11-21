# homelab — run this desktop as a 24/7 home server, reachable over Tailscale.
#
#   Pi-hole      DNS ad-blocking for your LAN (port 53) + its admin page :8053
#   Gitea        your own git server                       :3002  (ssh :2222)
#   Nextcloud    calendar, contacts, files                 :8091
#   FreshRSS     RSS reader (works with phone RSS apps)    :8090
#   Transmission torrents, web UI, ONLY through Proton VPN :9091
#   SearXNG      private metasearch                        :8888
#   Minecraft    Crafty control panel (worlds, mods)       :8443  OFF until `homelab minecraft on`
#
# Nice names: Caddy on port 80 gives each one a name — http://git.home.arpa,
# http://cloud.home.arpa … — and Pi-hole answers those names with this
# machine's Tailscale address. http://<this machine>/ is a start page listing
# everything. Ports above keep working too. Full guide: docs/HOMELAB.md.
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
# Torrents + Proton VPN: Transmission runs inside its own network namespace
# whose only way out is a WireGuard tunnel to Proton. If the tunnel is down it
# has no internet at all (a kill switch by construction, not a firewall rule
# that can be forgotten), and DNS goes through Proton too. Needs a Proton
# WireGuard config at /etc/homelab/protonvpn.conf; `homelab setup` says how.
# Every minute a check compares the tunnel's exit IP with your home IP and you
# get a desktop notification whenever the VPN goes up or down; `homelab vpn`,
# `homelab status` and the BenOS Lab tile "Torrent VPN" show it too.
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

  # ── Torrent VPN (Proton WireGuard in a network namespace) ──
  torrent = on "torrent";
  vpnOn = torrent && (h.torrentVpn or true);
  portForward = h.vpnPortForward or true;        # Proton NAT-PMP: lets peers reach you (P2P servers)
  vpnConf = "/etc/homelab/protonvpn.conf";
  ns = "torrentvpn";
  vethHost = "10.200.200.1"; vethNs = "10.200.200.2";
  vpnState = "/run/homelab/vpn";                 # "up <exit ip>" | "down <why>"
  vpnStatusPort = 9092;
  inNs = { NetworkNamespacePath = "/run/netns/${ns}";
           BindReadOnlyPaths = [ "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf" ];
           InaccessiblePaths = [ "-/run/nscd" ]; };   # nscd would resolve names OUTSIDE the tunnel

  ports = {
    pihole = 8053; git = 3002; gitSsh = 2222; cloud = 8091;
    rss = 8090; torrent = 9091; search = 8888; crafty = 8443;
  };
  url = p: "http://${addr}:${toString p}";

  # ── Reverse proxy + names ──
  proxyOn = h.proxy or true;
  domain = h.domain or "home.arpa";            # RFC 8375: reserved for home networks, never on the internet
  names = proxyOn && (on "pihole");            # the names need Pi-hole to answer them
  # What other devices should open: the nice name when there is one, else address:port.
  canon = sub: port: if names then "http://${sub}.${domain}" else url port;

  # ── Minecraft (Crafty Controller in Docker) ──
  mc = h.minecraft or true;                    # installed; the server itself stays OFF until you turn it on
  craftyImage = "registry.gitlab.com/crafty-controller/crafty-4:4.11.0";
  craftyDir = "/var/lib/crafty";
  craftyUnit = "docker-crafty.service";

  # Everything this module serves: name, what you open, what the agent probes.
  # Probes go to 127.0.0.1 on this machine, so they test the service itself.
  # sub = its name under the proxy (git → http://git.home.arpa); direct = address:port.
  services = map (x: x // { url = canon x.sub x.port + (x.path or ""); direct = url x.port + (x.path or ""); })
    (lib.filter (x: x.enable) [
      { key = "pihole"; enable = on "pihole"; name = "Pi-hole"; sub = "pihole"; port = ports.pihole;
        path = "/admin/"; check = "tcp://127.0.0.1:53"; }
      { key = "gitea"; enable = on "git"; name = "Gitea"; sub = "git"; port = ports.git;
        check = "http://127.0.0.1:${toString ports.git}/api/healthz"; }
      { key = "nextcloud"; enable = on "cloud"; name = "Nextcloud"; sub = "cloud"; port = ports.cloud;
        check = "http://127.0.0.1:${toString ports.cloud}/status.php"; }
      { key = "freshrss"; enable = on "rss"; name = "FreshRSS"; sub = "rss"; port = ports.rss;
        check = "http://127.0.0.1:${toString ports.rss}/"; }
      # The web UI asks for a password (401), so probe the port instead.
      { key = "transmission"; enable = torrent; name = "Transmission"; sub = "torrent"; port = ports.torrent;
        path = "/transmission/web/"; check = "tcp://127.0.0.1:${toString ports.torrent}"; }
      { key = "searxng"; enable = on "search"; name = "SearXNG"; sub = "search"; port = ports.search;
        check = "http://127.0.0.1:${toString ports.search}/healthz"; }
    ]);
  # Minecraft's panel is listed and proxied but not health-checked: it's off on purpose most of the time.
  minecraftEntry = { name = "Minecraft (Crafty)"; url = if names then "http://minecraft.${domain}" else "https://${addr}:${toString ports.crafty}";
                     direct = "https://${addr}:${toString ports.crafty}"; };
  everything = map (x: { inherit (x) name url direct; }) services ++ lib.optional mc minecraftEntry;

  # The start page (http://<this machine>/) and the list other desktops read to fill their menus.
  startPage = pkgs.runCommand "homelab-start-page" { } ''
    mkdir -p $out
    cp ${pkgs.writeText "services.json" (builtins.toJSON everything)} $out/services.json
    cat > $out/index.html <<'EOF'
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1"><title>${s.hostName} · homelab</title>
    <style>
      :root{color-scheme:light dark;--bg:#fafafa;--fg:#111;--mut:#666;--card:#fff;--line:#ddd}
      @media (prefers-color-scheme:dark){:root{--bg:#0b0b0c;--fg:#eee;--mut:#999;--card:#151517;--line:#2a2a2e}}
      body{margin:0;font:16px/1.4 system-ui,sans-serif;background:var(--bg);color:var(--fg)}
      main{max-width:640px;margin:0 auto;padding:24px 16px}
      h1{font-size:20px;margin:0 0 4px} p{color:var(--mut);margin:0 0 20px;font-size:14px}
      ul{list-style:none;padding:0;margin:0;display:grid;gap:8px}
      a{display:flex;justify-content:space-between;gap:12px;padding:12px 14px;border:1px solid var(--line);
        border-radius:10px;background:var(--card);color:inherit;text-decoration:none}
      a:hover{border-color:var(--mut)} small{color:var(--mut);overflow-wrap:anywhere;text-align:right}
    </style></head><body><main>
    <h1>${s.hostName}</h1><p>Everything this machine hosts. Only devices on your Tailscale network can open these.</p>
    <ul>
    ${lib.concatMapStrings (x: ''<li><a href="${x.url}">${x.name}<small>${lib.removePrefix "http://" (lib.removePrefix "https://" x.url)}</small></a></li>
    '') everything}</ul></main></body></html>
    EOF
  '';

  webPorts = map (x: x.port) services ++ lib.optional (on "git") ports.gitSsh
    ++ lib.optional proxyOn 80 ++ lib.optionals mc [ ports.crafty 8000 ];

  # What the BenOS agent registers on your Lab page. Add your own in settings:
  #   homelab.dashboard = [ { key = "jellyfin"; name = "Jellyfin"; url = "http://nix2:8096"; check = "http://127.0.0.1:8096/health"; } ];
  dashboard = map (x: { inherit (x) key name url check; group = "Homelab"; }) services
    # Up only while the tunnel works AND exits somewhere other than your home IP.
    ++ lib.optional vpnOn { key = "torrent-vpn"; name = "Torrent VPN"; url = null; group = "Homelab";
                            check = "http://127.0.0.1:${toString vpnStatusPort}/"; }
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
    runtimeInputs = with pkgs; [ coreutils systemd curl gnugrep iproute2 jq libnotify xdg-utils glibc.bin ];
    text = ''
      units=(${lib.concatStringsSep " " (
        lib.optional (on "pihole") "pihole-ftl"
        ++ lib.optional (on "git") "gitea"
        ++ lib.optionals (on "cloud") [ "phpfpm-nextcloud" "nginx" ]
        ++ lib.optional (on "rss") "phpfpm-freshrss"
        ++ lib.optionals vpnOn [ "torrent-netns" ]
        ++ lib.optional torrent "transmission"
        ++ lib.optional (vpnOn && portForward) "torrent-portforward"
        ++ lib.optional (on "search") "searx"
        ++ [ "tailscaled" ]
        ++ lib.optional (benosUrl != "") "benos-agent"
      )})
      show() { printf '  %-14s %s\n' "$1" "$2"; }
      vpn() {
        ${if !torrent then ''echo "Torrents are off."'' else if !vpnOn then ''echo "⚠ Torrent VPN is OFF (homelab.torrentVpn = false): torrents use your home IP."'' else ''
        st=$(cat ${vpnState} 2>/dev/null || echo "down not checked yet")
        case "$st" in
          up*)  echo "✓ Torrent VPN: ONLINE — torrents leave via Proton, exit IP ''${st#up }" ;;
          *)    echo "✗ Torrent VPN: OFFLINE (''${st#down }) — torrents are paused by the kill switch, nothing leaks" ;;
        esac
        ${lib.optionalString portForward ''[ -s /run/homelab/vpn-port ] && echo "  forwarded port $(cat /run/homelab/vpn-port)"''}
        [ -e ${vpnConf} ] || echo "  No Proton config yet: see 'homelab setup' step 7."
        ''}
      }
      case "''${1:-status}" in
        vpn) vpn ;;
        minecraft|mc)
          ${if !mc then ''echo "Minecraft is off in settings (homelab.minecraft = false)."; exit 1'' else ''
          panel="https://127.0.0.1:${toString ports.crafty}"
          say() { echo "$1"; notify-send -a Minecraft -i applications-games "Minecraft" "$1" 2>/dev/null || true; }
          case "''${2:-status}" in
            on)
              if systemctl is-active --quiet ${craftyUnit}; then say "Already on."; exit 0; fi
              [ -e ${craftyDir}/config/version.json ] || echo "First start: downloading the server panel (about 1 GB), give it a few minutes…"
              systemctl start ${craftyUnit}
              for _ in $(seq 1 180); do
                curl -fsSk -o /dev/null --max-time 2 "$panel" && break
                sleep 2
              done
              say "Minecraft ON — control panel: ${minecraftEntry.url}  (Java port 25565)"
              ;;
            off)
              systemctl is-active --quiet ${craftyUnit} || { say "Already off."; exit 0; }
              echo "Saving worlds and stopping (up to 2 minutes)…"
              systemctl stop ${craftyUnit}
              say "Minecraft OFF."
              ;;
            status)
              if systemctl is-active --quiet ${craftyUnit}; then
                echo "Minecraft: ON — control panel ${minecraftEntry.url}"
                echo "  Players join: ${addr}:25565 (tailnet) or this machine's home-network address :25565"
              else
                echo "Minecraft: OFF — 'homelab minecraft on' (or the menu) starts it"
              fi
              ;;
            panel) exec xdg-open "${minecraftEntry.url}" ;;
            *) echo "usage: homelab minecraft on|off|status|panel"; exit 2 ;;
          esac
          ''}
          ;;
        search-test)
          q="''${2:-nixos}"
          r=$(curl -fsS --max-time 30 -G "http://127.0.0.1:${toString ports.search}/search" \
                --data-urlencode "q=$q" --data-urlencode format=json) \
            || { echo "SearXNG didn't answer: systemctl status searx"; exit 1; }
          echo "Search for '$q': $(jq '.results | length' <<<"$r") results"
          echo "Engines that answered: $(jq -r '[.results[].engines[]] | unique | join(", ")' <<<"$r")"
          echo "Engines that failed (engine: reason):"
          jq -r '.unresponsive_engines[] | "  \(.[0]): \(.[1])"' <<<"$r"
          ;;
        status)
          vpn; echo
          echo "Services:"
          for u in "''${units[@]}"; do show "$u" "$(systemctl is-active "$u" 2>/dev/null || true)"; done
          ${lib.optionalString mc ''echo; "$0" minecraft status''}
          echo; echo "Open from any device on your tailnet${lib.optionalString proxyOn " (start page: http://${addr}/)"}:"
          ${lib.concatMapStrings (x: "show ${lib.escapeShellArg x.name} ${lib.escapeShellArg x.url}\n") everything}
          ${lib.optionalString names ''
          echo
          if getent hosts git.${domain} >/dev/null 2>&1; then echo "Names (*.${domain}) resolve here ✓"
          else echo "Names (*.${domain}) need Tailscale DNS → Pi-hole on each device; see 'homelab setup' step 4. Ports always work."; fi''}
          ;;
        passwords)
          sudo=/run/wrappers/bin/sudo
          echo "Usernames are '${s.username}' unless noted."
          ${lib.optionalString (on "cloud") ''show Nextcloud "admin / $($sudo cat ${secrets}/nextcloud-admin)"''}
          ${lib.optionalString (on "rss") ''show FreshRSS "$($sudo cat ${secrets}/freshrss)"''}
          ${lib.optionalString (on "torrent") ''show Transmission "$($sudo cat ${secrets}/transmission-password)"''}
          ${lib.optionalString (on "pihole") ''show Pi-hole "no password: only your tailnet can reach it"''}
          ${lib.optionalString (on "git") ''show Gitea "make your account: homelab git-admin"''}
          ${lib.optionalString mc ''
          if $sudo test -s ${craftyDir}/config/default-creds.txt; then
            show Minecraft "$($sudo cat ${craftyDir}/config/default-creds.txt | tr -d '\n')  (change it after logging in)"
          else
            show Minecraft "turn it on once (homelab minecraft on); the first login is made then"
          fi''}
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
      1. Join Tailscale (once):   sudo tailscale up     (then: tailscale ip -4 → this machine's 100.x)
      2. Passwords:               homelab passwords
      3. Gitea account:           homelab git-admin
      4. Tailscale DNS (makes the names and ad-blocking work on every device):
         login.tailscale.com/admin/dns → Nameservers → Add nameserver → Custom →
         this machine's 100.x address (tailscale ip -4) → turn on "Override DNS servers".
         Then ${if names then "http://home.${domain}" else "http://${addr}/"} lists everything.
         Pi-hole for devices NOT on Tailscale: set your router's DNS to this machine's LAN address.
      4b. Optional bridges (settings.local.nix, then nixup):
         homelab.lanSubnet = "192.168.1.0/24";  reach home devices from anywhere
         homelab.exitNode = true;               route a device's internet through home
         then login.tailscale.com/admin/machines → ${addr} → ⋯ → Edit route settings → approve.
      5. Dashboard:               ${if benosUrl == "" then "set homelab.benos.url in settings.local.nix, then see step 6"
                                   else "BenOS Lab → Add a server (address: ${addr}) → copy the agent token, then:"}
      6.   echo 'BENOS_AGENT_TOKEN=benos_agent_...' | sudo tee /etc/benos-agent.env >/dev/null
           sudo chmod 600 /etc/benos-agent.env && sudo systemctl restart benos-agent
         Your services then appear on the Lab page by themselves.
      7. Torrent VPN (Proton):    account.protonvpn.com → Downloads → WireGuard configuration.
         Platform: Linux · turn ON "NAT-PMP (Port Forwarding)" · pick a P2P server
         (the ones with the ⇄ icon) · Create → download the .conf, then:
           sudo install -D -m 600 ~/Downloads/<file>.conf ${vpnConf}
           sudo systemctl restart torrent-netns transmission
           homelab vpn          # should say ONLINE with a Proton exit IP
      8. Minecraft:               homelab minecraft on   → open the control panel, log in with
         'homelab passwords', create a server (Fabric/Forge/NeoForge for mods, Paper for plugins),
         upload mods under Files → mods/. 'homelab minecraft off' when you're done.
      9. Other parajynx machines:     on each, settings.local.nix: homelabServer = "${addr}";
         their menu (Super+Alt+d) then lists this machine's services by itself.
      Full guide: /etc/nixos/docs/HOMELAB.md
      EOF
          ;;
        *) echo "usage: homelab [status|vpn|minecraft on|off|status|panel|search-test [query]|passwords|git-admin [name] [email]|setup]"; exit 2 ;;
      esac
    '';
  };
in
{
  assertions = [{
    assertion = s.device == "desktop";
    message = "The homelab module keeps the machine awake 24/7; it's meant for a desktop (settings.device = \"desktop\").";
  }];
  warnings = lib.optional (torrent && !vpnOn)
    "homelab.torrentVpn = false: Transmission torrents from your home IP.";

  my.packages = [ homelab ];
  my.menu."Homelab" = [
    { label = "What's running + links"; run = "homelab status"; mode = "term"; }
    { label = "Passwords"; run = "homelab passwords"; mode = "term"; }
    { label = "Search: which engines work?"; run = "homelab search-test"; mode = "term"; }
    { label = "Setup steps"; run = "homelab setup"; mode = "term"; }
  ] ++ lib.optional torrent { label = "Torrent VPN: online?"; run = "homelab vpn"; mode = "term"; };
  my.menu."Minecraft" = lib.mkIf mc [
    { label = "Minecraft server: turn ON"; run = "homelab minecraft on"; mode = "term"; }
    { label = "Minecraft server: turn OFF"; run = "homelab minecraft off"; mode = "term"; }
    { label = "Minecraft control panel (worlds, mods, players)"; run = "https://127.0.0.1:${toString ports.crafty}"; mode = "url"; }
    { label = "Minecraft: is it on?"; run = "homelab minecraft status"; mode = "term"; }
  ];
  my.selfhosted = lib.listToAttrs (map (x: lib.nameValuePair x.name "http://127.0.0.1:${toString x.port}${x.path or ""}") services)
    // lib.optionalAttrs proxyOn { "Homelab start page" = "http://127.0.0.1/"; }
    // lib.optionalAttrs mc { "Minecraft control panel" = "https://127.0.0.1:${toString ports.crafty}"; };

  # ── 24/7 ───────────────────────────────────────────────────────────────────
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no"; AllowHibernation = "no";
    AllowHybridSleep = "no"; AllowSuspendThenHibernate = "no";
  };

  # ── Tailscale: the way in ─────────────────────────────────────────────────
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    # Your devices use this machine's Pi-hole through Tailscale; this machine itself keeps its own
    # resolver, so it never ends up asking itself in a loop.
    # Bridges, both off unless set — and stated every boot, so removing a
    # setting really turns it off (`tailscale set` remembers otherwise):
    #   homelab.lanSubnet = "192.168.1.0/24";  your home network reachable from
    #     anywhere on the tailnet (printer, router, a Pi: things that can't run
    #     Tailscale). `ip -4 route | grep -v tailscale` shows yours.
    #   homelab.exitNode = true;  your phone/laptop can send ALL their traffic
    #     through home (public Wi-Fi); you pick "Use exit node" on that device.
    # Either one then needs a one-time Approve in the Tailscale admin page.
    extraSetFlags = lib.optional (on "pihole") "--accept-dns=false" ++ [
      "--advertise-routes=${h.lanSubnet or ""}"
      "--advertise-exit-node=${lib.boolToString (h.exitNode or false)}"
    ];
  };
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
    # git.home.arpa, cloud.home.arpa … → this machine's Tailscale address (whatever it is).
    settings.misc.dnsmasq_lines = lib.optionals names ([ "local=/${domain}/" ]
      ++ map (n: "interface-name=${n}.${domain},tailscale0/4")
           ([ "home" ] ++ map (x: x.sub) services ++ lib.optional mc "minecraft"));
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
        DOMAIN = addr; ROOT_URL = "${canon "git" ports.git}/";
        SSH_DOMAIN = addr;                  # git over ssh goes straight to port 2222, not via the proxy
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
      trusted_domains = [ "127.0.0.1" "localhost" s.hostName ] ++ lib.optional names "cloud.${domain}";
      trusted_proxies = [ "127.0.0.1" ];
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
    baseUrl = canon "rss" ports.rss;
    api.enable = true;                      # phone apps (Reeder, NetNewsWire, ReadYou…)
  };
  services.nginx.virtualHosts.freshrss = lib.mkIf (on "rss") {
    listen = [{ addr = "0.0.0.0"; port = ports.rss; }];
  };

  # ── Transmission ──────────────────────────────────────────────────────────
  services.transmission = lib.mkIf torrent {
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
      # With the VPN, the web UI is reached through a proxy on this machine, so
      # requests arrive from the namespace's link; who may use the proxy is the
      # firewall's call (tailnet, + LAN with homelab.lan).
      rpc-whitelist = if vpnOn then "127.0.0.1,${vethHost}"
        else "127.0.0.1,100.*.*.*" + lib.optionalString lan ",192.168.*.*,10.*.*.*";
      rpc-host-whitelist-enabled = false;
      ratio-limit-enabled = true; ratio-limit = 2.0;
      port-forwarding-enabled = false;      # no UPnP on your home router; Proton forwards instead
    };
  };
  users.users.${s.username}.extraGroups = lib.optional torrent "transmission";
  systemd.tmpfiles.rules = lib.optional torrent "d ${dataDir}/torrents 0775 transmission transmission -";

  # ── Torrent VPN ───────────────────────────────────────────────────────────
  # The namespace: loopback, a WireGuard link to Proton (its encrypted UDP
  # still travels over your normal internet, it's created outside and moved
  # in), and a private link to this machine for the web UI. Default route =
  # the tunnel; there is no other way out.
  systemd.services.torrent-netns = lib.mkIf vpnOn {
    description = "Network namespace whose only exit is Proton VPN (for Transmission)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = vpnConf;      # no config yet → no namespace → no torrents
    path = with pkgs; [ iproute2 wireguard-tools gnugrep gnused coreutils ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      set -eu
      conf=${vpnConf}
      field() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//Ip" "$conf" | head -n1 | tr -d ' '; }
      addrs=$(field Address); dns=$(field DNS)
      [ -n "$addrs" ] || { echo "No Address = line in $conf — is it a WireGuard config?"; exit 1; }

      ip netns del ${ns} 2>/dev/null || true; ip link del vpn-host 2>/dev/null || true
      ip netns add ${ns}
      ip -n ${ns} link set lo up

      ip link add vpn-host type veth peer name vpn-ns
      ip link set vpn-ns netns ${ns}
      ip addr add ${vethHost}/30 dev vpn-host; ip link set vpn-host up
      ip -n ${ns} addr add ${vethNs}/30 dev vpn-ns; ip -n ${ns} link set vpn-ns up

      ip link add wg-proton type wireguard
      grep -viE '^[[:space:]]*(Address|DNS|MTU|Table|PreUp|PostUp|PreDown|PostDown|SaveConfig)[[:space:]]*=' "$conf" \
        | wg setconf wg-proton /dev/stdin
      ip link set wg-proton netns ${ns}
      for a in ''${addrs//,/ }; do ip -n ${ns} addr add "$a" dev wg-proton; done
      ip -n ${ns} link set wg-proton mtu 1420 up
      ip -n ${ns} route add default dev wg-proton
      if printf '%s' "$addrs" | grep -q ':'; then ip -n ${ns} -6 route add default dev wg-proton; fi

      mkdir -p /etc/netns/${ns}
      echo "nameserver ''${dns%%,*}" > /etc/netns/${ns}/resolv.conf
    '';
    preStop = "ip netns del ${ns} || true; ip link del vpn-host 2>/dev/null || true";
  };

  systemd.services.transmission = lib.mkIf vpnOn {
    bindsTo = [ "torrent-netns.service" ];           # VPN namespace gone → Transmission stops
    after = [ "torrent-netns.service" ];
    # A private user namespace can't join a namespace owned by the host's.
    serviceConfig = inNs // { PrivateUsers = false; };
  };

  # Web UI: this machine's port 9091 → Transmission inside the namespace.
  systemd.sockets.torrent-rpc = lib.mkIf vpnOn {
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "0.0.0.0:${toString ports.torrent}" ];
  };
  systemd.services.torrent-rpc = lib.mkIf vpnOn {
    description = "Proxy to Transmission's web UI inside the VPN namespace";
    requires = [ "torrent-rpc.socket" ];
    after = [ "torrent-rpc.socket" ];
    serviceConfig = {
      ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${vethNs}:${toString ports.torrent}";
      DynamicUser = true; PrivateTmp = true; NoNewPrivileges = true;
    };
  };

  # Proton port forwarding (NAT-PMP): ask for a port every 45 s, tell Transmission.
  systemd.services.torrent-portforward = lib.mkIf (vpnOn && portForward) {
    description = "Keep a Proton VPN forwarded port for Transmission";
    wantedBy = [ "transmission.service" ];
    bindsTo = [ "transmission.service" ];
    after = [ "transmission.service" ];
    path = with pkgs; [ libnatpmp transmission_4 gnugrep coreutils jq ];
    serviceConfig = inNs // { Restart = "always"; RestartSec = 30; };
    script = ''
      auth="$(jq -r '"\(."rpc-username"):\(."rpc-password")"' ${secrets}/transmission.json)"
      last=""
      while true; do
        natpmpc -a 1 0 udp 60 -g 10.2.0.1 >/dev/null
        port=$(natpmpc -a 1 0 tcp 60 -g 10.2.0.1 | grep -oP 'Mapped public port \K[0-9]+' || true)
        if [ -z "$port" ]; then echo "Proton gave no port (not a P2P server, or NAT-PMP off in the config)"; sleep 60; continue; fi
        if [ "$port" != "$last" ]; then
          transmission-remote 127.0.0.1:${toString ports.torrent} --auth "$auth" --port "$port" >/dev/null && last=$port
          echo "forwarded port $port"
          mkdir -p /run/homelab; echo "$port" > /run/homelab/vpn-port 2>/dev/null || true
        fi
        sleep 45
      done
    '';
  };

  # Every minute: does the tunnel work, and does it exit somewhere other than
  # home? Notifies your desktop when the answer changes.
  systemd.services.torrent-vpn-check = lib.mkIf vpnOn {
    description = "Check the torrent VPN and notify on change";
    path = with pkgs; [ curl iproute2 coreutils gnugrep gnused libnotify util-linux ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /run/homelab
      prev=$(cat ${vpnState} 2>/dev/null || echo none)
      if [ ! -e ${vpnConf} ]; then now="down no Proton config at ${vpnConf}"
      elif ! ip netns list | grep -qw ${ns}; then now="down namespace not running (systemctl status torrent-netns)"
      else
        # Cloudflare's trace by IP address: no DNS involved, so it can't be fooled by the resolver.
        ipof() { "$@" curl -fsS --max-time 10 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p'; }
        vpnip=$(ipof ip netns exec ${ns} || true)
        homeip=$(ipof || true)
        if [ -z "$vpnip" ]; then now="down tunnel not passing traffic"
        elif [ "$vpnip" = "$homeip" ]; then now="down LEAK: exits from your home IP"
        else now="up $vpnip"; fi
      fi
      echo "$now" > ${vpnState}
      # Only "up"/"down" changes are news, not a new exit IP.
      if [ "''${prev%% *}" != "''${now%% *}" ]; then
        case "$now" in
          up*) title="Torrent VPN online"; body="Torrents go through Proton (''${now#up })."; urg=normal ;;
          *)   title="Torrent VPN OFFLINE"; body="''${now#down }. Torrents are cut off until it's back — nothing leaks."; urg=critical ;;
        esac
        uid=$(id -u ${s.username})
        if [ -S "/run/user/$uid/bus" ]; then
          runuser -u ${s.username} -- env DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            notify-send -a Homelab -u "$urg" -i network-vpn "$title" "$body" || true
        fi
        echo "$title: $body"
      fi
    '';
  };
  systemd.timers.torrent-vpn-check = lib.mkIf vpnOn {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "1min"; OnUnitActiveSec = "1min"; };
  };

  # Tiny status page for the BenOS agent: 200 while the VPN is up, 503 if not.
  systemd.sockets.torrent-vpn-status = lib.mkIf vpnOn {
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "127.0.0.1:${toString vpnStatusPort}" ];
    socketConfig.Accept = true;
  };
  systemd.services."torrent-vpn-status@" = lib.mkIf vpnOn {
    description = "Torrent VPN status for the dashboard";
    serviceConfig = {
      StandardInput = "socket"; StandardOutput = "socket";
      DynamicUser = true; ProtectSystem = "strict"; NoNewPrivileges = true;
      ExecStart = pkgs.writeShellScript "torrent-vpn-status" ''
        while IFS= read -r l && [ -n "''${l%$'\r'}" ]; do :; done
        st=$(cat ${vpnState} 2>/dev/null || echo "down not checked yet")
        case "$st" in up*) code="200 OK" ;; *) code="503 Service Unavailable" ;; esac
        printf 'HTTP/1.0 %s\r\nContent-Type: text/plain\r\nContent-Length: %s\r\n\r\n%s\n' "$code" "$(( ''${#st} + 1 ))" "$st"
      '';
    };
  };

  # ── SearXNG ───────────────────────────────────────────────────────────────
  # SearXNG's own defaults (about 90 engines) stay on; this adds dependable
  # web engines, drops ones that only ever error here (.onion search needs Tor,
  # German recipes), gives slow engines more time, and turns on autocomplete,
  # favicons and the image proxy. Engines that fail for a while (a CAPTCHA,
  # rate limits) are skipped automatically and come back on their own.
  # `homelab search-test` shows which engines answered and why the others didn't.
  # Your own changes: homelab.searchEngines = [ { name = "yandex"; disabled = false; } ];
  services.searx = lib.mkIf (on "search") {
    enable = true;
    redisCreateLocally = true;
    environmentFile = "${secrets}/searx.env";
    settings = {
      use_default_settings.engines.remove = [ "ahmia" "torch" "chefkoch" ];
      server = {
        bind_address = "0.0.0.0"; port = ports.search;
        secret_key = "$SEARX_SECRET_KEY";
        base_url = "${canon "search" ports.search}/";
        limiter = false;                    # private instance: no bot limiter needed
        image_proxy = true;                 # images load via your server, not from the sites
      };
      general.instance_name = "search";
      search = {
        formats = [ "html" "json" ];        # json lets scripts and BenOS query it
        autocomplete = "duckduckgo";
        favicon_resolver = "duckduckgo";
        default_lang = h.searchLanguage or "en-US";
        safe_search = 0;
      };
      outgoing = {
        request_timeout = 5.0;              # default 3 s: too short for half the engines
        max_request_timeout = 10.0;
      };
      ui = {
        query_in_title = true;
        center_alignment = true;
        hotkeys = "vim";                    # j/k to move, Enter to open
      };
      plugins."searx.plugins.infinite_scroll.SXNGPlugin".active = true;
      engines = map (name: { inherit name; disabled = false; }) [
        # more general web results, so one blocked engine never leaves you empty
        "mojeek" "qwant" "presearch" "yep"
        # things you'd actually search for
        "reddit" "hackernews" "nixos wiki" "crates.io" "npm" "lib.rs" "pkg.go.dev"
        "codeberg" "gitlab" "imdb" "duckduckgo weather"
      ] ++ (h.searchEngines or [ ]);
    };
    # Site icons next to results, cached on disk (default: a temp file, lost on restart).
    faviconsSettings.favicons = {
      cfg_schema = 1;
      cache = { db_url = "/var/cache/searx/faviconcache.db"; MAINTENANCE_MODE = "auto"; };
    };
  };
  systemd.services.searx.serviceConfig.CacheDirectory = lib.mkIf (on "search") "searx";

  # ── Reverse proxy (Caddy) ─────────────────────────────────────────────────
  # Port 80, Tailscale only (+ LAN with homelab.lan). Plain http: Tailscale
  # already encrypts everything between your devices.
  services.caddy = lib.mkIf proxyOn {
    enable = true;
    globalConfig = "auto_https off";
    virtualHosts = {
      # Any name that reaches port 80 without a service name (http://live/, its 100.x address) → start page.
      ":80".extraConfig = ''
        root * ${startPage}
        file_server
      '';
    } // lib.optionalAttrs names ({
      "http://home.${domain}".extraConfig = ''
        root * ${startPage}
        file_server
      '';
    } // lib.listToAttrs (map (x: lib.nameValuePair "http://${x.sub}.${domain}" {
      extraConfig = "reverse_proxy 127.0.0.1:${toString x.port}";
    }) services) // lib.optionalAttrs mc {
      # Crafty serves https with its own certificate; the proxy talks to it on this machine only.
      "http://minecraft.${domain}".extraConfig = ''
        reverse_proxy https://127.0.0.1:${toString ports.crafty} {
          transport http {
            tls_insecure_skip_verify
          }
        }
      '';
    });
  };

  # ── Minecraft: Crafty Controller, OFF until you turn it on ────────────────
  # A web control panel for Minecraft servers: create Vanilla / Paper / Fabric /
  # Forge / NeoForge servers, upload mods and plugins (Files → mods/), import a
  # modpack, schedule backups, see the console, manage players.
  #
  #   homelab minecraft on | off | status | panel     (or the Minecraft menu)
  #
  # Turning it on starts the panel and every server you've marked "start with
  # Crafty"; off stops them cleanly (worlds saved). It never starts at boot.
  # Networking is plain: host networking, no VPN, no namespace, no Tor — the
  # game ports are open to your home network and your tailnet, nothing else.
  virtualisation.docker.enable = lib.mkIf mc true;
  virtualisation.docker.enableOnBoot = lib.mkIf mc (lib.mkDefault false);   # starts with the panel, not at boot
  virtualisation.oci-containers = lib.mkIf mc {
    backend = "docker";
    containers.crafty = {
      image = craftyImage;
      autoStart = false;
      environment.TZ = s.timeZone or "UTC";
      volumes = [
        "${craftyDir}/backups:/crafty/backups"
        "${craftyDir}/logs:/crafty/logs"
        "${craftyDir}/servers:/crafty/servers"
        "${craftyDir}/config:/crafty/app/config"
        "${craftyDir}/import:/crafty/import"
      ];
      # Host networking: the NixOS firewall decides who reaches which port (Docker's
      # own port publishing would go around it). Two minutes to save worlds on stop.
      extraOptions = [ "--network=host" "--stop-timeout=120" ];
    };
  };
  systemd.services.docker-crafty.serviceConfig.TimeoutStopSec = lib.mkIf mc (lib.mkForce 180);
  systemd.tmpfiles.settings."10-crafty" = lib.mkIf mc (lib.genAttrs
    (map (d: "${craftyDir}/${d}") [ "backups" "logs" "servers" "config" "import" ])
    (_: { d = { mode = "0755"; }; }));
  # Game ports: Java 25565-25575, Bedrock (Geyser) 19132/udp — home network + tailnet.
  networking.firewall.allowedTCPPortRanges = lib.optional mc { from = 25565; to = 25575; };
  networking.firewall.allowedUDPPortRanges = lib.optional mc { from = 19132; to = 19133; };
  # You may switch it on and off without a password.
  security.polkit.extraConfig = lib.mkIf mc ''
    polkit.addRule(function (action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "${craftyUnit}" && subject.user == "${s.username}") {
        return polkit.Result.YES;
      }
    });
  '';

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
