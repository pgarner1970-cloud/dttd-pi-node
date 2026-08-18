#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/dmx-node.conf"
DISCO_HOME="/home/disco"
AUTOSTART_DIR="${DISCO_HOME}/.config/autostart"
AUTOSTART_FILE="${AUTOSTART_DIR}/dttd-display.desktop"
LABWC_AUTOSTART="${DISCO_HOME}/.config/labwc/autostart"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script with sudo"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing $CONFIG_FILE"
  exit 1
fi

NODE_KEY="$(awk -F= '$1=="NODE_KEY"{print $2}' "$CONFIG_FILE" | tail -n1 | tr -d '\r\"\047 ' )"

# Remove legacy direct Chromium launch lines if they were previously used for
# the DTTD display. Do not touch unrelated browser/autostart entries.
if [[ -f "$LABWC_AUTOSTART" ]]; then
  cp "$LABWC_AUTOSTART" "${LABWC_AUTOSTART}.dttd-backup" 2>/dev/null || true
  sed -i '/chromium.*live\.dancethruthedecades\.co\.uk/d;/dttd-display-chromium/d' "$LABWC_AUTOSTART"
fi

mkdir -p "$AUTOSTART_DIR"

if [[ "$NODE_KEY" == "dmx-desk-a" ]]; then
  # Deck A is the primary HDMI display. Boot the desktop and launch the DTTD
  # display as soon as the disco desktop session starts.
  systemctl set-default graphical.target >/dev/null
  cat > "$AUTOSTART_FILE" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=DTTD Live Display
Comment=Start the Dance Thru The Decades HDMI live display
Exec=/usr/bin/python3 /opt/dttd-pi-node/agent/dmx-node-agent.py --display-start
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP
  chown -R disco:disco "$AUTOSTART_DIR"
  echo "Deck A: graphical boot and automatic DTTD display enabled"
elif [[ "$NODE_KEY" == "dmx-desk-b" ]]; then
  # Deck B is the lower-powered backup display. Keep it headless after reboot;
  # Start Display can bring graphical.target up temporarily when required.
  rm -f "$AUTOSTART_FILE"
  systemctl set-default multi-user.target >/dev/null
  echo "Deck B: headless boot enabled; display remains available on demand"
else
  rm -f "$AUTOSTART_FILE"
  echo "Unknown node ${NODE_KEY:-unset}: removed automatic DTTD display launch; boot target unchanged"
fi
