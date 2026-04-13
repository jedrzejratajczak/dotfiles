# Enable user services on first login (needs running user systemd instance)
if [[ ! -f "$XDG_STATE_HOME/zsh/.services-enabled" ]]; then
    systemctl --user daemon-reload
    systemctl --user enable mpd waybar gammastep hypridle hyprpolkitagent cliphist pipewire-pulse wireplumber nilnotify awww
    mkdir -p "$XDG_STATE_HOME/zsh"
    touch "$XDG_STATE_HOME/zsh/.services-enabled"
fi

# Start Hyprland on TTY1 if no display server running
if [[ -z "$DISPLAY" && -z "$WAYLAND_DISPLAY" && "${XDG_VTNR:-0}" -eq 1 ]]; then
    exec uwsm start hyprland-uwsm.desktop
fi
