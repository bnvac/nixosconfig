# A VPN that turns itself on, and steps aside on networks that block it.
#
#   vpn add ~/Downloads/proton.conf   once: a WireGuard config (Proton: account
#                                     page → Downloads → WireGuard configuration)
#   vpn            what's going on (on/off, this network, your public IP)
#   vpn off        stop it and keep it off · vpn on: back to automatic
#   vpn retry      try again on networks it gave up on
#
# How it behaves (vpn-auto, a small root service):
#   - Whenever you're on a network, the VPN connects.
#   - If nothing gets through it for 10 seconds (settings vpn.giveUpSeconds), it
#     disconnects and checks the network on its own:
#       · the internet works without it → this network blocks VPNs (school,
#         work, some cafés): it stays off on THIS network (for 12 hours, or
#         until `vpn retry`) and you get a notification. Other networks still
#         get the VPN.
#       · no internet at all (Wi-Fi gone, or a login page) → it waits, and
#         tries again as soon as the internet is back.
#   - `tormode on`, or another VPN you connected yourself (the Proton app):
#     it stands aside.
#
# Works together with Tailscale: Tailscale's routing rules come before the
# VPN's, so your tailnet (home server, sync, DeviceLink) goes straight to your
# devices and Tailscale's own connections use the real network; everything
# else goes through the VPN. No kill switch on purpose: a network that blocks
# VPNs would otherwise leave you with no internet at all.
#
# The config's private key is stored by NetworkManager (root-only), not in
# git or the Nix store. The Proton app (privacy module) still works, but use
# one or the other: its kill switch blocks Tailscale.
{ pkgs, lib, ... }:
let
  s = import ../settings.nix;
  v = s.vpn or { };
  id = "parajynx-vpn";         # NetworkManager connection name
  dev = "pjvpn0";              # its network interface
  state = "/var/lib/vpn-auto";
  giveUp = toString (v.giveUpSeconds or 10);
  retryHours = toString (v.retryBlockedHours or 12);
  # Something tiny that always answers, by address (no DNS involved).
  probe = "http://1.1.1.1/cdn-cgi/trace";

  vpn = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = with pkgs; [ networkmanager curl coreutils gnugrep systemd ];
    text = ''
      have() { nmcli -g connection.uuid connection show id ${id} >/dev/null 2>&1; }
      net() { nmcli -t -f UUID,TYPE,STATE connection show --active \
                | grep -E ':(802-11-wireless|802-3-ethernet|gsm):activated$' | head -1 | cut -d: -f1; }
      case "''${1:-status}" in
        add)
          f="''${2:-}"
          [ -r "$f" ] || { echo "usage: vpn add <wireguard-config.conf>"; exit 2; }
          tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
          cp -- "$f" "$tmp/${dev}.conf"          # the file name becomes the interface name
          nmcli connection delete id ${id} >/dev/null 2>&1 || true
          out=$(nmcli connection import type wireguard file "$tmp/${dev}.conf")
          uuid=$(grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}' <<<"$out" | head -1)
          [ -n "$uuid" ] || { echo "Import failed: $out"; exit 1; }
          # Ours to switch (autoconnect off), and its DNS only while it's up (no DNS leaks).
          nmcli connection modify "$uuid" connection.id ${id} connection.autoconnect no \
            ipv4.dns-priority -50 ipv6.dns-priority -50
          nmcli connection down "$uuid" >/dev/null 2>&1 || true
          rm -f ${state}/paused ${state}/blocked/* 2>/dev/null || true
          echo "VPN added. It connects by itself in a few seconds; 'vpn' shows it."
          echo "The config holds your private key: you can delete $f now (it's stored safely)."
          ;;
        on)
          rm -f ${state}/paused
          n=$(net); [ -n "$n" ] && rm -f "${state}/blocked/$n"
          echo "VPN: automatic (connects within a few seconds)." ;;
        off)
          touch ${state}/paused
          nmcli connection down id ${id} >/dev/null 2>&1 || true
          echo "VPN: off until 'vpn on'." ;;
        retry)
          rm -f ${state}/blocked/* 2>/dev/null || true
          echo "Trying the VPN again on every network." ;;
        status)
          if ! have; then
            echo "No VPN set up yet: download a WireGuard config (Proton: account → Downloads →"
            echo "WireGuard configuration), then: vpn add ~/Downloads/<file>.conf"; exit 0
          fi
          if [ -e ${state}/paused ]; then echo "Mode:      off (vpn on)"; else echo "Mode:      automatic"; fi
          if nmcli -t -f NAME connection show --active | grep -qx ${id}; then echo "VPN:       connected"
          else echo "VPN:       not connected"; fi
          n=$(net)
          if [ -z "$n" ]; then echo "Network:   none"
          else
            echo "Network:   $(nmcli -g connection.id connection show "$n")"
            [ -e "${state}/blocked/$n" ] && echo "           blocks VPNs: VPN off here (vpn retry)"
          fi
          ip=$(curl -s --max-time 5 ${probe} | grep -E '^(ip|loc)=' | tr '\n' ' ')
          echo "Public IP: ''${ip:-no internet}"
          systemctl is-active --quiet tailscaled && echo "Tailscale: $(tailscale ip -4 2>/dev/null || echo 'signed out (menu → Tailscale: sign in)')"
          ;;
        *) echo "usage: vpn [status|on|off|retry|add <file.conf>]"; exit 2 ;;
      esac
    '';
  };

  auto = pkgs.writeShellApplication {
    name = "vpn-auto";
    runtimeInputs = with pkgs; [ networkmanager curl coreutils gnugrep util-linux libnotify systemd ];
    text = ''
      user=${s.username}
      notify() {
        local uid; uid=$(id -u "$user" 2>/dev/null) || return 0
        [ -S "/run/user/$uid/bus" ] || return 0
        runuser -u "$user" -- env DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
          notify-send -a VPN -i network-vpn "$1" "$2" >/dev/null 2>&1 || true
      }
      through_vpn() { curl -s -o /dev/null --max-time 3 --interface ${dev} ${probe}; }
      direct() { curl -s -o /dev/null --max-time 4 ${probe}; }
      down() { nmcli connection down id ${id} >/dev/null 2>&1 || true; }

      last_net="" fail_since="" waiting="" tries=0 last_ok=0 worked=0
      while sleep 3; do
        vpn_uuid=$(nmcli -g connection.uuid connection show id ${id} 2>/dev/null) || { sleep 7; continue; }
        active=$(nmcli -t -f UUID,TYPE,STATE connection show --active 2>/dev/null) || continue
        net=$(grep -E ':(802-11-wireless|802-3-ethernet|gsm):activated$' <<<"$active" | head -1 | cut -d: -f1 || true)
        up=false; grep -q "^$vpn_uuid:" <<<"$active" && up=true
        now=$(date +%s)

        if [ "$net" != "$last_net" ]; then      # new network (or none): start fresh
          last_net=$net fail_since="" waiting="" tries=0 last_ok=0 worked=0
        fi
        [ -n "$net" ] || continue               # no network: nothing to decide yet

        # Stand aside: paused, tormode, or another VPN you connected yourself.
        if [ -e ${state}/paused ] || systemctl is-active --quiet tor-transparent \
           || grep -vE "^$vpn_uuid:" <<<"$active" | grep -qE ':(wireguard|vpn):activated$'; then
          continue
        fi

        b="${state}/blocked/$net"
        if [ -e "$b" ]; then
          if (( now - $(stat -c %Y "$b") < ${retryHours} * 3600 )); then $up && down; continue; fi
          rm -f "$b"
        fi

        if [ -n "$waiting" ]; then              # no internet here at all: wait for it
          direct || continue
          waiting="" fail_since=""
        fi

        if ! $up; then
          nmcli --wait 15 connection up uuid "$vpn_uuid" >/dev/null 2>&1 || true
          tries=$((tries + 1)) fail_since=$now last_ok=0
          continue
        fi

        # Connected: check it every 15 s, every 3 s while it's failing.
        if [ -z "$fail_since" ] && (( now - last_ok < 15 )); then continue; fi
        if through_vpn; then
          [ "$last_ok" = 0 ] && [ "$tries" -gt 0 ] && echo "VPN up on $net"
          fail_since="" last_ok=$now worked=1; continue
        fi
        [ -n "$fail_since" ] || fail_since=$now
        (( now - fail_since >= ${giveUp} )) || continue

        down; fail_since="" last_ok=0
        name=$(nmcli -g connection.id connection show "$net" 2>/dev/null || echo "this network")
        if direct && [ "$worked" = 1 ]; then
          # It worked on this network before: the VPN server hiccupped. Reconnect once.
          worked=0; echo "VPN stopped answering on $name: reconnecting"; continue
        elif direct; then
          touch "$b"
          echo "$name blocks the VPN: off here"
          notify "VPN off on $name" "This network blocks VPNs, so you're connected without it here. Other networks still use it. (vpn retry)"
        else
          waiting=1
          echo "$name: no internet, waiting"
          notify "No internet on $name" "VPN paused until the internet works (log in to the Wi-Fi's page if it has one); then it reconnects."
        fi
      done
    '';
  };
in
{
  my.packages = [ vpn ];

  systemd.services.vpn-auto = {
    description = "Turn the VPN on by itself, off on networks that block it";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager.service" ];
    wants = [ "NetworkManager.service" ];
    serviceConfig = {
      ExecStart = "${auto}/bin/vpn-auto";
      Restart = "always";
      RestartSec = 5;
      Nice = 10;
    };
  };
  # Your user can switch it (vpn on/off/retry) without sudo: you're in the
  # networkmanager group, which owns this folder.
  systemd.tmpfiles.rules = [
    "d ${state} 2775 root networkmanager -"
    "d ${state}/blocked 2775 root networkmanager -"
  ];

  my.menu."Network & privacy" = [
    { label = "VPN: status"; run = "vpn"; mode = "term"; }
    { label = "VPN: turn off"; run = "vpn off"; mode = "term"; }
    { label = "VPN: back to automatic"; run = "vpn on"; mode = "term"; }
    { label = "VPN: try again on blocked networks"; run = "vpn retry"; mode = "term"; }
  ];
}
