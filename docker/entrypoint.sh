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

# code-server hands out a shell with passwordless sudo, so it is never served
# unauthenticated unless that is asked for explicitly.
if [ -n "${PASSWORD:-}" ] || [ -n "${HASHED_PASSWORD:-}" ]; then
  CS_AUTH=password
elif [ "${CODE_SERVER_AUTH:-}" = none ]; then
  CS_AUTH=none
  echo "[entrypoint] Warning: CODE_SERVER_AUTH=none, code-server runs without authentication" >&2
else
  echo "[entrypoint] Error: PASSWORD is not set. Set PASSWORD (or HASHED_PASSWORD), or CODE_SERVER_AUTH=none to run code-server without authentication." >&2
  exit 1
fi

# Ensure directories exist
mkdir -p "$WORKSPACE_DIR" "$T3_DIR" \
  /home/coder/.claude \
  /home/coder/.gemini \
  /home/coder/.codex \
  /home/coder/.ssh \
  /home/coder/.npm-global \
  2>/dev/null || true

# Fix permissions if running with sudo/root access
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo chown -R coder:coder /home/coder/.t3 /home/coder/.claude /home/coder/.gemini /home/coder/.codex /home/coder/.config /home/coder/.ssh 2>/dev/null || true
  chmod 700 /home/coder/.ssh 2>/dev/null || true
fi

# Claude Code keeps its state in ~/.claude.json, outside the persisted ~/.claude volume:
# the real file lives on the volume and ~/.claude.json links to it.
if [ -d /home/coder/.claude ]; then
  CLAUDE_STATE=/home/coder/.claude/.claude.json
  CLAUDE_LINK=/home/coder/.claude.json
  # Claude writes through the link, so a regular file here predates it (e.g. written by the
  # installer during the image build): it only seeds a volume that has no state yet.
  if [ -f "$CLAUDE_LINK" ] && [ ! -L "$CLAUDE_LINK" ]; then
    if [ -e "$CLAUDE_STATE" ]; then
      rm -f "$CLAUDE_LINK" 2>/dev/null || true
    else
      mv "$CLAUDE_LINK" "$CLAUDE_STATE" 2>/dev/null || true
    fi
  fi
  if [ -L "$CLAUDE_LINK" ] || [ ! -e "$CLAUDE_LINK" ]; then
    ln -sfn "$CLAUDE_STATE" "$CLAUDE_LINK" 2>/dev/null || true
  fi
  # Pre-accept workspace trust dialog for Claude Code to avoid headless prompts
  WORKSPACE_DIR="$WORKSPACE_DIR" python3 - <<'EOF' 2>/dev/null || true
import json, os
p = os.path.expanduser("~/.claude/.claude.json")
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault("projects", {}).setdefault(os.environ["WORKSPACE_DIR"], {})["hasTrustDialogAccepted"] = True
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
EOF
fi

# Dynamic runtime worker installation (if specified via ENABLED_WORKERS)
if [ -n "${ENABLED_WORKERS:-}" ]; then
  IFS=',' read -ra WORKERS <<< "$ENABLED_WORKERS"
  # Expand aliases to binary names first: `command -v all` or `command -v antigravity`
  # never succeeds, which would reinstall those harnesses on every boot.
  # Keep the names in sync with harness-install.
  BINARIES=()
  for w in "${WORKERS[@]}"; do
    w=$(echo "$w" | tr '[:upper:]' '[:lower:]' | xargs)
    case "$w" in
      "") ;;
      all) BINARIES+=(claude agy codex) ;;
      agy | antigravity) BINARIES+=(agy) ;;
      claude | codex) BINARIES+=("$w") ;;
      *) echo "[entrypoint] Warning: unknown worker '$w' in ENABLED_WORKERS (supported: claude, agy, codex, all); skipping" >&2 ;;
    esac
  done
  for w in "${BINARIES[@]}"; do
    if ! command -v "$w" >/dev/null 2>&1; then
      echo "[entrypoint] Installing requested worker: $w"
      harness-install "$w" || echo "[entrypoint] Warning: installing $w failed; continuing" >&2
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
T3_LOG="$T3_DIR/t3-server.log"
# Rotate the log once it passes 10 MB so the persistent volume does not grow forever.
# Copy and truncate: t3 serve holds the log open in append mode and carries on in the emptied file.
rotate_t3_log() {
  if [ -f "$T3_LOG" ] && [ "$(stat -c %s "$T3_LOG")" -gt 10485760 ]; then
    cp -f "$T3_LOG" "$T3_LOG.1" && : > "$T3_LOG"
  fi
}
(
  while true; do
    rotate_t3_log || true
    t3 serve \
      --host "$T3_HOST" \
      --port "$T3_PORT" \
      --lan \
      --no-browser \
      --base-dir "$T3_DIR" \
      "$WORKSPACE_DIR" \
      >> "$T3_LOG" 2>&1 || echo "[entrypoint] Warning: t3 serve exited (see $T3_LOG); restarting in 5s" >&2
    sleep 5
  done
) &
# t3 serve can run for weeks without restarting, so the size is also checked while it runs
(
  while sleep 600; do
    rotate_t3_log || true
  done
) &

# Run code-server as main container process
echo "[entrypoint] Starting code-server on $CS_HOST:$CS_PORT..."
CS_ARGS=(--bind-addr "$CS_HOST:$CS_PORT")
if [ -n "${CODE_SERVER_BASE_PATH:-}" ]; then
  CS_ARGS+=(--base-path "$CODE_SERVER_BASE_PATH")
fi
CS_ARGS+=(--auth "$CS_AUTH")
CS_ARGS+=("$WORKSPACE_DIR")

exec code-server "${CS_ARGS[@]}"

