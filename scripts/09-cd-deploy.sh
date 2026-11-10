#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Step 09: Continuous Deployment (CD) Engine
# Automatically detects new commits in either the cluster repo or the
# grip-basketball-fullstack submodule and rebuilds ONLY the affected service
# on the current Raspberry Pi node, with automatic rollback on failure.
# Usage: sudo bash scripts/09-cd-deploy.sh [--force]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

FORCE_DEPLOY="${1:-}"
LOCK_FILE="/tmp/grip-cd.lock"

# Prevent concurrent CD runs (e.g., webhook + timer firing at the same time)
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  log_info "Another CD deployment is already running. Exiting."
  exit 0
fi

ROLE="${GRIP_NODE_ROLE:-edge}"
CLUSTER_BRANCH="${GRIP_CLUSTER_BRANCH:-main}"
SUBMODULE_REL="${GRIP_WEB_SUBMODULE_PATH:-submodules/grip-basketball-fullstack}"
SUBMODULE_DIR="${GRIP_REPO_DIR}/${SUBMODULE_REL}"
WEB_BRANCH="${GRIP_WEB_BRANCH:-dev}"
TRACK_LATEST="${GRIP_CD_TRACK_SUBMODULE_LATEST:-true}"

cd "${GRIP_REPO_DIR}"

OLD_CLUSTER_SHA="$(cat "${GRIP_STATE_DIR}/cluster.sha" 2>/dev/null || git rev-parse HEAD)"
OLD_WEB_SHA="$(cat "${GRIP_STATE_DIR}/web.sha" 2>/dev/null || git -C "${SUBMODULE_DIR}" rev-parse HEAD)"

# 1. Fetch latest updates from cluster remote (if remote origin is configured and reachable)
if git remote get-url origin &>/dev/null; then
  if git fetch --quiet origin "${CLUSTER_BRANCH}" 2>/dev/null; then
    REMOTE_CLUSTER_SHA="$(git rev-parse "origin/${CLUSTER_BRANCH}")"
    if [[ "${REMOTE_CLUSTER_SHA}" != "${OLD_CLUSTER_SHA}" ]]; then
      log_info "New commit detected in cluster repo: ${OLD_CLUSTER_SHA:0:7} -> ${REMOTE_CLUSTER_SHA:0:7}"
      git reset --hard "origin/${CLUSTER_BRANCH}"
      git submodule sync --recursive
      git submodule update --init --recursive
    fi
  fi
fi

# 2. Fetch latest updates from web submodule remote (grip-basketball-fullstack)
if [[ -d "${SUBMODULE_DIR}" ]]; then
  if git -C "${SUBMODULE_DIR}" fetch --quiet origin "${WEB_BRANCH}" 2>/dev/null; then
    if [[ "${TRACK_LATEST}" == "true" ]]; then
      REMOTE_WEB_SHA="$(git -C "${SUBMODULE_DIR}" rev-parse "origin/${WEB_BRANCH}")"
      if [[ "${REMOTE_WEB_SHA}" != "${OLD_WEB_SHA}" ]]; then
        log_info "New commit detected in web submodule (${WEB_BRANCH}): ${OLD_WEB_SHA:0:7} -> ${REMOTE_WEB_SHA:0:7}"
        git -C "${SUBMODULE_DIR}" checkout -B "${WEB_BRANCH}" "origin/${WEB_BRANCH}"
      fi
    fi
  fi
fi

NEW_CLUSTER_SHA="$(git rev-parse HEAD)"
NEW_WEB_SHA="$(git -C "${SUBMODULE_DIR}" rev-parse HEAD)"

if [[ "${NEW_CLUSTER_SHA}" == "${OLD_CLUSTER_SHA}" && "${NEW_WEB_SHA}" == "${OLD_WEB_SHA}" && "${FORCE_DEPLOY}" != "--force" ]]; then
  exit 0
fi

