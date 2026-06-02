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

find_usb_card() {
    # Prefer the known Sabrent/AB13X adapter where present.
    aplay -l 2>/dev/null | awk '/AB13X USB Audio/ {gsub("card ","",$2); gsub(":","",$2); print $2; exit}'
}

CARD="$(find_usb_card)"

if [ -z "$CARD" ]; then
    CARD="$(aplay -l 2>/dev/null | awk '/^card [0-9]+:/ && /USB|usb|Audio|audio/ {gsub("card ","",$2); gsub(":","",$2); print $2; exit}')"
fi

if [ -z "$CARD" ]; then
    echo "USB audio device not found"
    aplay -l || true
    exit 1
fi

echo "Using ALSA card ${CARD}"
echo "Requested volume: ${VOLUME}%"

CONTROLS="$(amixer -c "$CARD" scontrols 2>/dev/null | sed -n "s/^Simple mixer control '\([^']*\)'.*/\1/p")"

if [ -z "$CONTROLS" ]; then
    echo "No mixer controls found for ALSA card ${CARD}"
    amixer -c "$CARD" || true
    exit 1
fi

# Different USB audio adapters expose different mixer names.
# Sabrent/AB13X units commonly expose Speaker, while others expose PCM.
for CONTROL in PCM Speaker Headphone Master Line Playback; do
    if echo "$CONTROLS" | grep -Fxq "$CONTROL"; then
        echo "Setting ${CONTROL} volume to ${VOLUME}%"
        if amixer -c "$CARD" sset "$CONTROL" "${VOLUME}%" >/dev/null 2>&1; then
            alsactl store || true
            echo "Volume update complete"
            echo "ALSA card: ${CARD}"
            echo "ALSA control: ${CONTROL}=${VOLUME}%"
            exit 0
        fi
    fi
done

echo "Could not find a supported playback mixer control for ALSA card ${CARD}."
echo "Available mixer controls:"
printf '%s\n' "$CONTROLS"
amixer -c "$CARD" || true
exit 1
