#!/usr/bin/env bash
set -euo pipefail

echo "=== DTTD Pi Node Healthcheck ==="
echo "Hostname: $(hostname)"
echo "IP: $(hostname -I | awk '{print $1}')"
echo

echo "--- Config ---"
cat /etc/dmx-node.conf || true
echo

echo "--- Services ---"
systemctl is-active raspotify || true
systemctl is-active dmx-node-agent || true
systemctl is-active avahi-daemon || true
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
journalctl -u raspotify -n 30 --no-pager -o cat || true
echo

echo "--- Recent Agent log ---"
journalctl -u dmx-node-agent -n 30 --no-pager -o cat || true
