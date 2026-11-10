# GRIP Basketball — Raspberry Pi 4B Cluster & Smart Court Deployment (`grip-rpi-cluster`)

Production infrastructure, automated provisioning `.sh` scripts, `systemd` plug-and-play boot services, and Continuous Deployment (CD) engine for running the **GRIP Basketball** platform on **Raspberry Pi 4 Model B (4GB RAM / 32GB microSD)** hardware.

This repository tracks [`grip-basketball-fullstack`](https://github.com/Victor151203/grip-basketball-fullstack.git) as a **Git submodule** under [`submodules/grip-basketball-fullstack`](submodules/grip-basketball-fullstack).

---

## Hardware Sizing: Using 3 of Your 5 Raspberry Pi 4Bs

You have **5x Raspberry Pi 4B (4GB RAM, 32GB microSD)** available. **You do not need to use all 5.**
The optimal production architecture uses **3 Raspberry Pis**, keeping **2 unused** as spares (or optionally using 1 for single-node portable tournaments, or a 4th as an HDMI Court Scoreboard Kiosk):

| Node | Hostname (mDNS) | Assigned Role (`--role`) | Services Running | RAM Usage | Why Isolated? |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **RPi #1** | `grip-edge.local` | `edge` | **Nginx Reverse Proxy & Static Web** (`:80`) + **Python Live-Sync 3x3 & Sports DB Engine** (`:5500`) | ~350 MB | Ultra-low latency for court tablets (`live-tracker.html`) and player browsers. |
| **RPi #2** | `grip-app.local` | `app` | **Spring Boot 3 REST API** (`:8080`, Java 17 ARM64) + **Mailpit Local SMTP/Webmail** (`:1025` / `:8025`) | ~1.2 GB (2.2 GB during Maven build) | Isolates heavy JVM & Maven CD compilation so it never starves Nginx or PostgreSQL of RAM. |
| **RPi #3** | `grip-db.local` | `db` | **PostgreSQL 16 ARM64** (`:5432`, RPi4 tuned) + **Daily `pg_dump` Auto-Backup** (`grip-backup.timer`) | ~600 MB | Dedicated microSD I/O and memory cache for database persistence. |
| *RPi #4 (Optional)* | `grip-kiosk.local` | `kiosk` | **Fullscreen Chromium HDMI Kiosk** (`live-tracker.html`) | ~500 MB | Only needed if plugging an RPi directly into a court TV/monitor via HDMI. |
| *RPi #4 & #5* | — | *Unused / Spare* | Kept powered off as cold spares | 0 MB | Saves power, switch ports, and SD wear. |

> **Single-Pi Portable Option (`--role all-in-one`):** If you ever take the system to a small pop-up court and only want to carry **1 Raspberry Pi**, run `sudo bash scripts/install-node.sh --role all-in-one` to run all services on a single RPi 4B.

---

## Repository Structure

```text
grip-rpi-cluster/
├─ .gitmodules                        # Submodule -> grip-basketball-fullstack (branch: dev)
├─ README.md                          # Quick overview
├─ DEPLOYMENT_AND_CD_GUIDE.md         # Complete step-by-step deployment, boot & CD manual
├─ config/
│  ├─ cluster.env.example             # Environment template copied to /opt/grip/config/cluster.env
│  ├─ nginx.edge.conf                 # Nginx gateway config (routes /api/ + live-sync endpoints)
│  ├─ nginx.all-in-one.conf           # Nginx config for single-RPi mode
│  └─ postgresql.rpi4.conf            # PostgreSQL 16 memory & microSD wear tuning for 4GB RPi 4B
├─ docker/
│  ├─ Dockerfile.livesync             # ARM64 image for the Python Live-Sync & Sports DB service
│  ├─ docker-compose.db.yml           # Compose stack for RPi #3 (grip-db)
│  ├─ docker-compose.app.yml          # Compose stack for RPi #2 (grip-app)
│  ├─ docker-compose.edge.yml         # Compose stack for RPi #1 (grip-edge)
│  └─ docker-compose.all-in-one.yml   # Compose stack for 1-RPi portable mode
├─ scripts/
│  ├─ 00-common.sh                    # Logging, directory creation (/opt/grip/*), TCP wait helpers
│  ├─ 01-provision-os.sh              # Docker ARM64, Avahi mDNS, 2GB swap, journald/SD card tuning
│  ├─ 02-install-code.sh              # Installs repo + submodule into /opt/grip/repo & seeds JSON data
│  ├─ 03-setup-node-db.sh             # Starts & verifies PostgreSQL 16 on RPi #3
│  ├─ 04-setup-node-app.sh            # Builds & starts Spring Boot + Mailpit on RPi #2
│  ├─ 05-setup-node-edge.sh           # Builds & starts Nginx + Live-Sync on RPi #1
│  ├─ 06-setup-node-all-in-one.sh     # Builds & starts All-in-One stack on a single RPi
│  ├─ 07-setup-node-kiosk.sh          # Configures fullscreen Chromium HDMI Court Kiosk
│  ├─ 08-enable-startup.sh            # Enables systemd boot, watchdog, backup & CD timers
│  ├─ 09-cd-deploy.sh                 # Automated Continuous Deployment (Git poll + selective rebuild)
│  ├─ backup-db.sh                    # Compressed pg_dump + Court JSON snapshot (14-day retention)
│  ├─ grip-boot-guard.sh              # Boot startup & every-2-min self-healing repositioning watchdog
│  ├─ deploy-fleet-ssh.sh             # One-command remote installer from your Mac/PC over SSH
│  └─ install-node.sh                 # Master installer entrypoint run on each Raspberry Pi
├─ systemd/
│  ├─ grip-node.service               # Starts assigned role automatically on boot/power-on
│  ├─ grip-watchdog.{service,timer}   # Verifies & heals containers every 2 min after relocation
│  ├─ grip-cd.{service,timer}         # Checks Git remotes every 2 min for automated CD
│  ├─ grip-cd-webhook.service         # Instant GitHub Webhook listener on port 9000
│  ├─ grip-backup.{service,timer}     # Daily 03:00 AM automated database & JSON backup
│  └─ grip-kiosk.service              # Fullscreen X11/Chromium scoreboard display service
├─ cd/
│  └─ webhook-server.py               # HMAC-SHA256 verified GitHub Webhook daemon
└─ submodules/
   └─ grip-basketball-fullstack/      # Web page + Spring Boot backend submodule
```

---

## Quick Start (3 Commands)

On each Raspberry Pi (or remotely from your Mac via `bash scripts/deploy-fleet-ssh.sh`):

```bash
# 1. On RPi #3 (Database Node):
sudo bash scripts/install-node.sh --role db

# 2. On RPi #2 (Backend Application Node):
sudo bash scripts/install-node.sh --role app

# 3. On RPi #1 (Edge Web & Live-Sync Node):
sudo bash scripts/install-node.sh --role edge
```

See [**`DEPLOYMENT_AND_CD_GUIDE.md`**](DEPLOYMENT_AND_CD_GUIDE.md) for the complete step-by-step instructions.
