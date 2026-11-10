#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Shared Functions, Directories & Environment Loader
# Target: Raspberry Pi 4 Model B (4GB RAM / 32GB microSD, ARM64)
# =============================================================================
set -euo pipefail

export GRIP_BASE_DIR="${GRIP_BASE_DIR:-/opt/grip}"
export GRIP_REPO_DIR="${GRIP_BASE_DIR}/repo"
export GRIP_CONFIG_DIR="${GRIP_BASE_DIR}/config"
export GRIP_DATA_DIR="${GRIP_BASE_DIR}/data"
export GRIP_POSTGRES_DIR="${GRIP_DATA_DIR}/postgres"
export GRIP_COURT_DATA_DIR="${GRIP_DATA_DIR}/court"
export GRIP_BACKUP_DIR="${GRIP_BASE_DIR}/backups"
export GRIP_LOG_DIR="${GRIP_BASE_DIR}/logs"
export GRIP_STATE_DIR="${GRIP_BASE_DIR}/state"
export GRIP_ENV_FILE="${GRIP_CONFIG_DIR}/cluster.env"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[GRIP-INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') — $*"; }
log_ok()    { echo -e "${GREEN}[GRIP-OK]${NC}   $(date '+%Y-%m-%d %H:%M:%S') — $*"; }
log_warn()  { echo -e "${YELLOW}[GRIP-WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') — $*"; }
log_error() { echo -e "${RED}[GRIP-ERR]${NC}  $(date '+%Y-%m-%d %H:%M:%S') — $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be run as root (use: sudo bash $0 ...)"
    exit 1
  fi
}

ensure_grip_directories() {
  log_info "Creating required GRIP directories under ${GRIP_BASE_DIR}..."
  mkdir -p \
    "${GRIP_BASE_DIR}" \
    "${GRIP_REPO_DIR}" \
    "${GRIP_CONFIG_DIR}" \
    "${GRIP_DATA_DIR}" \
    "${GRIP_POSTGRES_DIR}" \
    "${GRIP_COURT_DATA_DIR}" \
    "${GRIP_BACKUP_DIR}" \
    "${GRIP_LOG_DIR}" \
    "${GRIP_STATE_DIR}"

  chmod 755 "${GRIP_BASE_DIR}" "${GRIP_DATA_DIR}" "${GRIP_COURT_DATA_DIR}" "${GRIP_LOG_DIR}" "${GRIP_STATE_DIR}" "${GRIP_BACKUP_DIR}"
  # postgres:16-alpine runs as UID:GID 70:70 inside the container; allow it to create /var/lib/postgresql/data/pgdata
  chown -R 70:70 "${GRIP_POSTGRES_DIR}" 2>/dev/null || true
  chmod 777 "${GRIP_POSTGRES_DIR}"
  log_ok "Directory hierarchy verified at ${GRIP_BASE_DIR}."
}

load_cluster_env() {
  if [[ -f "${GRIP_ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${GRIP_ENV_FILE}"
    set +a
  else
    log_warn "Environment file ${GRIP_ENV_FILE} not found yet; using defaults."
  fi
}

check_hardware_resources() {
  local arch
  arch="$(uname -m)"
  local ram_mb
  ram_mb="$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  local free_gb
  free_gb="$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}' 2>/dev/null || echo 0)"

  log_info "Detected Architecture: ${arch} | Total RAM: ${ram_mb} MB | Free Disk: ${free_gb} GB"
  if [[ "${arch}" != "aarch64" && "${arch}" != "arm64" ]]; then
    log_warn "Expected 64-bit ARM OS (aarch64) on Raspberry Pi 4B, detected: ${arch}."
  fi
  if [[ "${free_gb}" -lt 3 ]]; then
    log_warn "Low free space on microSD (${free_gb} GB free). Pruning unused Docker cache..."
    docker system prune -f >/dev/null 2>&1 || true
  fi
}

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local retries="${3:-30}"
  local wait_sec="${4:-3}"

  log_info "Waiting for ${host}:${port} to become reachable (max $((retries * wait_sec))s)..."
  for ((i=1; i<=retries; i++)); do
    if timeout 2 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
      log_ok "${host}:${port} is reachable!"
      return 0
    fi
    sleep "${wait_sec}"
  done
  log_warn "Timed out waiting for ${host}:${port} after $((retries * wait_sec))s."
  return 1
}
