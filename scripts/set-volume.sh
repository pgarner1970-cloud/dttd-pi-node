\
#!/usr/bin/env bash
set -euo pipefail

VOLUME="${1:-85}"
if ! [[ "$VOLUME" =~ ^[0-9]+$ ]]; then
  echo "Volume must be 0-100"
  exit 1
fi
if [[ "$VOLUME" -gt 100 ]]; then VOLUME=100; fi

echo "Setting node volume target to ${VOLUME}%"

CARD="$(aplay -l 2>/dev/null | sed -n 's/^card \([0-9][0-9]*\): Audio \[AB13X USB Audio\].*/\1/p' | head -n1)"
if [[ -z "$CARD" ]]; then
  CARD="$(aplay -l 2>/dev/null | awk '/^card [0-9]+:/ && /USB|usb|Audio|audio/ {gsub("card ","",$2); gsub(":","",$2); print $2; exit}')"
fi

if [[ -z "$CARD" ]]; then
  echo "No USB audio card found."
  aplay -l || true
  exit 1
fi

DEVICE="plughw:${CARD},0"
echo "Using ALSA device ${DEVICE}"

changed=0
for CONTROL in Master PCM Speaker Headphone Playback; do
  if amixer -c "$CARD" sset "$CONTROL" "${VOLUME}%" >/dev/null 2>&1; then
    echo "Set ${CONTROL} to ${VOLUME}%"
    changed=1
  fi
done

alsactl store || true

OVERRIDE_DIR="/etc/systemd/system/raspotify.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
mkdir -p "$OVERRIDE_DIR"

SPOTIFY_NAME="DMX Deck A"
if [[ -f /etc/dmx-node.conf ]]; then
  SPOTIFY_NAME="$(grep '^SPOTIFY_NAME=' /etc/dmx-node.conf | head -n1 | cut -d= -f2- | sed 's/^"//;s/"$//')"
  if [[ -z "$SPOTIFY_NAME" ]]; then SPOTIFY_NAME="DMX Deck A"; fi
fi

cat >"$OVERRIDE_FILE" <<EOF
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

echo "Volume command complete."
echo "ALSA device: ${DEVICE}"
echo "Librespot initial volume: ${VOLUME}%"
if [[ "$changed" -eq 0 ]]; then
  echo "Note: this USB adapter exposes no standard amixer controls; applied ALSA store and librespot software volume."
fi
