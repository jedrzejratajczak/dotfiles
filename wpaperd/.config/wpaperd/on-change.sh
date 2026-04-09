#!/bin/sh
set -e
# Triggered by wpaperd on wallpaper change
# $1 = display name, $2 = wallpaper path
[ -f "$2" ] || exit 1
matugen image "$2" -m dark -t scheme-tonal-spot
