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

echo "Using ALSA card ${CARD}"
echo "Setting live PCM volume to ${VOLUME}%"

# Do not restart Raspotify here. This is a live mixer-level volume change.
if amixer -c "$CARD" sset PCM "${VOLUME}%" >/dev/null 2>&1; then
    echo "PCM volume set to ${VOLUME}%"
else
    echo "Could not set PCM via amixer. Available mixer output:"
    amixer -c "$CARD" || true
    exit 1
fi

alsactl store || true

echo "Volume update complete"
echo "ALSA card: ${CARD}"
echo "ALSA control: PCM=${VOLUME}%"
