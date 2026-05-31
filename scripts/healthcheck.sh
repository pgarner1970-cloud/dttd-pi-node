\
#!/bin/bash
set -eu

echo "=== DTTD Pi Node Healthcheck ==="
echo "Hostname: $(hostname)"
echo "IP: $(hostname -I | awk '{print $1}')"
echo

echo "--- Config ---"
cat /etc/dmx-node.conf || true
echo

echo "--- Services ---"
echo "raspotify: $(systemctl is-active raspotify || true)"
echo "dmx-node-agent: $(systemctl is-active dmx-node-agent || true)"
echo "avahi-daemon: $(systemctl is-active avahi-daemon || true)"
echo

echo "--- ALSA playback devices ---"
aplay -l || true
echo

echo "--- USB audio mixer ---"
CARD="$(aplay -l 2>/dev/null | awk '/AB13X USB Audio/ {gsub("card ","",$2); gsub(":","",$2); print $2; exit}')"
if [ -n "$CARD" ]; then
  echo "AB13X USB Audio card number: $CARD"
  amixer -c "$CARD" || true
else
  echo "AB13X USB Audio not currently detected"
fi
echo

echo "--- Raspotify environment ---"
systemctl show raspotify -p Environment --no-pager -l || true
echo

echo "--- Spotify Connect advertisements ---"
if command -v avahi-browse >/dev/null 2>&1; then
  timeout 5 avahi-browse -rt _spotify-connect._tcp || true
else
  echo "avahi-browse not installed"
fi
echo

echo "--- Recent Raspotify log ---"
journalctl -u raspotify -n 40 --no-pager -o cat || true
echo

echo "--- Recent Agent log ---"
journalctl -u dmx-node-agent -n 30 --no-pager -o cat || true
