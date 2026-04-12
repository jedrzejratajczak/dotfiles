#!/bin/bash
set -eo pipefail

# Dotfiles install script for Arch Linux + Hyprland
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

# --- Machine profile ---
echo "Select machine profile:"
echo "  1) laptop  — Framework 13 (AMD GPU, TLP, sof-firmware)"
echo "  2) desktop — Desktop (NVIDIA GPU, no TLP)"
read -p "Choice [1/2]: " PROFILE_CHOICE

case "$PROFILE_CHOICE" in
    1) PROFILE="laptop" ;;
    2) PROFILE="desktop" ;;
    *) echo "Invalid choice" && exit 1 ;;
esac
echo "Using profile: $PROFILE"
echo ""

# --- 1. Packages (official repos) ---
echo "[1/8] Installing official repo packages..."

# Common packages
PACKAGES=(
  zsh stow rofi swaync yazi mpv mpd rmpc cliphist wl-clipboard
  hyprland hyprlock hypridle hyprpolkitagent hyprpicker
  imagemagick gammastep brightnessctl swayosd pavucontrol
  nwg-look nwg-displays bluetui greetd cage satty waybar kitty
  neovim playerctl grim slurp wev
  pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  zram-generator
  noto-fonts ttf-cascadia-code-nerd ttf-cascadia-mono-nerd
  ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono woff2-font-awesome
  papirus-icon-theme
  uwsm wpaperd qt5-wayland qt6-wayland qt6ct
  smartmontools htop wget less xdg-utils
  alsa-utils gst-plugin-pipewire libpulse
  linux-firmware amd-ucode efibootmgr
  iwd wireless_tools github-cli
  ufw usbguard
)

# Profile-specific packages
if [ "$PROFILE" = "laptop" ]; then
  PACKAGES+=(vulkan-radeon sof-firmware tlp)
elif [ "$PROFILE" = "desktop" ]; then
  PACKAGES+=(nvidia-open linux-headers)
fi

run sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"

# --- 2. AUR helper (paru) ---
echo "[2/8] Installing paru..."
if ! command -v paru &>/dev/null; then
  if ! $DRY_RUN; then
    rm -rf /tmp/paru
    for attempt in 1 2 3; do
      echo "  Cloning paru (attempt $attempt/3)..."
      if git clone https://aur.archlinux.org/paru.git /tmp/paru; then
        break
      fi
      rm -rf /tmp/paru
      [ "$attempt" -lt 3 ] && sleep 2
    done
    [ -d /tmp/paru ] || { echo "Failed to clone paru after 3 attempts" >&2; exit 1; }
    (cd /tmp/paru && makepkg -si --noconfirm)
    rm -rf /tmp/paru
  else
    echo "[dry-run] Would install paru from AUR"
  fi
fi

# --- 3. AUR packages ---
echo "[3/8] Installing AUR packages..."
AUR_PACKAGES=(
  grimblast-git wl-screenrec-git zsh-theme-powerlevel10k-git
  zen-browser-bin matugen-bin wlogout awww-bin
  nilgreeter-bin nilnotify-bin nilpower-bin nilwall-bin nilwidgets-bin
)

if [ "$PROFILE" = "desktop" ]; then
  AUR_PACKAGES+=(mediatek-mt7927-dkms)
fi

run paru -S --needed --noconfirm "${AUR_PACKAGES[@]}"

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
backup_if_exists ~/.config/wpaperd

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
    rm -rf ~/.config/wpaperd
fi

STOW_PACKAGES=(
    zsh git kitty hyprland rofi swaync yazi mpv mpd
    gammastep wlogout waybar gtk qt6ct matugen uwsm awww wpaperd
)

for dir in "${STOW_PACKAGES[@]}"; do
    echo "  Stowing $dir..."
    run stow -v "$dir" 2>&1 | grep -v "^$" || true
done

# --- 5. System configs (symlinks to dotfiles) ---
echo "[5/8] Applying system configs..."

# TLP (laptop only)
if [ "$PROFILE" = "laptop" ]; then
  run sudo rm -f /etc/tlp.conf
  run sudo ln -sf ~/.dotfiles/tlp/etc/tlp.conf /etc/tlp.conf
fi

# greetd (must copy, not symlink — greetd has ProtectHome=yes)
run sudo rm -f /etc/greetd/config.toml
run sudo cp ~/.dotfiles/greetd/etc/greetd/config.toml /etc/greetd/config.toml

# nilgreeter wrapper
run sudo tee /usr/local/bin/nilgreeter-wrapper > /dev/null << 'WRAPPER'
#!/bin/sh
export XKB_DEFAULT_LAYOUT=pl
exec cage -s -- /usr/bin/nilgreeter 2>>/tmp/nilgreeter.log
WRAPPER
run sudo chmod +x /usr/local/bin/nilgreeter-wrapper

