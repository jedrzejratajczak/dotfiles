#!/bin/bash
set -euo pipefail

# Dotfiles install script for Arch Linux + Hyprland
#
# Usage: git clone <repo> ~/.dotfiles && cd ~/.dotfiles && ./install.sh
#
# Requires: fresh Arch Linux install with base, base-devel, git, networkmanager

echo "=== Dotfiles installer ==="
echo ""

# --- Hardware detection (per component, not per machine) ---
ls /sys/class/power_supply/BAT* &>/dev/null && HAS_BATTERY=1 || HAS_BATTERY=0

if grep -q GenuineIntel /proc/cpuinfo; then
  UCODE="intel-ucode"
else
  UCODE="amd-ucode"
fi

GPU_INFO=$(lspci -nn | grep -iE "vga|3d|display" || true)
NET_INFO=$(lspci -nn | grep -iE "network|wireless" || true)
GPU_NVIDIA=0; echo "$GPU_INFO" | grep -qi "NVIDIA"          && GPU_NVIDIA=1
GPU_AMD=0;    echo "$GPU_INFO" | grep -qiE "AMD|ATI|Radeon" && GPU_AMD=1
GPU_INTEL=0;  echo "$GPU_INFO" | grep -qi "Intel"           && GPU_INTEL=1

echo "Detected hardware:"
echo "  ucode:   $UCODE"
echo "  gpu:     $([ $GPU_NVIDIA = 1 ] && printf 'nvidia ')$([ $GPU_AMD = 1 ] && printf 'amd ')$([ $GPU_INTEL = 1 ] && printf 'intel')"
echo "  battery: $([ $HAS_BATTERY = 1 ] && echo yes || echo no)"
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
  fzf jq less xdg-utils xdg-user-dirs
  gst-plugin-pipewire libpulse libnotify
  linux-firmware "$UCODE" efibootmgr
  github-cli
  obs-studio kdenlive
  ufw usbguard awww matugen code
  flatpak
)

# Hardware-specific packages (driven by detection, not machine profile)
[ $GPU_AMD = 1 ]     && PACKAGES+=(vulkan-radeon)
[ $GPU_NVIDIA = 1 ]  && PACKAGES+=(nvidia-open linux-headers)
[ $GPU_INTEL = 1 ]   && PACKAGES+=(vulkan-intel)
[ $HAS_BATTERY = 1 ] && PACKAGES+=(tlp)
# SOF firmware: ~10MB, harmless where unused. Needed on CPUs with
# integrated audio DSP (Intel Tiger Lake+, AMD Phoenix/Hawk/Strix mobile).
# Unconditional here to keep the detection surface small.
PACKAGES+=(sof-firmware)

# Suspend mkinitcpio pacman hooks during bulk install. Without this,
# every kernel-adjacent package (systemd, mkinitcpio, amd-ucode, linux-
# headers, etc.) triggers a full mkinitcpio -P inside pacman. A single
# explicit regeneration near the end is enough. Restored via EXIT trap
# so a mid-run failure doesn't leave the hooks missing from pacman's
# hook dir on the next upgrade. (Pattern borrowed from Omarchy.)
MKHOOK_DIR="/usr/share/libalpm/hooks"
MKHOOK_BAK="/tmp"
_restore_mkhooks() {
  for h in 60-mkinitcpio-remove 90-mkinitcpio-install; do
    if [ -f "$MKHOOK_BAK/${h}.hook.bak" ]; then
      sudo mv "$MKHOOK_BAK/${h}.hook.bak" "$MKHOOK_DIR/${h}.hook" 2>/dev/null || true
    fi
  done
}
trap _restore_mkhooks EXIT
for h in 60-mkinitcpio-remove 90-mkinitcpio-install; do
  if [ -f "$MKHOOK_DIR/${h}.hook" ] && [ ! -f "$MKHOOK_BAK/${h}.hook.bak" ]; then
    sudo mv "$MKHOOK_DIR/${h}.hook" "$MKHOOK_BAK/${h}.hook.bak"
  fi
done

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

# WiFi/BT cards needing out-of-tree drivers. MT7921/MT7925 work with
# in-tree mt79{21,25}e + linux-firmware and don't need anything here.
case "$NET_INFO" in
  *MT7927*) AUR_PACKAGES+=(mediatek-mt7927-dkms) ;;
esac

