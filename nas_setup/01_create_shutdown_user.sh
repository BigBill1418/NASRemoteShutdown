#!/usr/bin/env bash
# 01_create_shutdown_user.sh
#
# Run this ON the Synology NAS (192.168.50.20) as the admin user via SSH.
#
# What it does:
#   1. Creates a locked system user 'ha_shutdown' with no login shell
#   2. Creates ~/.ssh/authorized_keys with your Home Assistant public key,
#      restricted via a forced command so the key can ONLY trigger shutdown
#   3. Sets correct ownership and permissions
#
# Usage:
#   1. SSH into the NAS:
#        ssh admin@192.168.50.20
#   2. Paste your HA public key into the variable below (HA_PUBLIC_KEY)
#   3. Run:
#        sudo bash 01_create_shutdown_user.sh

set -euo pipefail

# ─── PASTE YOUR PUBLIC KEY HERE ──────────────────────────────────────────────
# Copy the output of:  cat /config/.ssh/id_ed25519_ha_nas_shutdown.pub
# from your HA host and paste it between the single quotes below.
HA_PUBLIC_KEY='PASTE_PUBLIC_KEY_HERE'
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${HA_PUBLIC_KEY}" == 'PASTE_PUBLIC_KEY_HERE' ]]; then
    echo "ERROR: You must paste your Home Assistant public key into HA_PUBLIC_KEY"
    exit 1
fi

SHUTDOWN_USER="ha_shutdown"
SHUTDOWN_CMD="/usr/syno/sbin/synoshutdown"

echo "==> Creating user: ${SHUTDOWN_USER}"

# Synology uses synouser for user management
if id "${SHUTDOWN_USER}" &>/dev/null; then
    echo "    User already exists, skipping creation"
else
    synouser --add "${SHUTDOWN_USER}" "" "" 0 "" 0
    # Lock the account — it must only be accessible via SSH key
    passwd -l "${SHUTDOWN_USER}"
fi

# Resolve home directory (Synology places it under /var/services/homes/)
HOME_DIR="$(getent passwd ${SHUTDOWN_USER} | cut -d: -f6)"
SSH_DIR="${HOME_DIR}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

echo "==> Setting up SSH directory at ${SSH_DIR}"
mkdir -p "${SSH_DIR}"

# Forced-command entry: even if this key were compromised, it can ONLY run
# synoshutdown -h — nothing else.
FORCED_COMMAND="command=\"sudo ${SHUTDOWN_CMD} -h\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty"

echo "${FORCED_COMMAND} ${HA_PUBLIC_KEY}" > "${AUTH_KEYS}"

chown -R "${SHUTDOWN_USER}:users" "${HOME_DIR}/.ssh"
chmod 700 "${SSH_DIR}"
chmod 600 "${AUTH_KEYS}"

echo ""
echo "==> Deploying sudoers rule"
echo "    Copy nas_setup/02_sudoers_nas_shutdown to /etc/sudoers.d/ on this NAS"
echo "    (the script will remind you — see README.md Step 3)"
echo ""
echo "============================================================"
echo " Done. User '${SHUTDOWN_USER}' is configured."
echo ""
echo " Next step: deploy the sudoers rule."
echo "   sudo cp 02_sudoers_nas_shutdown /etc/sudoers.d/ha_shutdown"
echo "   sudo chmod 440 /etc/sudoers.d/ha_shutdown"
echo "   sudo chown root:root /etc/sudoers.d/ha_shutdown"
echo "============================================================"
