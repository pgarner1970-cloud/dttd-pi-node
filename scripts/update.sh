#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/opt/dttd-pi-node"
BRANCH="${DTTD_PI_BRANCH:-main}"
REMOTE="${DTTD_PI_REMOTE:-origin}"
BACKUP_ROOT="/var/backups/dttd-pi-node"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"
LOG_FILE="/var/log/dttd-pi-node-update.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

fail() {
  log "ERROR: $*"
  exit 1
}

if [[ ! -d "$REPO_DIR/.git" ]]; then
  fail "Update skipped: $REPO_DIR is not a Git checkout. Reinstall/clone the Pi node repo first."
fi

mkdir -p "$BACKUP_ROOT"
touch "$LOG_FILE"

cd "$REPO_DIR"

log "Starting DTTD Pi node update in $REPO_DIR"
log "Target: ${REMOTE}/${BRANCH}"

# The update command normally runs via sudo from the agent. Git may otherwise
# reject a repository owned by the disco user as 'dubious ownership'.
git config --global --add safe.directory "$REPO_DIR" >/dev/null 2>&1 || true

CURRENT_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
log "Current HEAD: $CURRENT_HEAD"

# Keep a recovery copy of anything local before forcing the appliance checkout
# back to GitHub. Runtime identity/config belongs in /etc/dmx-node.conf, not in
# the repo, so the repo should be disposable on deployed nodes.
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  mkdir -p "$BACKUP_DIR"
  log "Local repo changes detected. Backing up to $BACKUP_DIR"
  git status --short > "$BACKUP_DIR/git-status.txt" || true
  git diff > "$BACKUP_DIR/local-changes.patch" || true
  git diff --cached > "$BACKUP_DIR/staged-changes.patch" || true
  git ls-files --others --exclude-standard > "$BACKUP_DIR/untracked-files.txt" || true
  if [[ -s "$BACKUP_DIR/untracked-files.txt" ]]; then
    tar -czf "$BACKUP_DIR/untracked-files.tar.gz" -T "$BACKUP_DIR/untracked-files.txt" 2>/dev/null || true
  fi
fi

log "Fetching latest code"
git fetch --prune "$REMOTE" "$BRANCH"

TARGET_REF="${REMOTE}/${BRANCH}"
TARGET_HEAD="$(git rev-parse --short "$TARGET_REF")"
log "Target HEAD: $TARGET_HEAD"

log "Resetting appliance checkout to $TARGET_REF"
git reset --hard "$TARGET_REF"

# Remove ignored/runtime files such as __pycache__ and .pyc files.
git clean -fdX

log "Validating Python agent"
python3 -m py_compile "$REPO_DIR/agent/dmx-node-agent.py"

log "Applying executable permissions"
chmod +x "$REPO_DIR/agent/dmx-node-agent.py"
find "$REPO_DIR/scripts" -type f -name '*.sh' -exec chmod +x {} \;

# Refresh installed service file if it changed in Git.
if [[ -f "$REPO_DIR/systemd/dmx-node-agent.service" ]]; then
  cp "$REPO_DIR/systemd/dmx-node-agent.service" /etc/systemd/system/dmx-node-agent.service
  systemctl daemon-reload
fi

NEW_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
log "DTTD Pi node update complete: $CURRENT_HEAD -> $NEW_HEAD"

echo "Update complete: $CURRENT_HEAD -> $NEW_HEAD"
if [[ -d "$BACKUP_DIR" ]]; then
  echo "Local changes were backed up to: $BACKUP_DIR"
fi