# /etc/issue (ASCII art for tuigreet)
run sudo rm -f /etc/issue
run sudo ln -sf ~/.dotfiles/issue/etc/issue /etc/issue

# logind (power button config)
# NOTE: must copy, not symlink — systemd-logind has ProtectHome=yes
# and cannot follow symlinks into /home/
run sudo cp ~/.dotfiles/logind/etc/systemd/logind.conf /etc/systemd/logind.conf

# Greeter wallpaper
# Greeter wallpaper (default: p0.webp)
run sudo mkdir -p /usr/share/backgrounds
if [ -f ~/.dotfiles/wallpapers/p0.webp ]; then
  run sudo cp ~/.dotfiles/wallpapers/p0.webp /usr/share/backgrounds/greeter.jpg
  echo "  Greeter wallpaper set from p0.webp"
elif ls ~/Pictures/Wallpapers/*.jpg &>/dev/null || ls ~/Pictures/Wallpapers/*.png &>/dev/null; then
  WALLPAPER=$(find ~/Pictures/Wallpapers -type f \( -name "*.jpg" -o -name "*.png" \) | head -1)
  run sudo cp "$WALLPAPER" /usr/share/backgrounds/greeter.jpg
  echo "  Greeter wallpaper set from $WALLPAPER"
else
  echo "  WARNING: No wallpaper found — add one and copy to /usr/share/backgrounds/greeter.jpg"
fi

# Boot optimization
run sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf

# --- 6. Security hardening ---
echo "[6/9] Applying security hardening..."

# Firewall (ufw)
echo "  Configuring firewall..."
run sudo ufw default deny incoming
run sudo ufw default allow outgoing
run sudo ufw --force enable

# Encrypted DNS (DNS-over-TLS via systemd-resolved)
echo "  Configuring encrypted DNS..."
run sudo mkdir -p /etc/systemd/resolved.conf.d
run sudo tee /etc/systemd/resolved.conf.d/dns-over-tls.conf > /dev/null << 'DNS'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=9.9.9.9#dns.quad9.net
DNSOverTLS=true
DNSSEC=allow-downgrade
Domains=~.
DNS
run sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
run sudo mkdir -p /etc/NetworkManager/conf.d
run sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null << 'NMDNS'
[main]
dns=systemd-resolved
NMDNS

# Kernel hardening (sysctl)
echo "  Applying kernel hardening..."
run sudo tee /etc/sysctl.d/99-hardening.conf > /dev/null << 'SYSCTL'
# Hide kernel pointers from unprivileged users
kernel.kptr_restrict = 2

# Restrict dmesg to root
kernel.dmesg_restrict = 1

# Restrict magic SysRq key to sync + remount-ro + reboot only
kernel.sysrq = 176

# Harden BPF JIT compiler
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# Prevent core dumps for SUID binaries
fs.suid_dumpable = 0

# Restrict ptrace to parent processes only
kernel.yama.ptrace_scope = 2

# Network hardening
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
SYSCTL

# PAM login delay (4 seconds between attempts, brute-force protection)
echo "  Configuring login delay..."
if ! grep -q "pam_faildelay" /etc/pam.d/system-login 2>/dev/null; then
  run sudo sed -i '0,/^auth/{s/^auth/auth       optional   pam_faildelay.so delay=4000000\nauth/}' /etc/pam.d/system-login
fi

# USBGuard (whitelist current devices, block unknown)
echo "  Configuring USBGuard..."
if [ ! -f /etc/usbguard/rules.conf ] || [ ! -s /etc/usbguard/rules.conf ]; then
  run sudo sh -c 'usbguard generate-policy > /etc/usbguard/rules.conf'
  echo "  USBGuard policy generated from currently connected devices"
fi

# Privacy: hostname leak, MAC randomization, IPv6 privacy
echo "  Configuring network privacy..."
run sudo tee /etc/NetworkManager/conf.d/privacy.conf > /dev/null << 'NMPRIVACY'
[device]
wifi.scan-rand-mac-address=yes

[connection]
ethernet.cloned-mac-address=stable
wifi.cloned-mac-address=stable
ipv4.dhcp-send-hostname=0
ipv6.dhcp-send-hostname=0
ipv6.addr-gen-mode=1
ipv6.ip6-privacy=2
ipv6.dhcp-duid=stable-uuid
NMPRIVACY

# Privacy: disable core dumps
echo "  Disabling core dumps..."
run sudo mkdir -p /etc/systemd/coredump.conf.d
run sudo tee /etc/systemd/coredump.conf.d/disable.conf > /dev/null << 'COREDUMP'
[Coredump]
Storage=none
ProcessSizeMax=0
COREDUMP

# --- 7. Systemd services ---
echo "[7/9] Enabling services..."

# System services
run sudo systemctl enable greetd
run sudo systemctl enable NetworkManager
run sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
run sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket
run sudo systemctl enable ufw
run sudo systemctl enable usbguard
run sudo systemctl enable systemd-resolved

if [ "$PROFILE" = "laptop" ]; then
  run sudo systemctl enable tlp
fi

# User services
run systemctl --user enable mpd

# --- 8. Shell ---
echo "[8/9] Setting default shell to zsh..."
if [ "$SHELL" != "/usr/bin/zsh" ]; then
  run sudo chsh -s /usr/bin/zsh "$USER"
  echo "  Shell changed to zsh (takes effect on next login)"
fi

# --- 9. Create directories and copy wallpapers ---
echo "[9/9] Setting up directories and wallpapers..."
run mkdir -p ~/Music ~/Videos ~/Pictures/Wallpapers ~/Pictures/Screenshots
run mkdir -p ~/.config/mpd/playlists
run mkdir -p ~/.config/qt6ct/colors
run mkdir -p ~/.local/state/zsh

# Copy bundled wallpapers and set default
if [ -d ~/.dotfiles/wallpapers ]; then
  run cp -n ~/.dotfiles/wallpapers/* ~/Pictures/Wallpapers/ 2>/dev/null || true
  echo "  Wallpapers copied to ~/Pictures/Wallpapers/"
fi
if [ -f ~/Pictures/Wallpapers/p0.webp ] && command -v matugen &>/dev/null; then
  run matugen image ~/Pictures/Wallpapers/p0.webp -m dark -t scheme-tonal-spot
  echo "  Default color scheme generated from p0.webp"
fi

echo ""
echo "=== Installation complete ==="
echo ""

# --- Optional: Secure Boot + TPM2 ---
echo "Set up Secure Boot + TPM2 auto-unlock?"
echo "  (Requires Secure Boot in Setup Mode in BIOS)"
read -p "Continue? [y/N] " SETUP_SB

if [[ "$SETUP_SB" == [yY] ]]; then
  echo "Setting up Secure Boot..."
  run sudo pacman -S --needed --noconfirm sbctl tpm2-tss

  echo "Creating Secure Boot keys..."
  run sudo sbctl create-keys
  run sudo sbctl enroll-keys -m

  echo "Signing boot files..."
  for uki in /boot/EFI/Linux/*.efi; do
    [ -f "$uki" ] && run sudo sbctl sign -s "$uki"
  done
  run sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
  run sudo sbctl verify

  echo ""
  echo "Secure Boot keys enrolled and boot files signed."

  # Check if Secure Boot is already active (re-run scenario)
  if sbctl status 2>/dev/null | grep -q "Secure Boot.*enabled"; then
    echo ""
    echo "Secure Boot is active. Set up TPM2 auto-unlock?"
    echo "  (LUKS will unlock automatically when boot chain is intact)"
    read -p "Continue? [y/N] " SETUP_TPM
    if [[ "$SETUP_TPM" == [yY] ]]; then
      LUKS_DEV=$(awk '/rd.luks.name/ {match($0, /rd.luks.name=([a-f0-9-]+)/, m); print m[1]}' /etc/cmdline.d/root.conf 2>/dev/null)
      if [ -n "$LUKS_DEV" ]; then
        echo "Enrolling TPM2 key (you will be asked for your LUKS password)..."
        run sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "/dev/disk/by-uuid/$LUKS_DEV"
        echo "TPM2 auto-unlock configured."
      else
        echo "Could not detect LUKS UUID from /etc/cmdline.d/root.conf"
        echo "Run manually: sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/<luks-partition>"
      fi
    fi
  else
    echo ""
    echo "Secure Boot is NOT yet active."
    echo "After this script finishes:"
    echo "  1. Reboot into BIOS"
    echo "  2. Enable Secure Boot"
    echo "  3. Boot into system"
    echo "  4. Re-run: ./install.sh  (select Secure Boot again to enroll TPM2)"
  fi
fi

echo ""
echo "=== Pre-install checklist (do before running this script) ==="
echo "  - BIOS: Set administrator password"
echo "  - BIOS: Disable CSM"
echo "  - BIOS: Enable fTPM (AMD fTPM configuration → Firmware TPM)"
echo "  - BIOS: Enable EXPO for RAM"
echo ""
echo "=== Post-install manual steps ==="
echo "  1. Install Zen Browser extensions: Tridactyl + uBlock Origin (from AMO)"
if ! sbctl status 2>/dev/null | grep -q "Secure Boot.*enabled"; then
  echo "  3. Enable Secure Boot in BIOS, then re-run ./install.sh for TPM2 setup"
fi
