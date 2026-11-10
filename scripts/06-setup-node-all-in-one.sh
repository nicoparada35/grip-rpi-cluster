#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Step 06: Setup All-in-One Node (Single RPi 4B Portable Mode)
# Runs PostgreSQL + Spring Boot + Mailpit + Live-Sync + Nginx on 1 Raspberry Pi
# Usage: sudo bash scripts/06-setup-node-all-in-one.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

log_info "Building & starting All-in-One GRIP Stack on $(hostname)..."
chown -R 70:70 "${GRIP_POSTGRES_DIR}" 2>/dev/null || true
chmod 777 "${GRIP_POSTGRES_DIR}"
cd "${GRIP_REPO_DIR}/docker"
docker compose --env-file "${GRIP_ENV_FILE}" -f docker-compose.all-in-one.yml up -d --build

wait_for_tcp "127.0.0.1" "${GRIP_DB_PORT:-5432}" 30 2
wait_for_tcp "127.0.0.1" "${GRIP_BACKEND_PORT:-8080}" 45 3
wait_for_tcp "127.0.0.1" "${GRIP_WEB_PORT:-80}" 20 2

docker image prune -f >/dev/null 2>&1 || true
log_ok "All-in-One GRIP Node is UP at http://$(hostname).local !"
