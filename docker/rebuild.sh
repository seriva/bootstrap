#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# rebuild.sh: Full Clean Rebuild of the Agent Container
# Pulls latest base images, rebuilds without cache, recreates the container,
# and cleans up intermediate images.
# ==============================================================================

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${STACK_DIR}"

echo "[$(date -Is)] Starting clean agent container rebuild in ${STACK_DIR}..."

# Pull base images and rebuild without cache to fetch latest CLIs and packages
docker compose build --pull --no-cache

# Recreate container with the newly built image
docker compose up -d --force-recreate

# Prune untagged intermediate images to keep disk clean
docker image prune -f

echo "[$(date -Is)] Agent rebuild completed successfully."

