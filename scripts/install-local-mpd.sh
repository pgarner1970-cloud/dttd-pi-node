#!/usr/bin/env bash
set -euo pipefail

MUSIC_DIR="${DTTD_LOCAL_MUSIC_DIR:-/mnt/dttd-music}"
ALSA_DEVICE="${DTTD_LOCAL_ALSA_DEVICE:-hw:1,0}"
MIXER_DEVICE="${DTTD_LOCAL_MIXER_DEVICE:-hw:1}"
MIXER_CONTROL="${DTTD_LOCAL_MIXER_CONTROL:-Speaker}"
CONF="/etc/mpd.conf"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script with sudo/root"
  exit 1
fi

echo "Installing/configuring MPD local playback"
echo "Music directory: ${MUSIC_DIR}"
echo "ALSA output: ${ALSA_DEVICE}"

apt-get update
apt-get install -y mpd mpc alsa-utils

mkdir -p /var/lib/mpd/playlists /var/log/mpd /run/mpd
chown -R mpd:audio /var/lib/mpd /var/log/mpd || true
usermod -a -G audio mpd || true

if [[ -f "${CONF}" && ! -f "${CONF}.dttd-original" ]]; then
  cp "${CONF}" "${CONF}.dttd-original"
fi
cp -f "${CONF}" "${CONF}.bak-${STAMP}" 2>/dev/null || true

cat >"${CONF}" <<EOF
# DTTD local music MPD configuration
music_directory         "${MUSIC_DIR}"
playlist_directory      "/var/lib/mpd/playlists"
db_file                 "/var/lib/mpd/tag_cache"
log_file                "/var/log/mpd/mpd.log"
pid_file                "/run/mpd/pid"
state_file              "/var/lib/mpd/state"
sticker_file            "/var/lib/mpd/sticker.sql"

user                    "mpd"
bind_to_address         "localhost"
port                    "6600"
restore_paused          "yes"
auto_update             "yes"
filesystem_charset      "UTF-8"

input {
        plugin          "curl"
}

audio_output {
        type            "alsa"
        name            "DTTD USB Audio"
        device          "${ALSA_DEVICE}"
        mixer_type      "hardware"
        mixer_device    "${MIXER_DEVICE}"
        mixer_control   "${MIXER_CONTROL}"
}
EOF

systemctl daemon-reload
systemctl enable mpd
systemctl restart mpd

# Set the USB speaker volume if the expected control exists.
amixer -c "${MIXER_DEVICE#hw:}" sset "${MIXER_CONTROL}" 90% >/dev/null 2>&1 || true
amixer -c "${MIXER_DEVICE#hw:}" sset "${MIXER_CONTROL}" unmute >/dev/null 2>&1 || true

# Trigger an initial scan if the music mount is available. Do not fail the
# installer if the event SSD/share is currently offline.
if [[ -d "${MUSIC_DIR}" ]]; then
  mpc update >/dev/null 2>&1 || true
fi

echo "MPD local playback setup complete."
