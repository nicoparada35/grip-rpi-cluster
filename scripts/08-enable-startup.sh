#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Step 08: Register & Enable Systemd Startup, Watchdog & CD
# Ensures plug-and-play turn-on/off resilience after reboot or court relocation
# Usage: sudo bash scripts/08-enable-startup.sh [role]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

ROLE="${1:-${GRIP_NODE_ROLE:-edge}}"

log_info "Installing systemd unit files from ${GRIP_REPO_DIR}/systemd/ to /etc/systemd/system/..."
cp "${GRIP_REPO_DIR}/systemd/"*.service /etc/systemd/system/
cp "${GRIP_REPO_DIR}/systemd/"*.timer /etc/systemd/system/

systemctl daemon-reload

# 1. Enable primary boot startup service for this node's role
log_info "Enabling grip-node.service (auto-starts ${ROLE} stack on power-on)..."
systemctl enable grip-node.service

# 2. Enable self-healing network/service watchdog (every 2 minutes)
log_info "Enabling grip-watchdog.timer (auto-heals after router/power repositioning)..."
systemctl enable --now grip-watchdog.timer

# 3. Enable Continuous Deployment (CD) Poller + Webhook Listener
if [[ "${ROLE}" != "kiosk" ]]; then
  log_info "Enabling grip-cd.timer (checks Git repos every 2 min) & grip-cd-webhook.service..."
  systemctl enable --now grip-cd.timer
  systemctl enable --now grip-cd-webhook.service
fi

# 4. Enable Automated Database Backups on DB or All-in-One nodes
if [[ "${ROLE}" == "db" || "${ROLE}" == "all-in-one" || "${ROLE}" == "edge" ]]; then
  log_info "Enabling grip-backup.timer (daily automated backups with 14-day retention)..."
  systemctl enable --now grip-backup.timer
fi

# 5. Enable HDMI Kiosk service if role is kiosk
if [[ "${ROLE}" == "kiosk" ]]; then
  log_info "Enabling grip-kiosk.service..."
  systemctl enable --now grip-kiosk.service
fi

log_ok "All boot startup & self-healing systemd tasks enabled for role '${ROLE}'!"
