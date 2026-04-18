#!/bin/bash
set -euo pipefail

# Dotfiles install script for Arch Linux + Hyprland
#
# Usage: git clone <repo> ~/.dotfiles && cd ~/.dotfiles && ./install.sh
#
# Requires: fresh Arch Linux install with base, base-devel, git, networkmanager

echo "=== Dotfiles installer ==="
echo ""

# --- Machine profile (auto-detected) ---
if ls /sys/class/power_supply/BAT* &>/dev/null; then
  PROFILE="laptop"
else
  PROFILE="desktop"
fi
echo "Detected profile: $PROFILE"
echo ""

# --- 1. Packages (official repos) ---
echo "Installing official repo packages..."

# Common packages
PACKAGES=(
  zsh stow rofi yazi mpv wl-clipboard wl-clip-persist
  hyprland hyprlock hypridle hyprsunset hyprpolkitagent hyprpicker
  imagemagick brightnessctl swayosd pavucontrol gpu-screen-recorder
  nwg-displays greetd cage satty waybar kitty
  neovim playerctl grim slurp
  pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  zram-generator
  noto-fonts ttf-cascadia-code-nerd
  papirus-icon-theme
  uwsm qt6-wayland qt6ct
  eza bat git-delta lazygit
  docker docker-compose
  fzf jq less xdg-utils
  gst-plugin-pipewire libpulse
  linux-firmware amd-ucode efibootmgr
  github-cli
  obs-studio kdenlive
  ufw usbguard awww matugen code
  flatpak
)

# Profile-specific packages
if [ "$PROFILE" = "laptop" ]; then
  PACKAGES+=(vulkan-radeon sof-firmware tlp)
elif [ "$PROFILE" = "desktop" ]; then
  PACKAGES+=(nvidia-open linux-headers)
fi

sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"

# --- 2. AUR helper (paru) ---
echo "Installing paru..."
if ! command -v paru &>/dev/null; then
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
fi

# --- 3. AUR packages ---
echo "Installing AUR packages..."
AUR_PACKAGES=(
  grimblast-git zsh-theme-powerlevel10k-git pinta
  nilgreeter-bin nilnotify-bin nilpower-bin nilwall-bin nilwidgets-bin
  localsend-bin lazydocker-bin
)

AUR_PACKAGES+=(cloudflare-warp-bin)

if [ "$PROFILE" = "desktop" ]; then
  AUR_PACKAGES+=(mediatek-mt7927-dkms)
fi

paru -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# Flatpak (sandboxed apps)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --noninteractive flathub io.gitlab.librewolf-community

# --- 4. Stow dotfiles ---
echo "Stowing dotfiles..."
cd ~/.dotfiles || { echo "Cannot cd to ~/.dotfiles" >&2; exit 1; }

STOW_PACKAGES=(
    zsh git kitty hyprland rofi yazi mpv
    waybar gtk matugen uwsm awww systemd
)

# Unstow any prior state before touching anything. Without this, a
# re-run would follow folded directory symlinks (e.g. ~/.config/zsh
# symlinked into this repo) and the rm -f below would delete tracked
# source files through the symlink.
for dir in "${STOW_PACKAGES[@]}"; do
    stow -D "$dir" 2>/dev/null || true
done

# Move runtime / generated files that a prior folded-stow run leaked
# into the package dirs (systemd enablements via symlinked user dir,
# matugen output via symlinked config dirs) into real target dirs so
# they stop polluting the repo.
mkdir -p ~/.config/systemd/user ~/.config/hypr ~/.config/waybar \
         ~/.config/kitty ~/.config/rofi ~/.config/yazi ~/.config/zsh
for item in default.target.wants graphical-session.target.wants \
            pipewire.service.wants sockets.target.wants \
            pipewire-session-manager.service; do
    src="$HOME/.dotfiles/systemd/.config/systemd/user/$item"
    [ -e "$src" ] && mv "$src" ~/.config/systemd/user/
done
for f in colors.conf hyprlock-colors.conf monitors.conf; do
    src="$HOME/.dotfiles/hyprland/.config/hypr/$f"
    [ -f "$src" ] && mv "$src" ~/.config/hypr/
done
for src_dst in \
    "waybar/.config/waybar/colors.css:waybar/" \
    "kitty/.config/kitty/current-theme.conf:kitty/" \
    "rofi/.config/rofi/colors.rasi:rofi/" \
    "yazi/.config/yazi/theme.toml:yazi/" \
    "zsh/.config/zsh/.zcompdump:zsh/" \
    "zsh/.config/zsh/local.zsh:zsh/"; do
    src="$HOME/.dotfiles/${src_dst%:*}"
    dst="$HOME/.config/${src_dst##*:}"
    [ -f "$src" ] && mv "$src" "$dst"
