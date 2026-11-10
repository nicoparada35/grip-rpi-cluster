#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Step 03: Setup RPi #3 (grip-db — PostgreSQL 16 + Backups)
# Starts PostgreSQL 16 ARM64 and verifies readiness
# Usage: sudo bash scripts/03-setup-node-db.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

log_info "Starting GRIP Database Node (PostgreSQL 16 ARM64) on $(hostname)..."

cd "${GRIP_REPO_DIR}/docker"
docker compose --env-file "${GRIP_ENV_FILE}" -f docker-compose.db.yml up -d

log_info "Waiting for PostgreSQL container healthcheck..."
for ((i=1; i<=30; i++)); do
  if docker exec grip-db pg_isready -U "${GRIP_DB_USER:-grip}" -d "${GRIP_DB_NAME:-gripdb}" >/dev/null 2>&1; then
    log_ok "PostgreSQL 16 is UP and accepting connections on port ${GRIP_DB_PORT:-5432}!"
    exit 0
  fi
  sleep 2
done

log_error "PostgreSQL did not become healthy in time. Checking container logs:"
docker logs --tail 50 grip-db
exit 1
