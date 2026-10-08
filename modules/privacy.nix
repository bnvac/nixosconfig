# Privacy / comms: passwords, Matrix, Tor (two modes), I2P, Proton VPN.
#   torrun <app>  one app through Tor, leak-proof (oniux namespaces)
#   tormode on    ALL traffic through Tor (nftables service; breaks voice/games)
{ config, pkgs, lib, ... }:
let
  torrun = pkgs.writeShellScriptBin "torrun" ''exec ${pkgs.oniux}/bin/oniux "$@"'';
  tormode = pkgs.writeShellScriptBin "tormode" ''
    case "''${1:-}" in
      on)  sudo systemctl start tor-transparent && echo "ALL traffic → Tor." ;;
      off) sudo systemctl stop  tor-transparent && echo "Tor routing OFF." ;;
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

  # Transparent torification, off until `tormode on`. TCP + DNS → Tor; other
  # UDP dropped so it can't leak around the tunnel.
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
            ip daddr 10.192.0.0/10 redirect to :9040
            meta l4proto tcp redirect to :9040
            udp dport 53 redirect to :9053
          }
        }
        EOF
      '';
      ExecStop = "${pkgs.nftables}/bin/nft delete table ip tor_trans";
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