done

# Backup any fresh-arch defaults still at target paths (non-symlinks).
BACKUP_DIR="$HOME/.config/dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
backup_if_exists() {
    local target="$1"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        mkdir -p "$BACKUP_DIR"
        local rel="${target#"$HOME"/}"
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        cp -r "$target" "$BACKUP_DIR/$rel"
        echo "  Backed up $target"
    fi
}
backup_if_exists ~/.zshenv
backup_if_exists ~/.config/zsh/.zshrc
backup_if_exists ~/.config/zsh/.zprofile
backup_if_exists ~/.config/zsh/.p10k.zsh
backup_if_exists ~/.gitconfig
backup_if_exists ~/.config/awww/set-wallpaper.sh
backup_if_exists ~/.config/gtk-3.0/settings.ini
backup_if_exists ~/.config/gtk-4.0/settings.ini
backup_if_exists ~/.config/qt6ct
backup_if_exists ~/.config/matugen/config.toml
backup_if_exists ~/.config/uwsm/env
backup_if_exists ~/.config/uwsm/env-hyprland
backup_if_exists ~/.config/systemd/user/nilnotify.service
backup_if_exists ~/.config/systemd/user/awww.service
if [ -d "$BACKUP_DIR" ]; then
    echo "  Backups saved to $BACKUP_DIR"
fi

# Remove non-symlink conflicts. Safe now: unstow above removed every
# stow-managed symlink, so no rm here can traverse into the repo.
rm -f ~/.zshenv ~/.gitconfig
rm -f ~/.config/zsh/.zshrc ~/.config/zsh/.zprofile ~/.config/zsh/.p10k.zsh
rm -f ~/.config/awww/set-wallpaper.sh
rm -f ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini
rm -rf ~/.config/qt6ct
rm -rf ~/.config/matugen
rm -f ~/.config/uwsm/env ~/.config/uwsm/env-hyprland
rm -f ~/.config/systemd/user/nilnotify.service ~/.config/systemd/user/awww.service

# --no-folding creates individual file symlinks rather than folding a
# package into one dir symlink. This keeps runtime writes (systemd
# enablements, matugen output) in the real filesystem instead of
# silently ending up in the repo via a directory symlink.
for dir in "${STOW_PACKAGES[@]}"; do
    echo "  Stowing $dir..."
    stow -v --no-folding "$dir" 2>&1 | grep -v "^$" || true
done

# --- 5. System configs (symlinks to dotfiles) ---
echo "Applying system configs..."

# TLP (laptop only)
if [ "$PROFILE" = "laptop" ]; then
  sudo cp "$HOME/.dotfiles/tlp/etc/tlp.conf" /etc/tlp.conf
fi

# greetd (must copy, not symlink — greetd has ProtectHome=yes)
sudo rm -f /etc/greetd/config.toml
sudo cp ~/.dotfiles/greetd/etc/greetd/config.toml /etc/greetd/config.toml

# nilgreeter wrapper
sudo tee /usr/local/bin/nilgreeter-wrapper > /dev/null << 'WRAPPER'
#!/bin/sh
export XKB_DEFAULT_LAYOUT=pl
exec cage -s -- /usr/bin/nilgreeter 2>/dev/null
WRAPPER
sudo chmod +x /usr/local/bin/nilgreeter-wrapper

# /etc/issue
sudo cp "$HOME/.dotfiles/issue/etc/issue" /etc/issue

# logind (power button config, drop-in)
sudo mkdir -p /etc/systemd/logind.conf.d
sudo cp "$HOME/.dotfiles/logind/etc/systemd/logind.conf.d/power-key.conf" /etc/systemd/logind.conf.d/power-key.conf

# Greeter wallpaper (nilgreeter reads /usr/share/nilgreeter/background.gif)
sudo mkdir -p /usr/share/nilgreeter
if [ -f ~/.dotfiles/wallpapers/waterfall.gif ]; then
  sudo cp ~/.dotfiles/wallpapers/waterfall.gif /usr/share/nilgreeter/background.gif
  echo "  Greeter wallpaper set from waterfall.gif"
elif [ -f ~/.dotfiles/wallpapers/p0.webp ]; then
  sudo cp ~/.dotfiles/wallpapers/p0.webp /usr/share/nilgreeter/background.gif
  echo "  Greeter wallpaper set from p0.webp (static fallback)"
else
  echo "  WARNING: No wallpaper found — copy a GIF to /usr/share/nilgreeter/background.gif"
fi

# Boot optimization
if [ -f /boot/loader/loader.conf ]; then
  sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf
fi

