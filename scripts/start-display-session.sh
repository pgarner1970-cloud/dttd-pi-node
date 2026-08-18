#!/usr/bin/env bash
set -euo pipefail

# Ensure an X11 graphical session is available before Chromium is launched.
# Deck A normally already has one. Deck B normally boots to multi-user.target,
# so this starts graphical.target on demand without changing its default target.

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script with sudo"
  exit 1
fi

DISCO_UID="$(id -u disco)"
DISCO_RUNTIME="/run/user/${DISCO_UID}"

if [[ -S /tmp/.X11-unix/X0 && -d "$DISCO_RUNTIME" ]]; then
  echo "Graphical display session is already available"
  exit 0
fi

systemctl start graphical.target

# The display manager can create X :0 slightly before the disco autologin
# session and its runtime directory are ready, so wait for both.
for _ in $(seq 1 60); do
  if [[ -S /tmp/.X11-unix/X0 && -d "$DISCO_RUNTIME" ]]; then
    echo "Graphical display session is ready"
    exit 0
  fi
  sleep 1
done

echo "Timed out waiting for the disco graphical session on X11 display :0" >&2
exit 1
