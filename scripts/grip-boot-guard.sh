#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Boot Guard & Repositioning Self-Healing Watchdog
# Invoked on boot (grip-node.service) and every 2 minutes (grip-watchdog.timer)
# Handles power-on after unplugging/moving Raspberry Pis to a new court
# Usage: sudo bash scripts/grip-boot-guard.sh [--start | --watchdog]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

MODE="${1:---start}"
ROLE="${GRIP_NODE_ROLE:-edge}"

# 1. Ensure Avahi mDNS daemon is active so .local hostnames resolve across the switch/Wi-Fi
if ! systemctl is-active --quiet avahi-daemon; then
  log_warn "avahi-daemon not active; restarting..."
  systemctl restart avahi-daemon || true
fi

# 2. Ensure Docker daemon is active
if ! systemctl is-active --quiet docker; then
  log_warn "Docker daemon not active; starting..."
  systemctl start docker
fi

start_assigned_role() {
  case "${ROLE}" in
    db)
      bash "${GRIP_REPO_DIR}/scripts/03-setup-node-db.sh"
      ;;
    app)
      bash "${GRIP_REPO_DIR}/scripts/04-setup-node-app.sh"
      ;;
    edge)
      bash "${GRIP_REPO_DIR}/scripts/05-setup-node-edge.sh"
      ;;
    all-in-one)
      bash "${GRIP_REPO_DIR}/scripts/06-setup-node-all-in-one.sh"
      ;;
    kiosk)
      systemctl restart grip-kiosk.service || true
      ;;
    *)
      log_error "Unknown GRIP_NODE_ROLE: ${ROLE}"
      exit 1
      ;;
  esac
}

if [[ "${MODE}" == "--start" ]]; then
  log_info "Boot Guard starting role '${ROLE}' on $(hostname)..."
  start_assigned_role
  exit 0
fi

# Watchdog mode: verify that expected containers/endpoints are healthy
if [[ "${MODE}" == "--watchdog" ]]; then
  case "${ROLE}" in
    db)
      if ! docker exec grip-db pg_isready -U "${GRIP_DB_USER:-grip}" -d "${GRIP_DB_NAME:-gripdb}" >/dev/null 2>&1; then
        log_warn "Watchdog: grip-db unhealthy or stopped. Restarting DB stack..."
        start_assigned_role
      fi
      ;;
    app)
      if ! timeout 3 bash -c "</dev/tcp/127.0.0.1/${GRIP_BACKEND_PORT:-8080}" 2>/dev/null; then
        log_warn "Watchdog: grip-backend not responding on :${GRIP_BACKEND_PORT:-8080}. Restarting App stack..."
        start_assigned_role
      fi
      ;;
    edge)
      if ! timeout 3 bash -c "</dev/tcp/127.0.0.1/${GRIP_WEB_PORT:-80}" 2>/dev/null || \
         ! timeout 3 bash -c "</dev/tcp/127.0.0.1/${GRIP_LIVESYNC_PORT:-5500}" 2>/dev/null; then
        log_warn "Watchdog: grip-edge (Nginx or Live-Sync) not responding. Healing Edge stack..."
        start_assigned_role
      fi
      ;;
    all-in-one)
      if ! timeout 3 bash -c "</dev/tcp/127.0.0.1/${GRIP_WEB_PORT:-80}" 2>/dev/null || \
         ! timeout 3 bash -c "</dev/tcp/127.0.0.1/${GRIP_BACKEND_PORT:-8080}" 2>/dev/null; then
        log_warn "Watchdog: All-in-One stack unhealthy. Healing..."
        start_assigned_role
      fi
      ;;
  esac
fi