# Silent boot
sudo mkdir -p /etc/cmdline.d
sudo tee /etc/cmdline.d/silent.conf > /dev/null << 'SILENT'
quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3 mem_encrypt=on
SILENT

# DMA protection (Thunderbolt/PCIe)
sudo tee /etc/cmdline.d/iommu.conf > /dev/null << 'IOMMU'
amd_iommu=force_isolation iommu=pt
IOMMU

# --- 6. Security hardening ---
echo "Applying security hardening..."

# Firewall (ufw)
echo "  Configuring firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

# Encrypted DNS (DNS-over-TLS via systemd-resolved)
echo "  Configuring encrypted DNS..."
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/dns-over-tls.conf > /dev/null << 'DNS'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=9.9.9.9#dns.quad9.net
DNSOverTLS=true
DNSSEC=opportunistic
Domains=~.
DNS
sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null << 'NMDNS'
[main]
dns=systemd-resolved
NMDNS

# Kernel hardening (sysctl)
echo "  Applying kernel hardening..."
sudo tee /etc/sysctl.d/99-hardening.conf > /dev/null << 'SYSCTL'
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
kernel.yama.ptrace_scope = 1

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
  sudo sed -i '0,/^auth/{s/^auth/auth       optional   pam_faildelay.so delay=4000000\nauth/}' /etc/pam.d/system-login
fi

# USBGuard (whitelist current devices, block unknown)
echo "  Configuring USBGuard..."
if [ ! -f /etc/usbguard/rules.conf ] || [ ! -s /etc/usbguard/rules.conf ]; then
  sudo sh -c 'usbguard generate-policy > /etc/usbguard/rules.conf'
  echo "  USBGuard policy generated from currently connected devices"
fi

# Privacy: hostname leak, MAC randomization, IPv6 privacy
echo "  Configuring network privacy..."
sudo tee /etc/NetworkManager/conf.d/privacy.conf > /dev/null << 'NMPRIVACY'
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

