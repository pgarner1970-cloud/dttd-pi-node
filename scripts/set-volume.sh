\
#!/bin/bash
set -eu

VOLUME="${1:-85}"

if ! echo "$VOLUME" | grep -Eq '^[0-9]+$'; then
    echo "Volume must be 0-100"
    exit 1
fi

if [ "$VOLUME" -lt 0 ]; then
    VOLUME=0
fi

if [ "$VOLUME" -gt 100 ]; then
    VOLUME=100
fi

CARD="$(aplay -l 2>/dev/null | awk '/AB13X USB Audio/ {gsub("card ","",$2); gsub(":","",$2); print $2; exit}')"

if [ -z "$CARD" ]; then
    CARD="$(aplay -l 2>/dev/null | awk '/^card [0-9]+:/ && /USB|usb|Audio|audio/ {gsub("card ","",$2); gsub(":","",$2); print $2; exit}')"
fi

if [ -z "$CARD" ]; then
    echo "USB audio device not found"
    aplay -l || true
    exit 1
fi

DEVICE="plughw:Audio,0"

echo "Using ALSA card ${CARD}"
echo "Using stable Raspotify device ${DEVICE}"
echo "Setting PCM volume to ${VOLUME}%"

# This AB13X adapter exposes PCM, not Master.
if amixer -c "$CARD" sset PCM "${VOLUME}%" >/dev/null 2>&1; then
    echo "PCM volume set to ${VOLUME}%"
else
    echo "Could not set PCM via amixer. Available mixer output:"
    amixer -c "$CARD" || true
    echo "Continuing with librespot software volume only."
fi

alsactl store || true

mkdir -p /etc/systemd/system/raspotify.service.d

SPOTIFY_NAME="DMX Deck A"
if [ -f /etc/dmx-node.conf ]; then
    FOUND_NAME="$(grep '^SPOTIFY_NAME=' /etc/dmx-node.conf | head -n1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)"
    if [ -n "$FOUND_NAME" ]; then
        SPOTIFY_NAME="$FOUND_NAME"
    fi
fi

cat >/etc/systemd/system/raspotify.service.d/override.conf <<EOF
[Unit]
After=sound.target network-online.target
Wants=network-online.target

[Service]
ExecStartPre=/bin/sleep 8

Environment="LIBRESPOT_NAME=${SPOTIFY_NAME}"
Environment="LIBRESPOT_BACKEND=alsa"
Environment="LIBRESPOT_DEVICE=${DEVICE}"
Environment="LIBRESPOT_INITIAL_VOLUME=${VOLUME}"
Environment="LIBRESPOT_DEVICE_TYPE=speaker"
Environment="LIBRESPOT_DISCOVERY_BACKEND=avahi"
Environment="HOME=/var/lib/raspotify"
EOF

systemctl daemon-reload
systemctl restart raspotify

echo "Volume update complete"
echo "ALSA card: ${CARD}"
echo "ALSA control: PCM=${VOLUME}%"
echo "Raspotify device: ${DEVICE}"
echo "Librespot initial volume: ${VOLUME}%"