paru -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# Flatpak (sandboxed apps)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --noninteractive flathub io.gitlab.librewolf-community

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
# Hyprland writes a default ~/.config/hypr/hyprland.conf on first launch.
# If the user logged into a Hyprland session between pacman -S and stow
# (e.g. via greetd, or a re-run after first boot), that autogen file
# blocks stow on the entire hyprland package — stow refuses to clobber a
# non-symlink and aborts every link in the package on a single conflict.
backup_if_exists ~/.config/hypr/hyprland.conf
if [ -d "$BACKUP_DIR" ]; then
    echo "  Backups saved to $BACKUP_DIR"
fi

# Remove non-symlink conflicts. Safe now: unstow above removed every
# stow-managed symlink, so no rm here can traverse into the repo.
rm -f ~/.zshenv ~/.gitconfig
rm -f ~/.config/zsh/.zshrc ~/.config/zsh/.zprofile ~/.config/zsh/.p10k.zsh
rm -f ~/.config/awww/set-wallpaper.sh
rm -f ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini
rm -f ~/.config/qt6ct/qt6ct.conf
# matugen dir is stow-managed; unstow above already cleared its symlinks.
# Avoid rm -rf here so any user-added templates survive a re-run.
rm -f ~/.config/uwsm/env ~/.config/uwsm/env-hyprland
rm -f ~/.config/systemd/user/nilnotify.service ~/.config/systemd/user/awww.service
rm -f ~/.config/hypr/hyprland.conf

# --no-folding creates individual file symlinks rather than folding a
# package into one dir symlink. This keeps runtime writes (systemd
# enablements, matugen output) in the real filesystem instead of
# silently ending up in the repo via a directory symlink.
for dir in "${STOW_PACKAGES[@]}"; do
    echo "  Stowing $dir..."
    # No `|| true` here: stow exits non-zero on conflict (and aborts the
    # whole package), so we want set -e to fire. Otherwise a single
    # missed entry in the conflict list above silently leaves a package
    # un-stowed and the rest of the install marches on, none the wiser.
    stow --no-folding "$dir"
done

# --- 5. System configs (symlinks to dotfiles) ---
echo "Applying system configs..."

# TLP (only on machines with a battery)
if [ $HAS_BATTERY = 1 ]; then
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

# Boot optimization: timeout 0 skips systemd-boot menu entirely.
# Replace existing timeout line or append if missing (sed's in-place
# substitution is a no-op on absent lines, which would silently leave
# the loader at base-install's default of 4s).
# sudo test: /boot is root-only (umask=0077 from base-install), so a
# bare `[ -f ]` as the user fails silently and the whole block skips.
if sudo test -f /boot/loader/loader.conf; then
  if sudo grep -q '^timeout' /boot/loader/loader.conf; then
    sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf
  else
    echo "timeout 0" | sudo tee -a /boot/loader/loader.conf > /dev/null
  fi
fi

# Silent boot
sudo mkdir -p /etc/cmdline.d
sudo tee /etc/cmdline.d/silent.conf > /dev/null << 'SILENT'
quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3
SILENT

# AMD SME (memory encryption). Silently ignored on Intel, so gate by vendor.
if grep -q AuthenticAMD /proc/cpuinfo; then
  sudo tee /etc/cmdline.d/mem-encrypt.conf > /dev/null << 'MEMENC'
mem_encrypt=on
MEMENC
fi

# KSPP-recommended runtime hardening (https://kspp.github.io/Recommended_Settings).
# slab_nomerge / init_on_*: mitigate heap exploits. page_alloc.shuffle:
# randomize freelists. randomize_kstack_offset: per-syscall kstack ASLR.
# vsyscall=none: remove legacy vsyscall page.
#
# Intentionally OMITTED (break DKMS / userspace tools on this setup):
# - module.sig_enforce=1 and lockdown=confidentiality would refuse to
#   load any DKMS module (Arch only signs in-tree modules with an
#   ephemeral per-build key), which would break mediatek-mt7927-dkms
#   (on machines that have MT7927) and any future DKMS module
# - debugfs=off breaks amdgpu-top, partially breaks powertop, and
#   blocks ryzenadj MSR access. Lockdown already implied the same.
sudo tee /etc/cmdline.d/hardening.conf > /dev/null << 'HARDENING'
slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none
HARDENING

# DMA protection (Thunderbolt/PCIe). iommu=pt is intentionally absent:
# per kernel docs force_isolation explicitly does NOT override iommu=pt,
# so pt would defeat the isolation. intel_iommu=on is a no-op on AMD.
sudo tee /etc/cmdline.d/iommu.conf > /dev/null << 'IOMMU'
amd_iommu=force_isolation intel_iommu=on iommu.passthrough=0 iommu.strict=1
IOMMU

