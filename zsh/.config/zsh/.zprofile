# Start Hyprland on TTY1 if no display server running
if [[ -z "$DISPLAY" && -z "$WAYLAND_DISPLAY" && "${XDG_VTNR:-0}" -eq 1 ]]; then
    exec uwsm start hyprland-uwsm.desktop
fi
