#!/bin/bash
set -euo pipefail

# Re-enroll TPM2 after firmware/BIOS update or PCR mismatch.
# Wipes existing TPM2 slot and re-binds with current PCR values.
# You will be prompted for your LUKS password and a new TPM PIN.

LUKS_DEV=$(awk 'match($0, /rd.luks.name=([a-f0-9-]+)/, m) {print m[1]}' /etc/cmdline.d/root.conf)
[ -n "$LUKS_DEV" ] || { echo "Could not find LUKS UUID in /etc/cmdline.d/root.conf" >&2; exit 1; }

DEV="/dev/disk/by-uuid/$LUKS_DEV"

echo "Wiping existing TPM2 slot on $DEV..."
sudo systemd-cryptenroll --wipe-slot=tpm2 "$DEV"

echo "Enrolling new TPM2 key with PCR 7+11 + PIN..."
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7+11 --tpm2-with-pin=yes "$DEV"

echo "Done. Reboot to verify auto-unlock with new PIN."
