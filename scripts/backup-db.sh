#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Automated Database & Court JSON Backup Script
# Protects data integrity while respecting 32GB microSD storage limits
# Usage: sudo bash scripts/backup-db.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
RETENTION_DAYS="${GRIP_BACKUP_RETENTION_DAYS:-14}"

# 1. PostgreSQL dump (if grip-db container is running on this RPi)
if docker ps --format '{{.Names}}' | grep -q '^grip-db$'; then
  PG_DUMP_FILE="${GRIP_BACKUP_DIR}/gripdb_${TIMESTAMP}.sql.gz"
  log_info "Creating compressed PostgreSQL backup: ${PG_DUMP_FILE}..."
  docker exec grip-db pg_dump -U "${GRIP_DB_USER:-grip}" "${GRIP_DB_NAME:-gripdb}" | gzip -9 > "${PG_DUMP_FILE}"
  log_ok "PostgreSQL backup saved ($(du -h "${PG_DUMP_FILE}" | awk '{print $1}'))."
fi

# 2. Court JSON data snapshot (if court data exists on this RPi)
if [[ -d "${GRIP_COURT_DATA_DIR}" ]] && compgen -G "${GRIP_COURT_DATA_DIR}/*.json" > /dev/null; then
  COURT_ARCHIVE="${GRIP_BACKUP_DIR}/courtdata_${TIMESTAMP}.tar.gz"
  log_info "Creating Court JSON data snapshot: ${COURT_ARCHIVE}..."
  tar -czf "${COURT_ARCHIVE}" -C "${GRIP_COURT_DATA_DIR}" .
  log_ok "Court JSON snapshot saved."
fi

# 3. Rotate old backups so the 32GB microSD card never fills up
log_info "Pruning backups older than ${RETENTION_DAYS} days..."
find "${GRIP_BACKUP_DIR}" -type f \( -name "*.sql.gz" -o -name "*.tar.gz" \) -mtime +"${RETENTION_DAYS}" -delete

log_ok "Backup cycle completed."