# --- 6. Security hardening ---
echo "Applying security hardening..."

# Firewall (ufw)
echo "  Configuring firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

# Encrypted DNS (DNS-over-TLS via systemd-resolved). resolved must be
# running before resolv.conf is pointed at its stub, or DNS dies on the
# next NM reload until reboot.
echo "  Configuring encrypted DNS..."
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/dns-over-tls.conf > /dev/null << 'DNS'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=9.9.9.9#dns.quad9.net
DNSOverTLS=true
DNSSEC=allow-downgrade
Domains=~.
DNS
sudo systemctl enable --now systemd-resolved
sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null << 'NMDNS'
[main]
dns=systemd-resolved
NMDNS
sudo systemctl reload NetworkManager 2>/dev/null || true

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

# Restrict ptrace to parent processes only (scope=1 still allows IDE
# debuggers like VS Code to attach to their own children; scope=2/3
# would break that)
kernel.yama.ptrace_scope = 1

# Block kexec-based kernel replacement at runtime
kernel.kexec_load_disabled = 1

# Restrict perf_event_open (2 = deny tracepoints + raw + CPU events
# for unprivileged users; value 3 is a Debian downstream patch only)
kernel.perf_event_paranoid = 2

# File creation hardening (protect against hardlink/symlink/FIFO
# races in world-writable dirs like /tmp)
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# Network hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
SYSCTL
sudo sysctl --system >/dev/null

# PAM login delay (4s between attempts) + faillock (lockout after N).
# pam_faillock is already wired into /etc/pam.d/system-auth by the
# Arch pambase package; only faillock.conf needs thresholds.
echo "  Configuring login delay and lockout..."
if ! grep -q "pam_faildelay" /etc/pam.d/system-login 2>/dev/null; then
  sudo sed -i '0,/^auth/{s/^auth/auth       optional   pam_faildelay.so delay=4000000\nauth/}' /etc/pam.d/system-login
fi
sudo tee /etc/security/faillock.conf > /dev/null << 'FAILLOCK'
# Lock account after 5 failures within 15 min, for 10 min. Root is
# exempt by default (add even_deny_root to include it — risky).
deny = 5
unlock_time = 600
fail_interval = 900
FAILLOCK

# USBGuard (whitelist current devices, block unknown)
echo "  Configuring USBGuard..."
if [ ! -f /etc/usbguard/rules.conf ] || [ ! -s /etc/usbguard/rules.conf ]; then
  sudo sh -c 'usbguard generate-policy > /etc/usbguard/rules.conf'
  sudo chmod 600 /etc/usbguard/rules.conf
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

# (sbctl package ships /usr/share/libalpm/hooks/zz-sbctl.hook which auto-
# signs EFI binaries on any boot/* or vmlinuz update, so no custom hook
# is needed here.) Clean up the old custom hook if a prior install wrote it.
sudo rm -f /etc/pacman.d/hooks/95-sbctl-sign.hook

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
sudo systemctl enable usbguard-dbus.service
sudo systemctl enable docker.socket
sudo systemctl enable warp-svc
sudo systemctl start warp-svc 2>/dev/null || echo "  warp-svc start deferred (will auto-start on next boot)"

if [ $HAS_BATTERY = 1 ]; then
  sudo systemctl enable tlp
fi

# Enable user services here (not in .zprofile): greetd → uwsm → Hyprland
# never spawns a zsh login shell, so zprofile would never run on first
# boot. Start them too, but only when graphical-session.target is
# already active — on a first install we're in a TTY and starting
# waybar/awww/hypridle/hyprpolkitagent/nilnotify there fails (no
# Wayland socket, no Hyprland IPC) and aborts install.sh via set -e.
systemctl --user daemon-reload
USER_SERVICES=(waybar hypridle hyprpolkitagent
  pipewire pipewire-pulse wireplumber nilnotify awww)
systemctl --user enable "${USER_SERVICES[@]}"
if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start "${USER_SERVICES[@]}"
fi

# --- 8. Shell and groups ---
echo "Setting default shell and groups..."
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/zsh" ]; then
  sudo chsh -s /usr/bin/zsh "$USER"
  echo "  Shell changed to zsh (takes effect on next login)"
fi
if ! groups "$USER" | grep -q '\bdocker\b'; then
  sudo usermod -aG docker "$USER"
  echo "  Added $USER to docker group (takes effect on next login)"
fi