# Restrict /boot permissions (survives kernel updates via pacman hook)
echo "  Restricting /boot permissions..."
sudo chmod 700 /boot
sudo mkdir -p /etc/pacman.d/hooks
sudo tee /etc/pacman.d/hooks/99-boot-permissions.hook > /dev/null << 'BOOTHOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Path
Target = boot/*

[Action]
When = PostTransaction
Exec = /usr/bin/chmod 700 /boot
BOOTHOOK

# Auto re-sign UKIs and systemd-boot after kernel/bootloader updates
echo "  Installing sbctl auto-sign hook..."
sudo tee /etc/pacman.d/hooks/95-sbctl-sign.hook > /dev/null << 'SBHOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen
Target = linux-hardened
Target = systemd
Target = systemd-boot
Target = mkinitcpio
Target = amd-ucode
Target = intel-ucode

[Action]
Description = Signing EFI binaries with sbctl...
When = PostTransaction
Exec = /usr/bin/sbctl sign-all
Depends = sbctl
SBHOOK

# Privacy: disable core dumps
echo "  Disabling core dumps..."
sudo mkdir -p /etc/systemd/coredump.conf.d
sudo tee /etc/systemd/coredump.conf.d/disable.conf > /dev/null << 'COREDUMP'
[Coredump]
Storage=none
ProcessSizeMax=0
COREDUMP

# --- 7. Systemd services ---
echo "Enabling services..."

# System services
sudo systemctl enable greetd
sudo systemctl enable NetworkManager
sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
sudo systemctl enable ufw
sudo systemctl enable usbguard
sudo systemctl enable systemd-resolved
sudo systemctl enable docker.socket
sudo systemctl enable --now warp-svc

if [ "$PROFILE" = "laptop" ]; then
  sudo systemctl enable tlp
fi

# User services are enabled on first login via .zprofile

# --- 8. Shell and groups ---
echo "Setting default shell and groups..."
if [ "$SHELL" != "/usr/bin/zsh" ]; then
  sudo chsh -s /usr/bin/zsh "$USER"
  echo "  Shell changed to zsh (takes effect on next login)"
fi
if ! groups "$USER" | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$USER"
  echo "  Added $USER to docker group (takes effect on next login)"
fi

# --- 9. Create directories and copy wallpapers ---
echo "Setting up directories and wallpapers..."
mkdir -p ~/Videos ~/Pictures/Wallpapers ~/Pictures/Screenshots
mkdir -p ~/.config/qt6ct/colors
mkdir -p ~/.local/state/zsh

# qt6ct config (not stowed — contains machine-specific home path)
cp ~/.dotfiles/qt6ct/.config/qt6ct/qt6ct.conf ~/.config/qt6ct/qt6ct.conf
sed -i "s|__HOME__|$HOME|" ~/.config/qt6ct/qt6ct.conf

# Configure zram
sudo tee /etc/systemd/zram-generator.conf > /dev/null << 'ZRAM'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRAM

# Create monitors.conf if missing (machine-specific, not tracked in git)
if [ ! -f ~/.config/hypr/monitors.conf ]; then
  mkdir -p ~/.config/hypr
  echo "monitor = , preferred, auto, auto" > ~/.config/hypr/monitors.conf
  echo "  Default monitors.conf created — edit ~/.config/hypr/monitors.conf for your display"
fi

# Create matugen output files if missing (generated by matugen, gitignored)
if [ ! -f ~/.config/hypr/colors.conf ]; then
  touch ~/.config/hypr/colors.conf
fi
if [ ! -f ~/.config/hypr/hyprlock-colors.conf ]; then
  touch ~/.config/hypr/hyprlock-colors.conf
fi
if [ ! -f ~/.config/waybar/colors.css ]; then
  touch ~/.config/waybar/colors.css
fi
if [ ! -f ~/.config/kitty/current-theme.conf ]; then
  touch ~/.config/kitty/current-theme.conf
fi
if [ ! -f ~/.config/rofi/colors.rasi ]; then
  touch ~/.config/rofi/colors.rasi
fi
if [ ! -f ~/.config/yazi/theme.toml ]; then
  touch ~/.config/yazi/theme.toml
fi
if [ ! -f ~/.config/qt6ct/colors/material-you.conf ]; then
  touch ~/.config/qt6ct/colors/material-you.conf
fi
if [ ! -f ~/.config/nilnotify/colors ]; then
  mkdir -p ~/.config/nilnotify
  touch ~/.config/nilnotify/colors
fi
if [ ! -f ~/.config/nilwall/colors.css ]; then
  mkdir -p ~/.config/nilwall
  touch ~/.config/nilwall/colors.css
fi

# Copy bundled wallpapers and set default
if [ -d ~/.dotfiles/wallpapers ]; then
  cp -n ~/.dotfiles/wallpapers/* ~/Pictures/Wallpapers/ 2>/dev/null || true
  echo "  Wallpapers copied to ~/Pictures/Wallpapers/"
fi
if [ -f ~/Pictures/Wallpapers/p0.webp ] && command -v matugen &>/dev/null; then
  matugen image ~/Pictures/Wallpapers/p0.webp -m dark -t scheme-tonal-spot
  echo "  Default color scheme generated from p0.webp"
fi

# Regenerate UKIs (picks up silent boot cmdline)
sudo mkinitcpio -P

echo ""
echo "=== Installation complete ==="
echo ""

# --- Secure Boot + TPM2 ---
echo "Setting up Secure Boot..."
sudo pacman -S --needed --noconfirm sbctl tpm2-tss

if ! sudo sbctl list-keys &>/dev/null || [ -z "$(sudo sbctl list-keys 2>/dev/null)" ]; then
  echo "Creating Secure Boot keys..."
  sudo sbctl create-keys
  sudo sbctl enroll-keys -m
else
  echo "  Secure Boot keys already exist, skipping creation"
fi

echo "Signing boot files..."
for uki in /boot/EFI/Linux/*.efi; do
  [ -f "$uki" ] && sudo sbctl sign -s "$uki"
done
sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sudo sbctl verify

if sbctl status 2>/dev/null | grep -q "Secure Boot.*enabled"; then
  LUKS_DEV=$(awk '/rd.luks.name/ {match($0, /rd.luks.name=([a-f0-9-]+)/, m); print m[1]}' /etc/cmdline.d/root.conf 2>/dev/null || true)
  if [ -n "$LUKS_DEV" ]; then
    if sudo systemd-cryptenroll --tpm2-device=list "/dev/disk/by-uuid/$LUKS_DEV" 2>/dev/null | grep -q tpm2; then
      echo "  TPM2 already enrolled, skipping"
    else
      echo "Enrolling TPM2 key (you will be asked for your LUKS password, then set a TPM PIN)..."
      sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,2,7,11 --tpm2-with-pin=yes "/dev/disk/by-uuid/$LUKS_DEV"
      echo "TPM2 auto-unlock configured (PIN required on boot)."
    fi
  fi
fi

echo ""
echo "=== Post-install ==="
if ! sbctl status 2>/dev/null | grep -q "Secure Boot.*enabled"; then
  echo "  1. Reboot into BIOS, enable Secure Boot"
  echo "  2. Boot into system, re-run ./install.sh (will enroll TPM2 automatically)"
fi
echo "  - Register Cloudflare WARP:  warp-cli registration new"
echo "  - Connect WARP:              warp-cli connect"
echo "  - Verify:                    warp-cli status"
