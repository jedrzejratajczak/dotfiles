#!/bin/sh
set -e

TMPFRAME=""
trap '[ -n "$TMPFRAME" ] && rm -f "$TMPFRAME"' EXIT

for cmd in awww matugen file; do
    command -v "$cmd" >/dev/null
done

WALLPAPER="$1"
[ -n "$WALLPAPER" ]
[ -f "$WALLPAPER" ]

for _ in 1 2 3 4 5; do
    awww query >/dev/null 2>&1 && break
    sleep 1
done

awww img "$WALLPAPER" --transition-type fade --transition-duration 1

MIME=$(file -b --mime-type "$WALLPAPER")
if [ "$MIME" = "image/gif" ]; then
    command -v magick >/dev/null
    TMPFRAME=$(mktemp /tmp/awww-frame-XXXXXX.png)
    magick "${WALLPAPER}[0]" "$TMPFRAME"
    matugen image "$TMPFRAME" -m dark -t scheme-tonal-spot
else
    matugen image "$WALLPAPER" -m dark -t scheme-tonal-spot
fi
