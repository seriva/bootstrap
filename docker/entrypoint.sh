#!/usr/bin/env bash
set -e

# ==============================================================================
# entrypoint.sh: bootstrap Agent Container Entrypoint
# Starts T3 Code (orchestrator) in background and code-server on configurable ports.
# ==============================================================================

WORKSPACE_DIR="${WORKSPACE_DIR:-/home/coder/workspace}"
T3_DIR="${T3CODE_HOME:-/home/coder/.t3}"
T3_HOST="${T3_HOST:-0.0.0.0}"
T3_PORT="${T3_PORT:-8011}"
CS_HOST="${CODE_SERVER_HOST:-0.0.0.0}"
CS_PORT="${CODE_SERVER_PORT:-8080}"

# Ensure directories exist
mkdir -p "$WORKSPACE_DIR" "$T3_DIR" \
  /home/coder/.claude \
  /home/coder/.gemini \
  /home/coder/.codex \
  /home/coder/.config/opencode \
  /home/coder/.pi \
  /home/coder/.ssh \
  /home/coder/.npm-global \
  2>/dev/null || true

# Fix permissions if running with sudo/root access
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo chown -R coder:coder /home/coder/.t3 /home/coder/.claude /home/coder/.gemini /home/coder/.codex /home/coder/.config /home/coder/.pi /home/coder/.ssh 2>/dev/null || true
  chmod 700 /home/coder/.ssh 2>/dev/null || true
fi

# Pre-accept workspace trust dialog for Claude Code to avoid headless prompts
if [ -d /home/coder/.claude ]; then
  python3 - <<'EOF' 2>/dev/null || true
import json, os
p = os.path.expanduser("~/.claude/.claude.json")
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault("projects", {}).setdefault("/home/coder/workspace", {})["hasTrustDialogAccepted"] = True
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
EOF
  if [ ! -L /home/coder/.claude.json ] && [ ! -f /home/coder/.claude.json ]; then
    ln -sfn /home/coder/.claude/.claude.json /home/coder/.claude.json 2>/dev/null || true
  fi
fi

# Dynamic runtime worker installation (if specified via ENABLED_WORKERS)
if [ -n "${ENABLED_WORKERS:-}" ]; then
  IFS=',' read -ra WORKERS <<< "$ENABLED_WORKERS"
  for w in "${WORKERS[@]}"; do
    w=$(echo "$w" | tr '[:upper:]' '[:lower:]' | xargs)
    if [ -n "$w" ] && ! command -v "$w" >/dev/null 2>&1; then
      echo "[entrypoint] Installing requested worker: $w"
      harness-install "$w" 2>/dev/null || true
    fi
  done
fi

# Ensure bootstrap skills are linked to all active harnesses
if [ -x "/opt/bootstrap/install.sh" ]; then
  /opt/bootstrap/install.sh >/dev/null 2>&1 || true
fi

# Default Git author config if none exists
if [ -z "$(git config --global user.name 2>/dev/null || true)" ]; then
  git config --global user.name "${GIT_USER_NAME:-Agent}"
fi
if [ -z "$(git config --global user.email 2>/dev/null || true)" ]; then
  git config --global user.email "${GIT_USER_EMAIL:-agent@bootstrap.local}"
fi

# Start T3 Code daemon in background (orchestrator)
echo "[entrypoint] Starting T3 Code web orchestrator on $T3_HOST:$T3_PORT..."
(
  while true; do
    # Rotate the log once it passes 10 MB so the persistent volume does not grow forever
    if [ -f "$T3_DIR/t3-server.log" ] && [ "$(stat -c %s "$T3_DIR/t3-server.log")" -gt 10485760 ]; then
      mv -f "$T3_DIR/t3-server.log" "$T3_DIR/t3-server.log.1"
    fi
    t3 serve \
      --host "$T3_HOST" \
      --port "$T3_PORT" \
      --lan \
      --no-browser \
      --base-dir "$T3_DIR" \
      --auto-bootstrap-project-from-cwd "$WORKSPACE_DIR" \
      >> "$T3_DIR/t3-server.log" 2>&1 || true
    sleep 5
  done
) &

# Run code-server as main container process
echo "[entrypoint] Starting code-server on $CS_HOST:$CS_PORT..."
CS_ARGS=(--bind-addr "$CS_HOST:$CS_PORT")
if [ -n "${CODE_SERVER_BASE_PATH:-}" ]; then
  CS_ARGS+=(--base-path "$CODE_SERVER_BASE_PATH")
fi
if [ -n "${PASSWORD:-}" ]; then
  CS_ARGS+=(--auth password)
else
  CS_ARGS+=(--auth none)
fi
CS_ARGS+=("$WORKSPACE_DIR")

exec code-server "${CS_ARGS[@]}"

