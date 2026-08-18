#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/dmx-node.conf"
DISCO_HOME="/home/disco"
AUTOSTART_DIR="${DISCO_HOME}/.config/autostart"
AUTOSTART_FILE="${AUTOSTART_DIR}/dttd-display.desktop"
LABWC_AUTOSTART="${DISCO_HOME}/.config/labwc/autostart"

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
  cat > "$AUTOSTART_FILE" <<'EOF'
[Desktop Entry]
Type=Application
Name=DTTD Live Display
Comment=Start the Dance Thru The Decades HDMI live display
Exec=/usr/bin/python3 /opt/dttd-pi-node/agent/dmx-node-agent.py --display-start
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  chown -R disco:disco "$AUTOSTART_DIR"
  echo "Deck A display autostart enabled"
else
  rm -f "$AUTOSTART_FILE"
  echo "Display autostart disabled for ${NODE_KEY:-unknown node}; display controls remain available"
fi
