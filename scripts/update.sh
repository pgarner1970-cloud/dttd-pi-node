\
#!/bin/bash
set -eu

REPO_DIR="/opt/dttd-pi-node"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Update skipped: $REPO_DIR is not a Git checkout yet."
  echo "Convert /opt/dttd-pi-node to a Git clone before using Update Agent."
  exit 0
fi

cd "$REPO_DIR"
git fetch --all --tags
git pull --ff-only

python3 -m py_compile "$REPO_DIR/agent/dmx-node-agent.py"
chmod +x "$REPO_DIR/agent/dmx-node-agent.py"
chmod +x "$REPO_DIR/scripts/"*.sh

# Do not restart dmx-node-agent here. The agent must report command completion first.
echo "DTTD Pi node update complete. Use Restart Agent afterwards if needed."