# --- 9. Create directories and copy wallpapers ---
echo "Setting up directories and wallpapers..."
# Canonical XDG user directories (Desktop, Documents, Downloads, etc.).
# Community-standard alternative to hand-rolled mkdir of ~/Pictures etc.
xdg-user-dirs-update
mkdir -p ~/Pictures/Wallpapers ~/Pictures/Screenshots
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
  # Seed with safe defaults so rofi doesn't spam "var failed to resolve"
  # warnings and render unthemed if rofi is launched before matugen runs
  # (or if matugen fails — e.g. no p0.webp on a minimal wallpaper set).
  cat > ~/.config/rofi/colors.rasi << 'ROFI_COLORS'
* {
    bg: #1a1a2e;
    bg-alpha: #1a1a2ee6;
    fg: #e0e0e0;
    accent: #7c7cff;
    on-accent: #1a1a2e;
    urgent: #ff6b6b;
    muted: #a0a0a0;
    surface: #252540;
    outline: #606060;
}
ROFI_COLORS
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

# --- Secure Boot keys (before mkinitcpio so sign loop can pick up fresh UKIs) ---
echo "Setting up Secure Boot..."
sudo pacman -S --needed --noconfirm sbctl tpm2-tss

if [ ! -f /var/lib/sbctl/keys/PK/PK.key ]; then
  echo "Creating Secure Boot keys..."
  sudo sbctl create-keys
else
  echo "  Secure Boot keys already exist, skipping creation"
fi
# enroll-keys needs the firmware in Setup Mode (factory keys cleared in
# BIOS). On a first install that's not the case yet, so don't let a
# nonzero exit kill the rest of the script — TPM enrollment and the
# post-install instructions still need to run. The Post-install block
# already tells the user to reboot, clear keys in BIOS, and re-run.
if ! sudo sbctl enroll-keys -m; then
  echo "  enroll-keys deferred (BIOS not in Setup Mode — see Post-install below)"
fi

# Regenerate UKIs (picks up silent boot / iommu / hardening cmdline drop-ins)
sudo mkinitcpio -P

echo "Signing boot files..."
for uki in /boot/EFI/Linux/*.efi; do
  [ -f "$uki" ] && sudo sbctl sign -s "$uki"
done
sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
# Also sign the EFI fallback path. bootctl install copies systemd-boot
# to /boot/EFI/BOOT/BOOTX64.EFI as the spec-mandated removable-media
# fallback; firmware that ignores the NVRAM entry (Framework, Macs,
# anything after an NVRAM reset) boots this copy instead, and an
# unsigned fallback bricks boot the moment Secure Boot is enabled.
[ -f /boot/EFI/BOOT/BOOTX64.EFI ] && sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
# Non-fatal: sbctl verify returns non-zero if any file is unsigned, but
# that's informational here, not a reason to abort the whole installer.
sudo sbctl verify || true

echo ""
echo "=== Installation complete ==="
echo ""

# --- TPM2 auto-unlock (requires Secure Boot already enabled in BIOS) ---
# PCR set per systemd-cryptenroll(1): "bound to some combination of PCRs
# 7, 11, and 14 (if shim/MOK is used). ... not advisable to use PCRs such
# as 0 and 2, since the program code they cover should already be covered
# indirectly through the certificates measured into PCR 7."
if sbctl status 2>/dev/null | grep -q "Secure Boot.*[Ee]nabled"; then
  LUKS_DEV=$(awk '/rd.luks.name/ {match($0, /rd.luks.name=([a-f0-9-]+)/, m); print m[1]}' /etc/cmdline.d/root.conf 2>/dev/null || true)
  if [ -n "$LUKS_DEV" ]; then
    LUKS_DEVICE="/dev/disk/by-uuid/$LUKS_DEV"
    if sudo cryptsetup luksDump "$LUKS_DEVICE" | grep -q systemd-tpm2; then
      echo "  TPM2 already enrolled, skipping"
    else
      echo "Enrolling TPM2 key (you will be asked for your LUKS password, then set a TPM PIN)..."
      sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7+11 --tpm2-with-pin=yes "$LUKS_DEVICE"
      echo "TPM2 auto-unlock configured (PIN required on boot)."
    fi
  fi
fi

echo ""
echo "=== Post-install ==="
if ! sbctl status 2>/dev/null | grep -q "Secure Boot.*[Ee]nabled"; then
  echo "  1. Reboot into BIOS, enable Secure Boot"
  echo "  2. Boot into system, re-run ./install.sh (will enroll TPM2 automatically)"
fi
echo "  - Register Cloudflare WARP:  warp-cli registration new"
echo "  - Connect WARP:              warp-cli connect"
echo "  - Verify:                    warp-cli status"
