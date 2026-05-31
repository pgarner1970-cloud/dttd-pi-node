#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/dmx-node.conf"
RASPOTIFY_OVERRIDE_DIR="/etc/systemd/system/raspotify.service.d"
RASPOTIFY_OVERRIDE_FILE="${RASPOTIFY_OVERRIDE_DIR}/override.conf"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script with sudo"
  exit 1
fi

if ! command -v aplay >/dev/null 2>&1; then
  apt-get update
  apt-get install -y alsa-utils
fi

SPOTIFY_NAME="DMX Deck"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE" || true
  SPOTIFY_NAME="${SPOTIFY_NAME:-${DISPLAY_NAME:-DMX Deck}}"
fi

REQUESTED_DEVICE="${1:-}"

echo "Available ALSA playback devices:"
aplay -l || true
echo

if [[ -n "$REQUESTED_DEVICE" ]]; then
  ALSA_DEVICE="$REQUESTED_DEVICE"
else
  # Prefer the first USB audio playback device.
  USB_LINE="$(aplay -l 2>/dev/null | awk '/^card [0-9]+:/ && /USB|usb|Audio|audio/ {print; exit}')"

  if [[ -z "$USB_LINE" ]]; then
    echo "No obvious USB audio card was found."
    echo "You can specify one manually, for example:"
    echo "  sudo /opt/dttd-pi-node/scripts/set-usb-audio.sh plughw:1,0"
    exit 1
  fi

  CARD="$(echo "$USB_LINE" | sed -n 's/^card \([0-9][0-9]*\):.*/\1/p')"
  DEVICE="0"
  ALSA_DEVICE="plughw:${CARD},${DEVICE}"
fi

echo "Configuring Raspotify/librespot to use ALSA device: ${ALSA_DEVICE}"

mkdir -p "$RASPOTIFY_OVERRIDE_DIR"

cat >"$RASPOTIFY_OVERRIDE_FILE" <<EOF
[Service]
Environment="LIBRESPOT_NAME=${SPOTIFY_NAME}"
Environment="LIBRESPOT_BACKEND=alsa"
Environment="LIBRESPOT_DEVICE=${ALSA_DEVICE}"
Environment="LIBRESPOT_DEVICE_TYPE=speaker"
Environment="LIBRESPOT_DISCOVERY_BACKEND=avahi"
Environment="HOME=/var/lib/raspotify"
EOF

# Keep credential cache enabled for the one-time Spotify phone pairing.
sed -i 's/^LIBRESPOT_DISABLE_CREDENTIAL_CACHE=/#LIBRESPOT_DISABLE_CREDENTIAL_CACHE=/' /etc/raspotify/conf || true
sed -i 's/^LIBRESPOT_ACCESS_TOKEN=/#LIBRESPOT_ACCESS_TOKEN=/' /etc/raspotify/conf || true

systemctl daemon-reload
systemctl reset-failed raspotify || true
systemctl restart raspotify

echo
echo "Raspotify audio device updated."
echo "Check with:"
echo "  sudo systemctl show raspotify -p Environment --no-pager -l"
echo "  sudo journalctl -u raspotify -n 60 --no-pager -o cat"
