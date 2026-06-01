#!/usr/bin/env bash
set -euo pipefail

DECK="${1:-}"
if [[ "$DECK" == "--deck" ]]; then
  DECK="${2:-}"
fi

if [[ -z "$DECK" ]]; then
  echo "Usage: sudo ./scripts/install.sh --deck a|b"
  exit 1
fi

DECK="$(echo "$DECK" | tr '[:upper:]' '[:lower:]')"

if [[ "$DECK" == "a" ]]; then
  NODE_KEY="dmx-desk-a"
  DISPLAY_NAME="DMX Deck A"
  HOSTNAME="dmx-desk-a"
elif [[ "$DECK" == "b" ]]; then
  NODE_KEY="dmx-desk-b"
  DISPLAY_NAME="DMX Deck B"
  HOSTNAME="dmx-desk-b"
else
  echo "Deck must be a or b"
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this installer with sudo"
  exit 1
fi

echo "Installing DTTD Pi node for ${DISPLAY_NAME}"

apt-get update
apt-get install -y curl git rsync python3 avahi-daemon avahi-utils alsa-utils

# Raspotify install. If already installed, this is harmless.
if ! command -v librespot >/dev/null 2>&1; then
  curl -sL https://dtcooper.github.io/raspotify/install.sh | sh
fi

mkdir -p /opt/dttd-pi-node
rsync -a --delete ./agent ./systemd ./scripts ./config ./docs /opt/dttd-pi-node/

cat >/etc/dmx-node.conf <<EOF
PORTAL_BASE=https://dj.dancethruthedecades.co.uk/api
SECRET=DMX_NODE_SECRET_7f2c9e4a1b8d6f0c3e5a9d7b2f4c8e1
NODE_KEY=${NODE_KEY}
DISPLAY_NAME=${DISPLAY_NAME}
SPOTIFY_NAME=${DISPLAY_NAME}
EOF

hostnamectl set-hostname "${HOSTNAME}"

mkdir -p /etc/systemd/system/raspotify.service.d
cat >/etc/systemd/system/raspotify.service.d/override.conf <<EOF
[Service]
Environment="LIBRESPOT_NAME=${DISPLAY_NAME}"
Environment="LIBRESPOT_BACKEND=alsa"
Environment="LIBRESPOT_DEVICE_TYPE=speaker"
Environment="LIBRESPOT_DISCOVERY_BACKEND=avahi"
Environment="HOME=/var/lib/raspotify"
EOF

# Keep credential cache enabled for the one-time Spotify phone pairing.
sed -i 's/^LIBRESPOT_DISABLE_CREDENTIAL_CACHE=/#LIBRESPOT_DISABLE_CREDENTIAL_CACHE=/' /etc/raspotify/conf || true
sed -i 's/^LIBRESPOT_ACCESS_TOKEN=/#LIBRESPOT_ACCESS_TOKEN=/' /etc/raspotify/conf || true

cp /opt/dttd-pi-node/systemd/dmx-node-agent.service /etc/systemd/system/dmx-node-agent.service
chmod +x /opt/dttd-pi-node/agent/dmx-node-agent.py
chmod +x /opt/dttd-pi-node/scripts/*.sh

# Allow the disco user to manage the limited services needed by the portal.
cat >/etc/sudoers.d/dttd-node-agent <<EOF
disco ALL=(root) NOPASSWD: /bin/systemctl restart raspotify, /bin/systemctl restart dmx-node-agent, /bin/systemctl is-active raspotify, /sbin/reboot, /usr/sbin/shutdown, /sbin/shutdown, /opt/dttd-pi-node/scripts/healthcheck.sh, /opt/dttd-pi-node/scripts/update.sh, /opt/dttd-pi-node/scripts/set-usb-audio.sh
EOF
chmod 440 /etc/sudoers.d/dttd-node-agent

systemctl daemon-reload
systemctl enable avahi-daemon
systemctl enable raspotify
systemctl enable dmx-node-agent
systemctl restart avahi-daemon
systemctl restart raspotify
systemctl restart dmx-node-agent

echo
echo "Install complete for ${DISPLAY_NAME}"
echo "Next:"
echo "1. Open Spotify on your phone"
echo "2. Select ${DISPLAY_NAME}"
echo "3. Play a track for 5-10 seconds to pair/cache the Spotify Connect speaker"
echo "4. If using USB audio, run:"
echo "   sudo /opt/dttd-pi-node/scripts/set-usb-audio.sh"
echo "5. Refresh Spotify Tools in the DJ portal"
