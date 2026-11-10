#!/usr/bin/env bash
# =============================================================================
# GRIP Basketball — Step 01: Base OS Provisioning for Raspberry Pi 4B (4GB/32GB)
# Installs Docker ARM64, Avahi mDNS, 2GB Swap, and microSD Wear Protection
# Usage: sudo bash scripts/01-provision-os.sh [hostname]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-common.sh
source "${SCRIPT_DIR}/00-common.sh"

require_root
ensure_grip_directories
load_cluster_env

TARGET_HOSTNAME="${1:-${GRIP_NODE_HOSTNAME:-grip-edge}}"

log_info "==> [1/6] Checking hardware & updating apt repositories..."
check_hardware_resources
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  jq \
  rsync \
  avahi-daemon \
  avahi-utils \
  libnss-mdns \
  ufw \
  htop \
  python3 \
  python3-pip

log_info "==> [2/6] Configuring Hostname (${TARGET_HOSTNAME}) & Avahi mDNS (.local)..."
hostnamectl set-hostname "${TARGET_HOSTNAME}"
if ! grep -q "127.0.1.1.*${TARGET_HOSTNAME}" /etc/hosts; then
  sed -i "/127.0.1.1/d" /etc/hosts
  echo "127.0.1.1 ${TARGET_HOSTNAME} ${TARGET_HOSTNAME}.local" >> /etc/hosts
fi

# Register cluster peer IPs in /etc/hosts for instant resolution alongside Avahi mDNS
sed -i '/# GRIP-CLUSTER-HOSTS/d' /etc/hosts
cat <<EOF >> /etc/hosts
${GRIP_EDGE_HOST:-192.168.0.121} grip-edge grip-edge.local grip.local # GRIP-CLUSTER-HOSTS
${GRIP_APP_HOST:-192.168.0.148} grip-app grip-app.local # GRIP-CLUSTER-HOSTS
${GRIP_DB_HOST:-192.168.0.23} grip-db grip-db.local # GRIP-CLUSTER-HOSTS
EOF

# Configure Avahi to publish mDNS reliably on Ethernet & Wi-Fi when repositioned
mkdir -p /etc/avahi
cat <<'AVAHI' > /etc/avahi/avahi-daemon.conf
[server]
use-ipv4=yes
use-ipv6=no
allow-interfaces=eth0,wlan0
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=yes

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=yes
publish-domain=yes
AVAHI

systemctl enable --now avahi-daemon
systemctl restart avahi-daemon

log_info "==> [3/6] Configuring 2GB Swapfile (prevents OOM on 4GB RAM during Maven builds)..."
if [[ "$(swapon --show | wc -l)" -eq 0 ]] || [[ ! -f /swapfile && ! -f /var/swap ]]; then
  if command -v dphys-swapfile &>/dev/null && [[ -f /etc/dphys-swapfile ]]; then
    sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
    dphys-swapfile setup
    dphys-swapfile swapon
  elif [[ ! -f /swapfile ]]; then
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q "/swapfile" /etc/fstab; then
      echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
  fi
fi

log_info "==> [4/6] Applying Kernel & 32GB microSD Wear-Reduction Optimizations..."
cat <<'SYSCTL' > /etc/sysctl.d/99-grip-rpi4.conf
# Keep swap usage minimal unless RAM is genuinely full (protects microSD)
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.overcommit_memory=1

# High concurrency network buffers for Live-Sync & PostgreSQL
net.core.somaxconn=1024
net.ipv4.ip_local_port_range=10240 65535
net.ipv4.tcp_tw_reuse=1
SYSCTL
sysctl --system >/dev/null

# Cap systemd journal size to 100MB to protect the 32GB microSD card
mkdir -p /etc/systemd/journald.conf.d
cat <<'JOURNAL' > /etc/systemd/journald.conf.d/99-grip-sd-protect.conf
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=50M
MaxRetentionSec=7day
JOURNAL
systemctl restart systemd-journald || true

log_info "==> [5/6] Installing Docker Engine & Docker Compose Plugin (ARM64)..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

TARGET_USER="${SUDO_USER:-pi}"
if id "${TARGET_USER}" &>/dev/null; then
  usermod -aG docker "${TARGET_USER}" || true
fi

# Configure global Docker log rotation for 32GB microSD protection
mkdir -p /etc/docker
cat <<'DOCKER_DAEMON' > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
DOCKER_DAEMON

systemctl enable --now docker
systemctl reload-or-restart docker

log_info "==> [6/6] Base OS provisioning complete for ${TARGET_HOSTNAME}.local!"
