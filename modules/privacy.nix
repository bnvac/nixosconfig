# Privacy / comms: passwords, Matrix, Tor (two modes), I2P, Proton VPN.
#   torrun <app>  one app through Tor, leak-proof (oniux namespaces, own Tor)
#   tormode on    ALL traffic through Tor (breaks voice/games/LAN) · tormode off
# The Tor daemon does NOT run at boot — `tormode on` starts it, `off` stops it.
# Tor Browser and torrun bring their own Tor, so they work either way.
{ pkgs, lib, ... }:
let
  torrun = pkgs.writeShellScriptBin "torrun" ''exec ${pkgs.oniux}/bin/oniux "$@"'';
  tormode = pkgs.writeShellScriptBin "tormode" ''
    case "''${1:-}" in
      on)  sudo systemctl start tor-transparent && echo "ALL traffic → Tor (nothing else can get out)." ;;
      off) sudo systemctl stop tor-transparent tor && echo "Tor routing OFF, Tor stopped." ;;
      *)   systemctl is-active --quiet tor-transparent && echo "tormode: ON" || echo "tormode: OFF" ;;
    esac
  '';
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
  #  - nat: every IPv4 TCP connection and all DNS are redirected into Tor;
  #  - guard (fail-closed): anything that would still leave directly — other
  #    UDP like QUIC/WebRTC, all IPv6 (Tor's transparent port here is IPv4) —
  #    is dropped, except Tor itself, loopback, and DHCP so the lease survives.
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
            # (that includes .onion's mapped 10.192.0.0/10 range; a bare
            #  "ip daddr … redirect to :port" is invalid nft and used to make
            #  the whole ruleset fail to load, so tormode silently did nothing)
            udp dport 53 redirect to :9053
          }
        }
        table inet tor_guard {
          chain output {
            type filter hook output priority 0; policy drop;
            oifname "lo" accept
            meta skuid "tor" accept
            udp sport 68 udp dport 67 accept
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

  environment.systemPackages = with pkgs; [
    torrun tormode oniux torsocks tor-browser
    bitwarden-desktop bitwarden-cli nheko
    proton-vpn proton-vpn-cli
  ];
  networking.wireguard.enable = true;
}
