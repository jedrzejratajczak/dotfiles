# Start Hyprland on TTY1 if no display server running. Use hyprland.desktop
# (not hyprland-uwsm.desktop): the -uwsm variant is a display-manager entry
# whose Exec= itself calls `uwsm start ... hyprland.desktop`, so calling it
# from a login shell double-wraps. Per Arch wiki "Hyprland", the canonical
# tty/login-shell pattern is `uwsm start hyprland.desktop`.
if [[ -z "$DISPLAY" && -z "$WAYLAND_DISPLAY" && "${XDG_VTNR:-0}" -eq 1 ]]; then
    exec uwsm start hyprland.desktop
fi
