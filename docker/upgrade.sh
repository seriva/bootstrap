#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# upgrade.sh: In-Place Agent Upgrader
# Dual-mode script: runs on the host (delegating via docker compose) or directly
# inside the container to upgrade tools, harnesses, and skills without resetting state.
# ==============================================================================

run_in_container() {
  export PATH="/home/coder/.npm-global/bin:/home/coder/.local/bin:/home/coder/.antigravity/bin:${PATH}"
  export T3CODE_HOME="/home/coder/.t3"
  export NPM_CONFIG_PREFIX="/home/coder/.npm-global"

  echo "[$(date -Is)] Upgrading agent environment inside container..."

  # 1. System packages
  echo "--> Updating system apt packages..."
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    sudo apt-get clean
    sudo rm -rf /var/lib/apt/lists/*
  fi

  # 2. T3 Code CLI & server
  echo "--> Updating T3 Code orchestrator..."
  if command -v sudo >/dev/null 2>&1; then
    sudo T3CODE_HOME=/opt/t3 T3CODE_INSTALL_BIN_DIR=/usr/local/bin sh -c 'curl -fsSL https://t3.codes/install.sh | sh' && sudo chmod -R 755 /opt/t3
  else
    T3CODE_HOME=/opt/t3 T3CODE_INSTALL_BIN_DIR=/usr/local/bin sh -c 'curl -fsSL https://t3.codes/install.sh | sh'
  fi

  # 3. Active worker harnesses
  echo "--> Updating installed worker harnesses..."
  # Upgrade all harnesses that exist on PATH or were requested
  DETECTED_WORKERS=()
  command -v claude >/dev/null 2>&1 && DETECTED_WORKERS+=("claude")
  command -v agy >/dev/null 2>&1 && DETECTED_WORKERS+=("agy")
  command -v codex >/dev/null 2>&1 && DETECTED_WORKERS+=("codex")
  command -v opencode >/dev/null 2>&1 && DETECTED_WORKERS+=("opencode")
  command -v pi >/dev/null 2>&1 && DETECTED_WORKERS+=("pi")

  if [ ${#DETECTED_WORKERS[@]} -gt 0 ]; then
    harness-install "${DETECTED_WORKERS[@]}"
  fi

  # 4. Global npm packages
  if command -v npm >/dev/null 2>&1; then
    echo "--> Updating global npm packages..."
    npm update -g --prefix /home/coder/.npm-global 2>/dev/null || true
  fi

  # 5. Bootstrap skills
  if [ -x "/opt/bootstrap/install.sh" ]; then
    echo "--> Refreshing bootstrap skills..."
    /opt/bootstrap/install.sh
  fi

  # 6. Restart background daemons so entrypoint loop restarts them with new binaries
  echo "--> Refreshing background daemons..."
  pkill -f "t3 serve" 2>/dev/null || true

  echo "[$(date -Is)] Agent upgrade completed successfully."
}

run_on_host() {
  local script_path="${BASH_SOURCE[0]}"
  local stack_dir
  stack_dir="$(cd "$(dirname "$script_path")" && pwd)"
  cd "$stack_dir"

  echo "[$(date -Is)] Starting agent upgrade in ${stack_dir}..."

  if ! docker compose ps --services --filter "status=running" 2>/dev/null | grep -qx "agent"; then
    echo "Container 'agent' is not running. Starting container..."
    docker compose up -d
    sleep 5
  fi

  # Stream script into running container to execute without requiring image rebuild
  docker compose exec -T -u coder agent bash -s -- --in-container < "$script_path"

  echo "[$(date -Is)] Agent upgrade process finished on host."
}

# Determine execution context: container or host
if [[ "${1:-}" == "--in-container" ]] || [[ -f /.dockerenv ]]; then
  run_in_container
else
  run_on_host
fi

