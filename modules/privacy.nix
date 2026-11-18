# Privacy / comms: passwords, Matrix, Tor (three ways), I2P, Proton (VPN, Mail, Pass).
#   Tor Browser     Super+Alt+t — its own Tor, works any time
#   torrun <app>    one app through Tor, leak-proof (oniux namespaces, own Tor)
#   tormode on      ALL traffic through Tor (breaks voice/games/LAN/VPN) · off · status
# The Tor daemon does NOT run at boot — `tormode on` starts it, `off` stops it.
{ pkgs, lib, ... }:
let
  torrun = pkgs.writeShellScriptBin "torrun" ''
    [ "$#" -gt 0 ] || { echo "usage: torrun <command> [args…]   e.g. torrun firefox"; exit 2; }
    exec ${pkgs.oniux}/bin/oniux "$@"
  '';

  # tormode: on/off, and proof — it asks check.torproject.org whether your
  # traffic really arrives from Tor, and waits for Tor to finish connecting
  # instead of claiming success while it's still bootstrapping.
  tormode = pkgs.writeShellApplication {
    name = "tormode";
    runtimeInputs = with pkgs; [ curl jq coreutils systemd ];
    text = ''
      check() {
        local r
        r=$(curl -s --max-time 15 https://check.torproject.org/api/ip) || return 1
        if jq -e '.IsTor == true' <<<"$r" >/dev/null; then
          echo "✓ traffic goes through Tor — exit IP $(jq -r .IP <<<"$r")"
        else
          echo "✗ NOT through Tor — your IP $(jq -r .IP <<<"$r")"; return 1
        fi
      }
      case "''${1:-status}" in
        on)
          /run/wrappers/bin/sudo systemctl start tor-transparent
          printf 'Connecting to Tor'
          for _ in $(seq 1 45); do                 # up to ~90 s to bootstrap
            if check >/dev/null 2>&1; then
              echo; check
              echo "ALL traffic → Tor. What can't go through Tor (IPv6, UDP like QUIC/WebRTC,"
              echo "your LAN, Docker/VMs, a VPN) is refused, never leaked. \`tormode off\` to stop."
              exit 0
            fi
            printf '.'; sleep 2
          done
          echo; echo "Tor is on but hasn't connected yet (network blocking Tor? see: journalctl -u tor -e)."
          echo "Nothing leaks meanwhile — everything is refused until Tor is up."
          exit 1 ;;
        off)
          /run/wrappers/bin/sudo systemctl stop tor-transparent tor
          echo "Tor routing OFF, Tor stopped." ;;
        status | check)
          if systemctl is-active --quiet tor-transparent; then echo "tormode: ON"; else echo "tormode: OFF"; fi
          check || true ;;
        *) echo "usage: tormode on|off|status"; exit 2 ;;
      esac
    '';
  };
