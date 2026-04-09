# dotfiles

Arch Linux + Hyprland setup managed with GNU Stow.

## What's included

- **Shell:** Zsh + zinit + Powerlevel10k
- **Terminal:** Kitty
- **WM:** Hyprland (UWSM session)
- **Bar:** Waybar
- **Launcher:** Rofi (Wayland native)
- **Notifications:** nilnotify
- **Lock/Idle:** Hyprlock + Hypridle
- **Wallpaper:** wpaperd + nilwall
- **Power menu:** nilpower
- **Widgets:** nilwidgets
- **Greeter:** nilgreeter (greetd)
- **Theming:** Matugen (Material You)
- **Power management:** TLP

## Install

Requires a fresh Arch Linux install with `base`, `base-devel`, `git`, and `networkmanager`.

```bash
git clone https://github.com/jedrzejratajczak/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

Use `./install.sh -t` for a dry-run that shows what would happen without making changes.

## Post-reboot

1. Add a wallpaper to `~/Pictures/Wallpapers/`
2. Generate color scheme:
   ```bash
   matugen image ~/Pictures/Wallpapers/<wallpaper> -m dark -t scheme-tonal-spot
   ```
3. Configure Powerlevel10k prompt:
   ```bash
   p10k configure
   ```
4. (Optional) Create `~/.config/zsh/local.zsh` for machine-specific aliases and variables — this file is gitignored.

## Machine-specific config

`~/.config/zsh/local.zsh` is excluded from version control. Use it for anything that differs between machines (SSH aliases, environment variables, paths).
