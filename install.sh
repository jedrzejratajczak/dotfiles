#!/bin/bash
set -eo pipefail

# Dotfiles install script for Arch Linux + Hyprland
# Framework 13 (AMD Ryzen AI 5 340)
#
# Usage: git clone <repo> ~/.dotfiles && cd ~/.dotfiles && ./install.sh
# Flags: -t  dry-run (show what would happen, change nothing)
#
# Requires: fresh Arch Linux install with base, base-devel, git, networkmanager

DRY_RUN=false

while getopts "t" opt; do
    case $opt in
        t) DRY_RUN=true ;;
        *) echo "Usage: $0 [-t]" && exit 1 ;;
    esac
done

run() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

echo "=== Dotfiles installer ==="
$DRY_RUN && echo "*** DRY-RUN MODE — no changes will be made ***"
echo ""

# --- 1. Packages (official repos) ---
echo "[1/8] Installing official repo packages..."
run sudo pacman -S --needed --noconfirm \
  zsh \
  stow \
  rofi \
  swaync \
  yazi \
  mpv \
  mpd \
  rmpc \
  cliphist \
  wl-clipboard \
  hyprland \
  hyprlock \
  hypridle \
  hyprpolkitagent \
  hyprpicker \
  imagemagick \
  gammastep \
  brightnessctl \
  swayosd \
  pavucontrol \
  nwg-look \
  nwg-displays \
  bluetui \
  tlp \
  greetd \
  cage \
  satty \
  wlogout \
  waybar \
  kitty \
  neovim \
  playerctl \
  grim \
  slurp \
  wev \
  pipewire \
  pipewire-alsa \
  pipewire-jack \
  pipewire-pulse \
  wireplumber \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  zram-generator \
  noto-fonts \
  ttf-cascadia-code-nerd \
  ttf-cascadia-mono-nerd \
  ttf-nerd-fonts-symbols \
  ttf-nerd-fonts-symbols-mono \
  woff2-font-awesome \
  papirus-icon-theme \
  uwsm \
  qt5-wayland \
  qt6-wayland \
  qt6ct \
  vulkan-radeon \
  smartmontools \
  htop \
  wget \
  less \
  xdg-utils \
  alsa-utils \
  gst-plugin-pipewire \
  libpulse \
  sof-firmware \
  linux-firmware \
  amd-ucode \
  efibootmgr \
  iwd \
  wireless_tools

# --- 2. AUR helper (paru) ---
echo "[2/8] Installing paru..."
if ! command -v paru &>/dev/null; then
  if ! $DRY_RUN; then
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
    rm -rf /tmp/paru
  else
    echo "[dry-run] Would install paru from AUR"
  fi
fi

# --- 3. AUR packages ---
echo "[3/8] Installing AUR packages..."
run paru -S --needed --noconfirm \
  grimblast-git \
  wl-screenrec-git \
  zsh-theme-powerlevel10k-git \
  zen-browser-bin \
  matugen-bin \
  awww

# --- 4. Stow dotfiles ---
echo "[4/8] Stowing dotfiles..."
cd ~/.dotfiles || { echo "Cannot cd to ~/.dotfiles" >&2; exit 1; }

# Backup existing configs before stow overwrites them
BACKUP_DIR="$HOME/.config/dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
backup_if_exists() {
    local target="$1"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        mkdir -p "$BACKUP_DIR"
        local rel="${target#"$HOME"/}"
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        if $DRY_RUN; then
            echo "[dry-run] Would backup $target → $BACKUP_DIR/$rel"
        else
            cp -r "$target" "$BACKUP_DIR/$rel"
            echo "  Backed up $target"
        fi
    fi
}

# Backup files that would conflict with stow
backup_if_exists ~/.zshenv
backup_if_exists ~/.config/zsh/.zshrc
backup_if_exists ~/.config/zsh/.zprofile
backup_if_exists ~/.config/zsh/.p10k.zsh
backup_if_exists ~/.gitconfig
backup_if_exists ~/.config/rofi
backup_if_exists ~/.config/swaync
backup_if_exists ~/.config/yazi
backup_if_exists ~/.config/mpv
backup_if_exists ~/.config/gammastep
backup_if_exists ~/.config/wlogout
backup_if_exists ~/.config/awww/set-wallpaper.sh
backup_if_exists ~/.config/gtk-3.0/settings.ini
backup_if_exists ~/.config/qt6ct/qt6ct.conf
backup_if_exists ~/.config/matugen/config.toml
backup_if_exists ~/.config/uwsm/env
backup_if_exists ~/.config/uwsm/env-hyprland

