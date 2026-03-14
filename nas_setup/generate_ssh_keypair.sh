#!/usr/bin/env bash
# generate_ssh_keypair.sh
#
# Run this on your Home Assistant host (via SSH add-on terminal or container shell)
# to generate the dedicated ED25519 key used for NAS shutdown.
#
# Usage:
#   bash generate_ssh_keypair.sh
#
# Output:
#   /config/.ssh/id_ed25519_ha_nas_shutdown       (private key — stays on HA)
#   /config/.ssh/id_ed25519_ha_nas_shutdown.pub   (public key — copied to NAS)

set -euo pipefail

KEY_DIR="/config/.ssh"
KEY_PATH="${KEY_DIR}/id_ed25519_ha_nas_shutdown"

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

if [[ -f "${KEY_PATH}" ]]; then
    echo "Key already exists at ${KEY_PATH}"
    echo "Delete it first if you want to regenerate:"
    echo "  rm ${KEY_PATH} ${KEY_PATH}.pub"
    exit 1
fi

ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "home-assistant-nas-shutdown" -N ""

chmod 600 "${KEY_PATH}"
chmod 644 "${KEY_PATH}.pub"

echo ""
echo "============================================================"
echo " Keys generated successfully"
echo "============================================================"
echo ""
echo " Private key : ${KEY_PATH}"
echo " Public key  : ${KEY_PATH}.pub"
echo ""
echo " Copy the public key below — you will need it for"
echo " nas_setup/01_create_shutdown_user.sh (step 2):"
echo ""
cat "${KEY_PATH}.pub"
echo ""