log_info "Applying Continuous Deployment update for role '${ROLE}'..."
log_info "Cluster SHA: ${OLD_CLUSTER_SHA:0:7} -> ${NEW_CLUSTER_SHA:0:7} | Web SHA: ${OLD_WEB_SHA:0:7} -> ${NEW_WEB_SHA:0:7}"

# Determine which paths in the web submodule changed so we only rebuild necessary containers
CHANGED_WEB_FILES=""
if [[ "${NEW_WEB_SHA}" != "${OLD_WEB_SHA}" ]]; then
  CHANGED_WEB_FILES="$(git -C "${SUBMODULE_DIR}" diff --name-only "${OLD_WEB_SHA}" "${NEW_WEB_SHA}" 2>/dev/null || echo 'all')"
fi

rollback() {
  log_error "Deployment failed! Rolling back to previous commits (${OLD_CLUSTER_SHA:0:7} / ${OLD_WEB_SHA:0:7})..."
  git -C "${GRIP_REPO_DIR}" reset --hard "${OLD_CLUSTER_SHA}" || true
  git -C "${SUBMODULE_DIR}" checkout -f "${OLD_WEB_SHA}" || true
  bash "${GRIP_REPO_DIR}/scripts/grip-boot-guard.sh" --start
  exit 1
}

trap rollback ERR

case "${ROLE}" in
  db)
    bash "${GRIP_REPO_DIR}/scripts/03-setup-node-db.sh"
    ;;
  app)
    if [[ "${FORCE_DEPLOY}" == "--force" || "${NEW_CLUSTER_SHA}" != "${OLD_CLUSTER_SHA}" || "${CHANGED_WEB_FILES}" == *"backend/"* || "${CHANGED_WEB_FILES}" == "all" ]]; then
      log_info "Backend changes detected; rebuilding & restarting grip-app stack..."
      bash "${GRIP_REPO_DIR}/scripts/04-setup-node-app.sh"
    else
      log_info "No backend/ changes in submodule commit; skipping Maven rebuild on grip-app."
    fi
    ;;
  edge)
    if [[ "${FORCE_DEPLOY}" == "--force" || "${NEW_CLUSTER_SHA}" != "${OLD_CLUSTER_SHA}" || "${CHANGED_WEB_FILES}" == *"frontend/"* || "${CHANGED_WEB_FILES}" == *"scripts/"* || "${CHANGED_WEB_FILES}" == "all" ]]; then
      log_info "Frontend/Live-Sync changes detected; rebuilding & restarting grip-edge stack..."
      bash "${GRIP_REPO_DIR}/scripts/05-setup-node-edge.sh"
    else
      log_info "No frontend/ or scripts/ changes in submodule commit; skipping rebuild on grip-edge."
    fi
    ;;
  all-in-one)
    bash "${GRIP_REPO_DIR}/scripts/06-setup-node-all-in-one.sh"
    ;;
esac

# Update systemd units if cluster repo changed
if [[ "${NEW_CLUSTER_SHA}" != "${OLD_CLUSTER_SHA}" ]]; then
  cp "${GRIP_REPO_DIR}/systemd/"*.service /etc/systemd/system/
  cp "${GRIP_REPO_DIR}/systemd/"*.timer /etc/systemd/system/
  systemctl daemon-reload
fi

echo "${NEW_CLUSTER_SHA}" > "${GRIP_STATE_DIR}/cluster.sha"
echo "${NEW_WEB_SHA}" > "${GRIP_STATE_DIR}/web.sha"

# Append deployment audit record
echo "$(date -Iseconds) ROLE=${ROLE} CLUSTER=${NEW_CLUSTER_SHA:0:7} WEB=${NEW_WEB_SHA:0:7} STATUS=SUCCESS" >> "${GRIP_LOG_DIR}/cd-deployments.log"
log_ok "CD Deployment succeeded! (Cluster: ${NEW_CLUSTER_SHA:0:7}, Web: ${NEW_WEB_SHA:0:7})"