if [ -d "$BACKUP_DIR" ]; then
    echo "  Backups saved to $BACKUP_DIR"
fi

# Remove existing configs that would conflict with stow
if ! $DRY_RUN; then
    rm -f ~/.zshenv ~/.gitconfig
    rm -f ~/.config/zsh/.zshrc ~/.config/zsh/.zprofile ~/.config/zsh/.p10k.zsh
    rm -rf ~/.config/rofi ~/.config/swaync ~/.config/yazi ~/.config/mpv
    rm -rf ~/.config/gammastep ~/.config/wlogout
    rm -f ~/.config/awww/set-wallpaper.sh
    rm -f ~/.config/gtk-3.0/settings.ini
    rm -f ~/.config/qt6ct/qt6ct.conf
    rm -rf ~/.config/matugen
    rm -f ~/.config/uwsm/env ~/.config/uwsm/env-hyprland
fi

STOW_PACKAGES=(
    zsh git kitty hyprland rofi swaync yazi mpv mpd
    gammastep wlogout waybar gtk qt6ct matugen uwsm awww
)

for dir in "${STOW_PACKAGES[@]}"; do
    echo "  Stowing $dir..."
    run stow -v "$dir" 2>&1 | grep -v "^$" || true
done

# --- 5. System configs (symlinks to dotfiles) ---
echo "[5/8] Applying system configs..."

# TLP
run sudo rm -f /etc/tlp.conf
run sudo ln -sf ~/.dotfiles/tlp/etc/tlp.conf /etc/tlp.conf

# greetd + tuigreet
run sudo rm -f /etc/greetd/config.toml
run sudo ln -sf ~/.dotfiles/greetd/etc/greetd/config.toml /etc/greetd/config.toml

# /etc/issue (ASCII art for tuigreet)
run sudo rm -f /etc/issue
run sudo ln -sf ~/.dotfiles/issue/etc/issue /etc/issue

# logind (power button config)
# NOTE: must copy, not symlink — systemd-logind has ProtectHome=yes
# and cannot follow symlinks into /home/
run sudo cp ~/.dotfiles/logind/etc/systemd/logind.conf /etc/systemd/logind.conf

# Greeter wallpaper
run sudo mkdir -p /usr/share/backgrounds
if ls ~/Pictures/Wallpapers/*.jpg &>/dev/null || ls ~/Pictures/Wallpapers/*.png &>/dev/null; then
  WALLPAPER=$(find ~/Pictures/Wallpapers -type f \( -name "*.jpg" -o -name "*.png" \) | head -1)
  run sudo cp "$WALLPAPER" /usr/share/backgrounds/greeter.jpg
  echo "  Greeter wallpaper set from $WALLPAPER"
else
  echo "  WARNING: No wallpaper found in ~/Pictures/Wallpapers/ — add one and copy to /usr/share/backgrounds/greeter.jpg"
fi

# Boot optimization
run sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf

# --- 6. Systemd services ---
echo "[6/8] Enabling services..."

# System services
run sudo systemctl enable greetd
run sudo systemctl enable tlp
run sudo systemctl enable NetworkManager
run sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
run sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket

# User services
run systemctl --user enable mpd

# --- 7. Shell ---
echo "[7/8] Setting default shell to zsh..."
if [ "$SHELL" != "/usr/bin/zsh" ]; then
  run sudo chsh -s /usr/bin/zsh "$USER"
  echo "  Shell changed to zsh (takes effect on next login)"
fi

# --- 8. Create directories ---
echo "[8/8] Creating directories..."
run mkdir -p ~/Music ~/Videos ~/Pictures/Wallpapers ~/Pictures/Screenshots
run mkdir -p ~/.config/mpd/playlists
run mkdir -p ~/.config/qt6ct/colors
run mkdir -p ~/.local/state/zsh

echo ""
echo "=== Installation complete ==="
echo ""
echo "Manual steps remaining:"
echo "  1. Add wallpaper to ~/Pictures/Wallpapers/"
echo "  2. Run 'p10k configure' to set up prompt"
echo "  3. Run 'matugen image <wallpaper-path> -m dark -t scheme-tonal-spot' to generate colors"
echo "  4. Install Zen Browser extensions: Tridactyl + uBlock Origin (from AMO)"
echo "  5. Reboot"
