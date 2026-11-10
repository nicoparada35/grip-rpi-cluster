#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Remote Fleet Provisioner & Updater (Run from your Mac/PC)
# Pushes this repository (including the web submodule) via rsync/SSH to your
# 3 Raspberry Pis in the correct startup order: DB -> APP -> EDGE
#
# Usage:
#   bash scripts/deploy-fleet-ssh.sh [pi_user] [db_host] [app_host] [edge_host]
# Example:
#   bash scripts/deploy-fleet-ssh.sh pi 192.168.1.103 192.168.1.102 192.168.1.101
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_USER="${1:-pi}"
DB_HOST="${2:-grip-db.local}"
APP_HOST="${3:-grip-app.local}"
EDGE_HOST="${4:-grip-edge.local}"

deploy_to_pi() {
  local role="$1"
  local host="$2"
  echo "==> Syncing GRIP Cluster + Web Submodule to ${PI_USER}@${host} (role: ${role})..."
  ssh "${PI_USER}@${host}" "mkdir -p ~/grip-rpi-cluster"
  rsync -avz --delete \
    --exclude '.git/index.lock' \
    --exclude 'submodules/grip-basketball-fullstack/backend/target' \
    "${REPO_ROOT}/" "${PI_USER}@${host}:~/grip-rpi-cluster/"

  echo "==> Running install-node.sh --role ${role} on ${host}..."
  ssh -t "${PI_USER}@${host}" "sudo bash ~/grip-rpi-cluster/scripts/install-node.sh --role ${role} --db-host ${DB_HOST} --app-host ${APP_HOST} --edge-host ${EDGE_HOST}"
}

echo "=================================================================="
echo " Deploying GRIP 3-Node Raspberry Pi 4B Cluster"
echo "   1. RPi #3 (Database) : ${PI_USER}@${DB_HOST}"
echo "   2. RPi #2 (Backend)  : ${PI_USER}@${APP_HOST}"
echo "   3. RPi #1 (Edge/Web) : ${PI_USER}@${EDGE_HOST}"
echo "=================================================================="

deploy_to_pi "db"   "${DB_HOST}"
deploy_to_pi "app"  "${APP_HOST}"
deploy_to_pi "edge" "${EDGE_HOST}"

echo "=================================================================="
echo " All 3 Raspberry Pi nodes deployed and active!"
echo " Open http://${EDGE_HOST} in your browser."
echo "=================================================================="
