#!/bin/bash
set -euo pipefail

if ! sudo sbctl status --json | jq -e '.secure_boot == true' >/dev/null; then
  echo "[!] Secure Boot is not enabled in UEFI."
  echo "    Enable it in firmware setup, then re-run this script."
  exit 1
fi

LUKS_DEV=$(sudo awk 'match($0, /rd.luks.name=([a-f0-9-]+)/, m) {print m[1]}' /etc/cmdline.d/root.conf)
LUKS_DEVICE="/dev/disk/by-uuid/$LUKS_DEV"

if sudo cryptsetup luksDump "$LUKS_DEVICE" | grep -q systemd-tpm2; then
  echo "[=] TPM2 already enrolled in $LUKS_DEVICE."
  exit 0
fi

echo "[*] Enrolling TPM2 for $LUKS_DEVICE."
echo "    You will be asked for the LUKS passphrase, then a new TPM PIN."
sudo systemd-cryptenroll \
    --tpm2-device=auto \
    --tpm2-pcrs=7 \
    --tpm2-with-pin=yes \
    --tpm2-measure-pcr=yes \
    "$LUKS_DEVICE"
