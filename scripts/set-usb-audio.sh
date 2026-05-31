\
#!/bin/bash
set -eu

CONFIG_FILE="/etc/dmx-node.conf"
RASPOTIFY_OVERRIDE_DIR="/etc/systemd/system/raspotify.service.d"
RASPOTIFY_OVERRIDE_FILE="${RASPOTIFY_OVERRIDE_DIR}/override.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo"
  exit 1
fi

if ! command -v aplay >/dev/null 2>&1; then
  apt-get update
  apt-get install -y alsa-utils
fi

SPOTIFY_NAME="DMX Deck A"
if [ -f "$CONFIG_FILE" ]; then
  FOUND_NAME="$(grep '^SPOTIFY_NAME=' "$CONFIG_FILE" | head -n1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)"
  if [ -n "$FOUND_NAME" ]; then
    SPOTIFY_NAME="$FOUND_NAME"
  fi
fi

echo "Available ALSA playback devices:"
aplay -l || true
echo

if ! aplay -l | grep -q "AB13X USB Audio"; then
  echo "AB13X USB Audio was not found."
  echo "Make sure the USB audio adapter is plugged in before starting the Pi."
  exit 1
fi

# Use the stable ALSA card name, not a changing card number.
ALSA_DEVICE="plughw:Audio,0"

echo "Configuring Raspotify/librespot to use stable ALSA device: ${ALSA_DEVICE}"

mkdir -p "$RASPOTIFY_OVERRIDE_DIR"

cat >"$RASPOTIFY_OVERRIDE_FILE" <<EOF
[Unit]
After=sound.target network-online.target
Wants=network-online.target

[Service]
ExecStartPre=/bin/sleep 8

Environment="LIBRESPOT_NAME=${SPOTIFY_NAME}"
Environment="LIBRESPOT_BACKEND=alsa"
Environment="LIBRESPOT_DEVICE=${ALSA_DEVICE}"
Environment="LIBRESPOT_INITIAL_VOLUME=85"
Environment="LIBRESPOT_DEVICE_TYPE=speaker"
Environment="LIBRESPOT_DISCOVERY_BACKEND=avahi"
Environment="HOME=/var/lib/raspotify"
EOF

sed -i 's/^LIBRESPOT_DISABLE_CREDENTIAL_CACHE=/#LIBRESPOT_DISABLE_CREDENTIAL_CACHE=/' /etc/raspotify/conf || true
sed -i 's/^LIBRESPOT_ACCESS_TOKEN=/#LIBRESPOT_ACCESS_TOKEN=/' /etc/raspotify/conf || true

# Set PCM where available. This adapter uses PCM rather than Master.
CARD="$(aplay -l | awk '/AB13X USB Audio/ {gsub("card ","",$2); gsub(":","",$2); print $2; exit}')"
if [ -n "$CARD" ]; then
  amixer -c "$CARD" sset PCM 85% >/dev/null 2>&1 || true
  alsactl store || true
fi

systemctl daemon-reload
systemctl reset-failed raspotify || true
systemctl restart raspotify

echo
echo "Raspotify audio device updated."
echo "Check with:"
echo "  sudo systemctl show raspotify -p Environment --no-pager -l"
echo "  alsamixer"
