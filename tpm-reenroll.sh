#!/bin/bash
set -euo pipefail

LUKS_DEV=$(sudo awk 'match($0, /rd.luks.name=([a-f0-9-]+)/, m) {print m[1]}' /etc/cmdline.d/root.conf)
[ -n "$LUKS_DEV" ]

sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes --tpm2-measure-pcr=yes "/dev/disk/by-uuid/$LUKS_DEV"
