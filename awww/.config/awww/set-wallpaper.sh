#!/bin/sh
# Set wallpaper via awww with matugen color generation
# Usage: set-wallpaper.sh <path-to-image>
# Handles both static images and animated GIFs

set -e

TMPFRAME=""
trap '[ -n "$TMPFRAME" ] && rm -f "$TMPFRAME"' EXIT

# Verify required dependencies
for cmd in awww matugen file; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd" >&2; exit 1; }
done

WALLPAPER="$1"

if [ -z "$WALLPAPER" ]; then
    echo "Usage: $0 <path-to-image>" >&2
    exit 1
fi

if [ ! -f "$WALLPAPER" ]; then
    echo "File not found: $WALLPAPER" >&2
    exit 1
fi

# Wait for awww-daemon to be ready
for _ in 1 2 3 4 5; do
    awww query >/dev/null 2>&1 && break
    sleep 1
done

# Set wallpaper with awww
awww img "$WALLPAPER" --transition-type fade --transition-duration 1

# Generate color scheme with matugen
# For GIFs, extract first frame to a temp file
MIME=$(file -b --mime-type "$WALLPAPER")
if [ "$MIME" = "image/gif" ]; then
    command -v magick >/dev/null 2>&1 || { echo "Missing dependency: magick (imagemagick)" >&2; exit 1; }
    TMPFRAME=$(mktemp /tmp/awww-frame-XXXXXX.png)
    magick "${WALLPAPER}[0]" "$TMPFRAME"
    matugen image "$TMPFRAME" -m dark -t scheme-tonal-spot
else
    matugen image "$WALLPAPER" -m dark -t scheme-tonal-spot
fi
