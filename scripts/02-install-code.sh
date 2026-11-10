#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Step 02: Install Code, Submodules, Config & Seed Data
# Clones/updates repo + grip-basketball-fullstack submodule into /opt/grip/repo
# Usage: sudo bash scripts/02-install-code.sh [role]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories

NODE_ROLE="${1:-edge}"

# 1. Create /opt/grip/config/cluster.env if it does not exist yet
if [[ ! -f "${GRIP_ENV_FILE}" ]]; then
  log_info "Creating initial ${GRIP_ENV_FILE} from template..."
  cp "${SOURCE_REPO_ROOT}/config/cluster.env.example" "${GRIP_ENV_FILE}"
  sed -i "s/^GRIP_NODE_ROLE=.*/GRIP_NODE_ROLE=${NODE_ROLE}/" "${GRIP_ENV_FILE}"

  case "${NODE_ROLE}" in
    edge)       DEF_HOST="grip-edge" ;;
    app)        DEF_HOST="grip-app" ;;
    db)         DEF_HOST="grip-db" ;;
    all-in-one) DEF_HOST="grip" ;;
    kiosk)      DEF_HOST="grip-kiosk" ;;
    *)          DEF_HOST="grip-${NODE_ROLE}" ;;
  esac
  sed -i "s/^GRIP_NODE_HOSTNAME=.*/GRIP_NODE_HOSTNAME=${DEF_HOST}/" "${GRIP_ENV_FILE}"
  chmod 600 "${GRIP_ENV_FILE}"
fi

load_cluster_env

# 2. Install or synchronize repository into /opt/grip/repo
log_info "Installing/Updating GRIP cluster repository at ${GRIP_REPO_DIR}..."
if [[ "${SOURCE_REPO_ROOT}" != "${GRIP_REPO_DIR}" ]]; then
  rsync -a --delete --exclude '.git/index.lock' "${SOURCE_REPO_ROOT}/" "${GRIP_REPO_DIR}/"
fi

cd "${GRIP_REPO_DIR}"
git config --global --add safe.directory "${GRIP_REPO_DIR}" || true
git config --global --add safe.directory "${GRIP_REPO_DIR}/${GRIP_WEB_SUBMODULE_PATH:-submodules/grip-basketball-fullstack}" || true

# Initialize & update the web page submodule if not populated
SUBMODULE_DIR="${GRIP_REPO_DIR}/${GRIP_WEB_SUBMODULE_PATH:-submodules/grip-basketball-fullstack}"
if [[ ! -f "${SUBMODULE_DIR}/frontend/index.html" ]]; then
  log_info "Initializing git submodule (${GRIP_WEB_SUBMODULE_PATH:-submodules/grip-basketball-fullstack})..."
  git submodule sync --recursive || true
  git submodule update --init --recursive || true
fi

# 3. Seed persistent Court Data (/opt/grip/data/court) with initial JSONs if empty
if [[ -d "${SUBMODULE_DIR}/frontend/data" ]]; then
  log_info "Seeding persistent court data directory (${GRIP_COURT_DATA_DIR})..."
  for json_file in "${SUBMODULE_DIR}/frontend/data/"*.json; do
    [[ -e "${json_file}" ]] || continue
    base_name="$(basename "${json_file}")"
    if [[ ! -f "${GRIP_COURT_DATA_DIR}/${base_name}" ]]; then
      cp "${json_file}" "${GRIP_COURT_DATA_DIR}/${base_name}"
      log_ok "Seeded ${base_name} -> ${GRIP_COURT_DATA_DIR}/${base_name}"
    fi
  done
fi

# 4. Record deployed commit SHAs for Continuous Deployment (CD) state tracking
CLUSTER_SHA="$(git -C "${GRIP_REPO_DIR}" rev-parse HEAD 2>/dev/null || echo 'initial')"
WEB_SHA="$(git -C "${SUBMODULE_DIR}" rev-parse HEAD 2>/dev/null || echo 'initial')"
echo "${CLUSTER_SHA}" > "${GRIP_STATE_DIR}/cluster.sha"
echo "${WEB_SHA}" > "${GRIP_STATE_DIR}/web.sha"

chmod +x "${GRIP_REPO_DIR}/scripts/"*.sh
log_ok "Codebase & submodule ready at ${GRIP_REPO_DIR} (Cluster: ${CLUSTER_SHA:0:7}, Web: ${WEB_SHA:0:7})."
