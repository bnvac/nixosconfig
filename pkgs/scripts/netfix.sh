# netfix — internet not working? Finds which layer is broken and fixes it,
# one step at a time, re-testing after each, and tells you what it was.
#
#   netfix          check + fix (menu → Network & privacy → Internet not working?)
#
# The layers, bottom up:
#   1. Wi-Fi radio off (airplane mode, a key)        → turned back on
#   2. not connected to any network                  → opens the Wi-Fi picker
#   3. the VPN is up but passes nothing / no DNS     → VPN off on this network
#   4. Tailscale's DNS doesn't answer (home server
#      off, or its Pi-hole down)                     → this machine stops using it
#   5. NetworkManager stuck                          → restarted
# Anything left after that is the Wi-Fi driver itself: start the previous
# version from the boot menu, and the report below says what to look at.

ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

ip_ok() { curl -s -o /dev/null --max-time 5 http://1.1.1.1/cdn-cgi/trace; }
dns_ok() { timeout 5 getent hosts example.com >/dev/null 2>&1; }
works() { ip_ok && dns_ok; }
net() { nmcli -t -f UUID,TYPE,STATE connection show --active 2>/dev/null \
          | grep -E ':(802-11-wireless|802-3-ethernet|gsm):activated$' | head -1 | cut -d: -f1; }
done_with() { echo; ok "Fixed: $1"; exit 0; }

step "Checking…"
if works; then
  ok "The internet works (address and names both answer)."
  exit 0
fi

step "1. Wi-Fi radio"
if rfkill list wifi 2>/dev/null | grep -q "Soft blocked: yes" || [ "$(nmcli radio wifi 2>/dev/null)" = disabled ]; then
  rfkill unblock wifi 2>/dev/null || true
  nmcli radio wifi on 2>/dev/null || true
  bad "Wi-Fi was switched off; switched it on."
  sleep 8
  works && done_with "Wi-Fi was switched off."
elif rfkill list wifi 2>/dev/null | grep -q "Hard blocked: yes"; then
  bad "Wi-Fi is off by a hardware switch or key (airplane mode). Press it, then run netfix again."
  exit 1
else
  ok "Radio on."
fi

step "2. Connected to a network?"
if [ -z "$(net)" ]; then
  bad "Not connected. Pick your network:"
  nmcli device wifi rescan 2>/dev/null || true
  command -v wifi >/dev/null && wifi
  sleep 6
  works && done_with "it wasn't connected to a network."
  [ -n "$(net)" ] || { bad "Still not connected. If no networks show up at all, see the end."; }
else
  ok "Connected to $(nmcli -g connection.id connection show "$(net)" 2>/dev/null)."
fi

step "3. VPN"
if nmcli -t -f NAME connection show --active | grep -qx parajynx-vpn; then
  n=$(net)
  nmcli connection down id parajynx-vpn >/dev/null 2>&1 || true
  [ -n "$n" ] && touch "/var/lib/vpn-auto/blocked/$n" 2>/dev/null
  sleep 3
  if works; then
    done_with "the VPN was up but passing nothing here. It's off on this network now (vpn retry tries again later)."
  fi
  ok "Turned the VPN off here; that wasn't it alone."
else
  ok "Not in the way."
fi

step "4. DNS through Tailscale"
if ip_ok && ! dns_ok && tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
  tailscale set --accept-dns=false 2>/dev/null || sudo tailscale set --accept-dns=false
  sleep 3
  if works; then
    echo
    ok "Fixed: Tailscale's DNS (your home server's Pi-hole) wasn't answering."
    echo "    This machine now uses the network's own DNS. To get Pi-hole back once the"
    echo "    server is up:  tailscale set --accept-dns=true"
    echo "    For good: login.tailscale.com/admin/dns → add 9.9.9.9 as a second nameserver,"
    echo "    so DNS keeps working whenever the server is off."
    exit 0
  fi
  ok "Tried the network's own DNS instead; that wasn't it alone."
else
  ok "Not in the way."
fi

step "5. Restarting NetworkManager (your password, once)"
sudo systemctl restart NetworkManager && sleep 10
works && done_with "NetworkManager was stuck."

step "Still not working"
echo "  That points at the Wi-Fi driver or firmware (an update changed them)."
echo "  Start the previous version: reboot, boot menu → All configurations → one down."
echo "  What the driver said (send this to whoever's helping):"
journalctl -b -k --no-pager 2>/dev/null | grep -iE 'iwl|wlan|wifi|firmware|ath1|rtw|mt7|brcm' | tail -12 | sed 's/^/    /'
exit 1
