#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Step 04: Setup RPi #2 (grip-app — Spring Boot 3 + Mailpit)
# Waits for grip-db, builds/starts Spring Boot Backend & Mailpit SMTP
# Usage: sudo bash scripts/04-setup-node-app.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

DB_HOST="${GRIP_DB_HOST:-192.168.0.23}"
DB_PORT="${GRIP_DB_PORT:-5432}"

log_info "Checking reachability of Database Node (${DB_HOST}:${DB_PORT})..."
wait_for_tcp "${DB_HOST}" "${DB_PORT}" 40 3 || log_warn "Proceeding with startup; Spring Boot / Docker will retry connection."

log_info "Building & starting Spring Boot Backend + Mailpit on $(hostname)..."
cd "${GRIP_REPO_DIR}/docker"
docker compose --env-file "${GRIP_ENV_FILE}" -f docker-compose.app.yml up -d --build

log_info "Waiting for Spring Boot API on port ${GRIP_BACKEND_PORT:-8080}..."
wait_for_tcp "127.0.0.1" "${GRIP_BACKEND_PORT:-8080}" 45 3

# Prune dangling build layers to keep 32GB microSD clean
docker image prune -f >/dev/null 2>&1 || true

log_ok "RPi #2 (grip-app) is UP! Backend API: :${GRIP_BACKEND_PORT:-8080} | Mailpit UI: :${GRIP_MAILPIT_UI_PORT:-8025}"
