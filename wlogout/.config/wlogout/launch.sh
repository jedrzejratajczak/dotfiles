#!/bin/sh
set -e
# Resolve current wallpaper and launch wlogout

DYNAMIC_CSS="/tmp/wlogout-dynamic.css"

# Get current wallpaper path from awww
WALLPAPER=$(awww query 2>/dev/null | sed -n 's/^image: //p')

if [ -n "$WALLPAPER" ] && [ -f "$WALLPAPER" ]; then
    printf 'window { background-image: linear-gradient(rgba(0,0,0,0.65), rgba(0,0,0,0.65)), url("%s"); }\n' "$WALLPAPER" > "$DYNAMIC_CSS"
else
    printf 'window { background-image: none; }\n' > "$DYNAMIC_CSS"
fi

exec wlogout -b 3 -c 0 -T 300 -B 300