in
{
  # (electron/olm insecure allowances live in core.nix so they merge reliably)
  services.tor = {
    enable = true; client.enable = true;
    settings = {
      TransPort = [ { addr = "127.0.0.1"; port = 9040; } ];
      DNSPort   = [ { addr = "127.0.0.1"; port = 9053; } ];
      VirtualAddrNetworkIPv4 = "10.192.0.0/10";
      AutomapHostsOnResolve = true;
    };
  };
  systemd.services.tor.wantedBy = lib.mkForce [ ];      # on demand only (tormode on)

  # Transparent torification, off until `tormode on`:
  #  - nat: every IPv4 TCP connection and all DNS are redirected into Tor
  #    (that includes .onion's mapped 10.192.0.0/10 range).
  #  - guard (fail-closed): anything else that would leave directly — other
  #    UDP like QUIC/WebRTC, all IPv6 (Tor's transparent port is IPv4), and
  #    forwarded traffic from Docker containers and VMs — is REFUSED, except
  #    Tor itself, loopback, and DHCP so the lease survives. Refused rather
  #    than silently dropped, so apps fall back to plain TCP (which goes
  #    through Tor) at once instead of hanging for a minute first.
  #    If Tor is down, traffic stops rather than leaking.
  systemd.services.tor-transparent = {
    description = "Transparent Tor routing";
    after = [ "tor.service" "network.target" ]; wants = [ "tor.service" ];
    serviceConfig = {
      Type = "oneshot"; RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "tor-trans-up" ''
        ${pkgs.nftables}/bin/nft -f - <<'EOF'
        table ip tor_trans {
          chain output {
            type nat hook output priority -100;
            meta skuid "tor" return
            ip daddr 127.0.0.0/8 return
            meta l4proto tcp redirect to :9040
            udp dport 53 redirect to :9053
          }
        }
        table inet tor_guard {
          chain output {
            type filter hook output priority 0; policy drop;
            oifname "lo" accept
            meta skuid "tor" accept
            udp sport 68 udp dport 67 accept
            meta l4proto tcp reject with tcp reset
            reject with icmpx type admin-prohibited
          }
          chain forward {
            type filter hook forward priority 0; policy drop;
            reject with icmpx type admin-prohibited
          }
        }
        EOF
      '';
      ExecStop = pkgs.writeShellScript "tor-trans-down" ''
        ${pkgs.nftables}/bin/nft delete table ip tor_trans 2>/dev/null || true
        ${pkgs.nftables}/bin/nft delete table inet tor_guard 2>/dev/null || true
      '';
    };
  };

  services.i2p.enable = true;   # console http://127.0.0.1:7657

  # ── Proton VPN ───────────────────────────────────────────────────────────
  # The official app (protonvpn-app) and CLI (protonvpn). Both keep your login
  # in the system keyring and connect through NetworkManager (WireGuard; the
  # OpenVPN plugin covers its OpenVPN mode). The keyring unlocks with your
  # login password at the ly login screen, so the app can read the saved
  # login without asking. Reverse-path filtering is loosened (core.nix +
  # here): strict mode drops a WireGuard tunnel's replies, which is what made
  # the VPN connect and then pass no traffic.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.ly.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;
  networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ];
  networking.firewall.checkReversePath = "loose";

  # ── Proton (VPN, Mail, Pass) ────────────────────────────────────────────
  # The official apps. Each signs in once and keeps the login in the system
  # keyring. Proton Mail Bridge (paid plans) lets Thunderbird or any mail app
  # read Proton mail; Proton Pass is the password manager. Their own "start
  # at login" options work: the session runs XDG autostart entries
  # (desktop.nix), which dwm alone doesn't.
  my.menu."Proton" = [
    { label = "Proton VPN"; run = "protonvpn-app"; }
    { label = "VPN: connect to the fastest server"; run = "protonvpn connect"; mode = "term"; }
    { label = "VPN: disconnect"; run = "protonvpn disconnect"; mode = "term"; }
    { label = "VPN: status"; run = "protonvpn status"; mode = "term"; }
    { label = "VPN: sign in (terminal, first time)"; run = "protonvpn signin"; mode = "tty"; }
    { label = "Proton Mail"; run = "proton-mail"; }
    { label = "Proton Mail Bridge (Thunderbird and other mail apps)"; run = "protonmail-bridge-gui"; }
    { label = "Proton Pass (passwords)"; run = "proton-pass"; }
    { label = "Proton Authenticator (2FA codes)"; run = "proton-authenticator"; needs = "proton-authenticator"; }
  ];

  my.menu."Network & privacy" = [
    { label = "Proton VPN"; run = "protonvpn-app"; }
    { label = "VPN: what's connected"; run = "nmcli -f NAME,TYPE,DEVICE connection show --active"; mode = "term"; }
    { label = "Tor Browser"; run = "tor-browser"; }
    { label = "Mullvad Browser (look like everyone else; no Tor)"; run = "mullvad-browser"; }
    { label = "Tor: route everything ON"; run = "tormode on"; mode = "term"; }
    { label = "Tor: stop routing"; run = "tormode off"; mode = "term"; }
    { label = "Tor: am I on Tor?"; run = "tormode status"; mode = "term"; }
  ];
  my.selfhosted."I2P router" = "http://127.0.0.1:7657";

  my.packages = with pkgs; [
    torrun tormode oniux torsocks tor-browser
    mullvad-browser                         # Tor Browser's anti-fingerprinting, on your normal connection
    bitwarden-desktop bitwarden-cli nheko
    proton-vpn proton-vpn-cli seahorse      # seahorse: see/unlock the keyring
    protonmail-desktop protonmail-bridge-gui proton-pass proton-authenticator
  ];
  networking.wireguard.enable = true;
}
