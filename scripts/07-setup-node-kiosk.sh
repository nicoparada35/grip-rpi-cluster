#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Step 07: Setup Optional Court Scoreboard HDMI Kiosk Node
# Configures Chromium in fullscreen Kiosk mode displaying live-tracker.html
# Usage: sudo bash scripts/07-setup-node-kiosk.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

log_info "Installing lightweight X11 & Chromium Kiosk packages for Court Display..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  xserver-xorg \
  x11-xserver-utils \
  xinit \
  openbox \
  chromium-browser \
  unclutter || apt-get install -y --no-install-recommends chromium unclutter x11-xserver-utils

cat <<'KIOSK_SH' > "${GRIP_BASE_DIR}/kiosk-launch.sh"
#!/usr/bin/env bash
set -euo pipefail
source /opt/grip/config/cluster.env 2>/dev/null || true
TARGET_URL="${GRIP_FRONTEND_URL:-http://grip-edge.local}/live-tracker.html"

xset -dpms || true
xset s off || true
xset s noblank || true
unclutter -idle 0.5 -root &

CHROMIUM_BIN="$(command -v chromium-browser || command -v chromium)"
while true; do
  "${CHROMIUM_BIN}" \
    --noerrdialogs \
    --disable-infobars \
    --kiosk \
    --incognito \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    "${TARGET_URL}" || sleep 3
done
KIOSK_SH
chmod +x "${GRIP_BASE_DIR}/kiosk-launch.sh"

log_ok "Court Scoreboard Kiosk launcher installed at ${GRIP_BASE_DIR}/kiosk-launch.sh"
