#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Master Installer for Any Raspberry Pi 4B Node
# Orchestrates OS provisioning, directory creation, submodule installation,
# service startup, boot persistence, and Continuous Deployment (CD).
#
# Usage:
#   sudo bash scripts/install-node.sh --role <db|app|edge|all-in-one|kiosk> [options]
#
# Options:
#   --role <role>         Assigned role for this Raspberry Pi (required)
#   --hostname <name>     Custom mDNS hostname (default: grip-<role>)
#   --db-host <host>      Database hostname/IP (default: grip-db.local)
#   --app-host <host>     Backend App hostname/IP (default: grip-app.local)
#   --edge-host <host>    Edge Web hostname/IP (default: grip-edge.local)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root

ROLE=""
CUSTOM_HOSTNAME=""
ARG_DB_HOST=""
ARG_APP_HOST=""
ARG_EDGE_HOST=""

usage() {
  cat <<EOF
Usage: sudo bash $0 --role <db|app|edge|all-in-one|kiosk> [options]

Roles (Recommended 3-Pi Topology out of your 5 Raspberry Pi 4Bs):
  db          RPi #3 (grip-db.local)   — PostgreSQL 16 ARM64 + Daily Auto-Backups
  app         RPi #2 (grip-app.local)  — Spring Boot 3 Backend API + Mailpit SMTP
  edge        RPi #1 (grip-edge.local) — Nginx Reverse Proxy + Static Web + Live-Sync 3x3
  all-in-one  Single-RPi Portable Mode — Runs DB + App + Edge on 1 Raspberry Pi 4B
  kiosk       Optional RPi #4          — HDMI Fullscreen Court Scoreboard & Live-Tracker

Options:
  --hostname <name>     Override hostname (default: grip-<role>)
  --db-host <host>      Override GRIP_DB_HOST (default: grip-db.local)
  --app-host <host>     Override GRIP_APP_HOST (default: grip-app.local)
  --edge-host <host>    Override GRIP_EDGE_HOST (default: grip-edge.local)
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)      ROLE="${2:-}"; shift 2 ;;
    --hostname)  CUSTOM_HOSTNAME="${2:-}"; shift 2 ;;
    --db-host)   ARG_DB_HOST="${2:-}"; shift 2 ;;
    --app-host)  ARG_APP_HOST="${2:-}"; shift 2 ;;
    --edge-host) ARG_EDGE_HOST="${2:-}"; shift 2 ;;
    -h|--help)   usage ;;
    *)           log_error "Unknown argument: $1"; usage ;;
  esac
done

if [[ -z "${ROLE}" ]]; then
  log_error "Missing required --role argument."
  usage
fi

case "${ROLE}" in
  db)         DEFAULT_HOSTNAME="grip-db" ;;
  app)        DEFAULT_HOSTNAME="grip-app" ;;
  edge)       DEFAULT_HOSTNAME="grip-edge" ;;
  all-in-one) DEFAULT_HOSTNAME="grip" ;;
  kiosk)      DEFAULT_HOSTNAME="grip-kiosk" ;;
  *)          log_error "Invalid role '${ROLE}'. Choose: db, app, edge, all-in-one, kiosk"; exit 1 ;;
esac

FINAL_HOSTNAME="${CUSTOM_HOSTNAME:-${DEFAULT_HOSTNAME}}"

log_info "=================================================================="
log_info " GRIP Basketball — Installing Node Role: ${ROLE} (${FINAL_HOSTNAME}.local)"
log_info "=================================================================="

# Step 1: Install Code, Submodules & Create Directories
bash "${SCRIPT_DIR}/02-install-code.sh" "${ROLE}"

# Apply CLI overrides to /opt/grip/config/cluster.env
sed -i "s/^GRIP_NODE_ROLE=.*/GRIP_NODE_ROLE=${ROLE}/" "${GRIP_ENV_FILE}"
sed -i "s/^GRIP_NODE_HOSTNAME=.*/GRIP_NODE_HOSTNAME=${FINAL_HOSTNAME}/" "${GRIP_ENV_FILE}"
[[ -n "${ARG_DB_HOST}" ]]   && sed -i "s/^GRIP_DB_HOST=.*/GRIP_DB_HOST=${ARG_DB_HOST}/" "${GRIP_ENV_FILE}"
[[ -n "${ARG_APP_HOST}" ]]  && sed -i "s/^GRIP_APP_HOST=.*/GRIP_APP_HOST=${ARG_APP_HOST}/" "${GRIP_ENV_FILE}"
[[ -n "${ARG_EDGE_HOST}" ]] && sed -i "s/^GRIP_EDGE_HOST=.*/GRIP_EDGE_HOST=${ARG_EDGE_HOST}/" "${GRIP_ENV_FILE}"

# Step 2: Provision Base OS, Docker ARM64, Swap & SD Card Protection
bash "${GRIP_REPO_DIR}/scripts/01-provision-os.sh" "${FINAL_HOSTNAME}"

# Step 3: Run Role-Specific Service Setup
case "${ROLE}" in
  db)         bash "${GRIP_REPO_DIR}/scripts/03-setup-node-db.sh" ;;
  app)        bash "${GRIP_REPO_DIR}/scripts/04-setup-node-app.sh" ;;
  edge)       bash "${GRIP_REPO_DIR}/scripts/05-setup-node-edge.sh" ;;
  all-in-one) bash "${GRIP_REPO_DIR}/scripts/06-setup-node-all-in-one.sh" ;;
  kiosk)      bash "${GRIP_REPO_DIR}/scripts/07-setup-node-kiosk.sh" ;;
esac

# Step 4: Register Systemd Boot Startup, Watchdog & Continuous Deployment
bash "${GRIP_REPO_DIR}/scripts/08-enable-startup.sh" "${ROLE}"

log_ok "=================================================================="
log_ok " Node ${FINAL_HOSTNAME}.local (${ROLE}) installation COMPLETE!"
log_ok " - Auto-start on boot: ENABLED (grip-node.service)"
log_ok " - Self-healing watchdog: ENABLED (grip-watchdog.timer)"
log_ok " - Automated CD updates: ENABLED (grip-cd.timer & webhook :9000)"
log_ok "=================================================================="
