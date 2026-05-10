#!/bin/bash
set -euo pipefail

STATUS=$(sudo sbctl status --json)

if echo "$STATUS" | jq -e '.setup_mode == true' >/dev/null; then
  sudo sbctl enroll-keys
  sudo sbctl verify || true
  echo
  echo "Keys enrolled. Next steps:"
  echo "  1. Reboot, enter UEFI."
  echo "  2. Enable Secure Boot."
  echo "  3. Boot back, re-run this script for TPM enrollment."
  exit 0
fi

if ! echo "$STATUS" | jq -e '.secure_boot == true' >/dev/null; then
  echo "[!] UEFI is neither in Setup Mode nor has Secure Boot enabled."
  echo "    To start Secure Boot setup:"
  echo "      1. Reboot, enter UEFI."
  echo "      2. Clear / Erase / Reset Platform Keys."
  echo "      3. Save & boot back to OS."
  echo "      4. Re-run this script."
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
