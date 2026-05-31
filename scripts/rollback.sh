#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/opt/dttd-pi-node"
cd "$REPO_DIR"

if [[ ! -d ".git" ]]; then
  echo "Rollback unavailable: not installed from Git yet."
  exit 1
fi

git reset --hard HEAD~1
python3 -m py_compile "$REPO_DIR/agent/dmx-node-agent.py"
systemctl restart dmx-node-agent
echo "Rolled back one Git commit and restarted agent"
