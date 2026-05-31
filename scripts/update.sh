#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/opt/dttd-pi-node"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "Update skipped: $REPO_DIR is not a Git checkout yet."
  echo "For now, upload/copy files manually or install from Git later."
  exit 0
fi

cd "$REPO_DIR"
git fetch --all --tags
git pull --ff-only

python3 -m py_compile "$REPO_DIR/agent/dmx-node-agent.py"
cp "$REPO_DIR/systemd/dmx-node-agent.service" /etc/systemd/system/dmx-node-agent.service
chmod +x "$REPO_DIR/agent/dmx-node-agent.py"
chmod +x "$REPO_DIR/scripts/"*.sh

systemctl daemon-reload
systemctl restart dmx-node-agent

echo "DTTD Pi node update complete"
