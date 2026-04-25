#!/bin/bash
set -euo pipefail

# Bootstrap helper for fresh-install pendrive.
#
# Run from Arch live ISO once Wi-Fi is up:
#   bash /path/to/bootstrap.sh
#
# Fetches the latest base-install.sh from the repo and execs it. Lives
# on the install pendrive so the only thing that has to be typed by hand
# is the path to this file — base-install.sh's URL stays in the repo
# where it can be edited freely without re-flashing the pendrive.

REPO=https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main
SCRIPT=base-install.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

echo "Fetching $SCRIPT..."
curl -fLO "$REPO/machines/$SCRIPT"
chmod +x "$SCRIPT"

exec "./$SCRIPT"
