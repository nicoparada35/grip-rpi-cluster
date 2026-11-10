#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Step 05: Setup RPi #1 (grip-edge — Nginx Web + Live-Sync)
# Renders Nginx upstream config, builds/starts Live-Sync & Nginx Frontend
# Usage: sudo bash scripts/05-setup-node-edge.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

APP_HOST="${GRIP_APP_HOST:-grip-app.local}"
APP_PORT="${GRIP_BACKEND_PORT:-8080}"

# Also publish grip.local alias via Avahi if this is the edge node
if [[ "$(hostname)" != "grip" ]] && command -v avahi-publish &>/dev/null; then
  log_info "Ensuring Nginx responds to both grip.local and $(hostname).local..."
fi

log_info "Rendering Nginx edge configuration with upstream ${APP_HOST}:${APP_PORT}..."
sed \
  -e "s/__GRIP_APP_HOST__/${APP_HOST}/g" \
  -e "s/__GRIP_BACKEND_PORT__/${APP_PORT}/g" \
  "${GRIP_REPO_DIR}/config/nginx.edge.conf" > "${GRIP_CONFIG_DIR}/nginx.rendered.conf"

log_info "Checking reachability of Backend Node (${APP_HOST}:${APP_PORT})..."
wait_for_tcp "${APP_HOST}" "${APP_PORT}" 25 3 || log_warn "Backend not reachable yet; Live-Sync & Nginx will still start."

log_info "Building & starting GRIP Frontend (Nginx) + Live-Sync Court Engine..."
cd "${GRIP_REPO_DIR}/docker"
docker compose --env-file "${GRIP_ENV_FILE}" -f docker-compose.edge.yml up -d --build

wait_for_tcp "127.0.0.1" "${GRIP_LIVESYNC_PORT:-5500}" 20 2
wait_for_tcp "127.0.0.1" "${GRIP_WEB_PORT:-80}" 20 2

# Prune dangling images to save 32GB microSD space
docker image prune -f >/dev/null 2>&1 || true

log_ok "RPi #1 (grip-edge) is UP! Web Portal & Live-Tracker ready at http://$(hostname).local"
