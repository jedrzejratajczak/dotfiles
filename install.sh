#!/bin/bash
set -euo pipefail

ls /sys/class/power_supply/BAT* &>/dev/null && HAS_BATTERY=1 || HAS_BATTERY=0

if grep -q GenuineIntel /proc/cpuinfo; then
  UCODE="intel-ucode"
else
  UCODE="amd-ucode"
fi

LSPCI=$(lspci -nn)
NET_INFO=$(echo "$LSPCI" | grep -iE "network|wireless" || true)
GPU_INFO=$(echo "$LSPCI" | grep -iE "vga|3d|display" || true)

PACKAGES=(
  zsh stow rofi yazi mpv wl-clipboard wl-clip-persist
  hyprland hyprlock hypridle hyprsunset hyprpolkitagent hyprpicker
  imagemagick brightnessctl swayosd pavucontrol gpu-screen-recorder
  nwg-displays satty waybar kitty
  neovim playerctl grim slurp
  pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  zram-generator
  noto-fonts noto-fonts-emoji ttf-cascadia-code-nerd
  papirus-icon-theme
  uwsm qt6-wayland qt6ct
  eza bat git-delta lazygit
  mise rustup
  docker docker-compose
  fzf jq less xdg-utils xdg-user-dirs
  gst-plugin-pipewire libpulse libnotify
  linux-firmware linux-headers "$UCODE" efibootmgr
  github-cli
  obs-studio kdenlive
  ufw usbguard awww matugen code
  flatpak
  sbctl tpm2-tss
  sof-firmware
  fwupd
  chrony
)

echo "$GPU_INFO" | grep -qi "NVIDIA"          && PACKAGES+=(nvidia-open)
echo "$GPU_INFO" | grep -qiE "AMD|ATI|Radeon" && PACKAGES+=(vulkan-radeon)
echo "$GPU_INFO" | grep -qi "Intel"           && PACKAGES+=(vulkan-intel)
[ $HAS_BATTERY = 1 ]                          && PACKAGES+=(tlp)

sudo pacman -Syu --needed --noconfirm "${PACKAGES[@]}"

rustup default stable
rustup component add rust-src

if ! command -v paru &>/dev/null; then
  rm -rf /tmp/paru
  git clone https://aur.archlinux.org/paru.git /tmp/paru
  (cd /tmp/paru && makepkg -si --noconfirm)
  rm -rf /tmp/paru
fi

AUR_PACKAGES=(
  grimblast-git zsh-theme-powerlevel10k-git pinta
  nilnotify-bin nilpower-bin nilwall-bin nilwidgets-bin
  localsend-bin lazydocker-bin
)

case "$NET_INFO" in
  *MT7927*) AUR_PACKAGES+=(mediatek-mt7927-dkms) ;;
esac

paru -S --needed --noconfirm "${AUR_PACKAGES[@]}"

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --noninteractive flathub io.gitlab.librewolf-community dev.vencord.Vesktop com.heroicgameslauncher.hgl com.valvesoftware.Steam

command -v claude &>/dev/null || curl -fsSL https://claude.ai/install.sh | bash

mise use -g node@lts

cd ~/.dotfiles

STOW_PACKAGES=(
    zsh git kitty hyprland rofi yazi mpv
    waybar gtk matugen uwsm awww systemd claude
)

stow --no-folding "${STOW_PACKAGES[@]}"

[ $HAS_BATTERY = 1 ] && sudo cp "$HOME/.dotfiles/tlp/etc/tlp.conf" /etc/tlp.conf

sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --noreset --noclear --autologin $USER - \${TERM}
Type=simple
EOF

sudo cp "$HOME/.dotfiles/issue/etc/issue" /etc/issue

sudo mkdir -p /etc/systemd/logind.conf.d
sudo cp "$HOME/.dotfiles/logind/etc/systemd/logind.conf.d/power-key.conf" /etc/systemd/logind.conf.d/power-key.conf

sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf

echo "quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3" | sudo tee /etc/cmdline.d/silent.conf > /dev/null
echo "slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none random.trust_cpu=off random.trust_bootloader=off debugfs=off" | sudo tee /etc/cmdline.d/hardening.conf > /dev/null
echo "amd_iommu=force_isolation intel_iommu=on iommu.passthrough=0 iommu.strict=1 efi=disable_early_pci_dma" | sudo tee /etc/cmdline.d/iommu.conf > /dev/null
grep -q AuthenticAMD /proc/cpuinfo && echo "mem_encrypt=on" | sudo tee /etc/cmdline.d/mem-encrypt.conf > /dev/null
sudo chmod 600 /etc/cmdline.d/*.conf

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/dns-over-tls.conf > /dev/null << 'DNS'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=9.9.9.9#dns.quad9.net
DNSOverTLS=true
DNSSEC=allow-downgrade
Domains=~.
LLMNR=no
MulticastDNS=no
DNS
sudo systemctl enable --now systemd-resolved
sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null << 'NMDNS'
[main]
dns=systemd-resolved
NMDNS
sudo systemctl reload NetworkManager 2>/dev/null || true

sudo systemctl disable --now systemd-timesyncd 2>/dev/null || true
sudo tee /etc/chrony.conf > /dev/null << 'CHRONY'
server time.cloudflare.com iburst nts
server nts.netnod.se iburst nts
server time.dfm.dk iburst nts
minsources 2

driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
ntsdumpdir /var/lib/chrony
CHRONY

sudo tee /etc/sysctl.d/99-hardening.conf > /dev/null << 'SYSCTL'
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.sysrq = 176
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
fs.suid_dumpable = 0
kernel.yama.ptrace_scope = 1
kernel.kexec_load_disabled = 1
kernel.perf_event_paranoid = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
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
net.ipv4.tcp_rfc1337 = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
dev.tty.ldisc_autoload = 0
dev.tty.legacy_tiocsti = 0
vm.unprivileged_userfaultfd = 0
vm.mmap_rnd_bits = 32
vm.mmap_rnd_compat_bits = 16
kernel.core_pattern = |/bin/false
SYSCTL
sudo sysctl --system >/dev/null

if ! grep -q "pam_faildelay" /etc/pam.d/system-login 2>/dev/null; then
  sudo sed -i '0,/^auth/{s/^auth/auth       optional   pam_faildelay.so delay=4000000\nauth/}' /etc/pam.d/system-login
fi
sudo tee /etc/security/faillock.conf > /dev/null << 'FAILLOCK'
deny = 5
unlock_time = 600
fail_interval = 900
FAILLOCK

if [ ! -f /etc/usbguard/rules.conf ] || [ ! -s /etc/usbguard/rules.conf ]; then
  sudo sh -c 'usbguard generate-policy > /etc/usbguard/rules.conf'
  sudo chmod 600 /etc/usbguard/rules.conf
fi
sudo sed -i "s|^IPCAllowedUsers=.*|IPCAllowedUsers=$USER|" /etc/usbguard/usbguard-daemon.conf
sudo sed -i 's|^IPCAllowedGroups=.*|IPCAllowedGroups=|' /etc/usbguard/usbguard-daemon.conf

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
connection.llmnr=0
connection.mdns=0
NMPRIVACY

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

sudo mkdir -p /etc/systemd/coredump.conf.d
sudo tee /etc/systemd/coredump.conf.d/disable.conf > /dev/null << 'COREDUMP'
[Coredump]
Storage=none
ProcessSizeMax=0
COREDUMP

sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/limits.conf > /dev/null << 'JOURNAL'
[Journal]
Storage=persistent
SystemMaxUse=500M
JOURNAL

sudo tee /etc/modprobe.d/blacklist-rare.conf > /dev/null << 'BLACKLIST'
blacklist dccp
blacklist sctp
blacklist rds
blacklist tipc
blacklist cramfs
blacklist freevxfs
blacklist jffs2
blacklist hfs
blacklist hfsplus
blacklist udf
blacklist firewire-core
blacklist firewire-ohci
blacklist firewire-sbp2
blacklist vivid
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true
install firewire-core /bin/true
install firewire-ohci /bin/true
install firewire-sbp2 /bin/true
install vivid /bin/true
BLACKLIST

sudo sed -i 's/^UMASK\s.*/UMASK 077/' /etc/login.defs
sudo sed -i 's/^HOME_MODE\s.*/HOME_MODE 0700/' /etc/login.defs

sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null << 'DOCKERD'
{
  "userns-remap": "default",
  "no-new-privileges": true,
  "icc": false,
  "live-restore": true
}
DOCKERD

sudo sed -i -E '/^[[:space:]]*[^#]*[[:space:]]+\/(tmp|dev\/shm)[[:space:]]/d' /etc/fstab
echo 'tmpfs   /tmp     tmpfs   nosuid,nodev,noexec,size=50%,mode=1777   0   0' | sudo tee -a /etc/fstab > /dev/null
echo 'tmpfs   /dev/shm tmpfs   nosuid,nodev,noexec                      0   0' | sudo tee -a /etc/fstab > /dev/null

sudo systemctl enable getty@tty1.service NetworkManager ufw usbguard usbguard-dbus.service docker.socket fwupd-refresh.timer chronyd.service
sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
[ $HAS_BATTERY = 1 ] && sudo systemctl enable tlp

systemctl --user daemon-reload
USER_SERVICES=(waybar hypridle hyprpolkitagent
  pipewire pipewire-pulse wireplumber nilnotify awww)
systemctl --user enable "${USER_SERVICES[@]}"
if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start "${USER_SERVICES[@]}"
fi

[ "$(getent passwd "$USER" | cut -d: -f7)" = "/usr/bin/zsh" ] || sudo chsh -s /usr/bin/zsh "$USER"
groups "$USER" | grep -q '\bdocker\b' || sudo usermod -aG docker "$USER"

xdg-user-dirs-update
mkdir -p ~/Pictures/Wallpapers ~/Pictures/Screenshots \
         ~/.config/qt6ct/colors ~/.config/nilnotify ~/.config/nilwall \
         ~/.local/state/zsh

sed "s|__HOME__|$HOME|" ~/.dotfiles/qt6ct/.config/qt6ct/qt6ct.conf > ~/.config/qt6ct/qt6ct.conf

sudo tee /etc/systemd/zram-generator.conf > /dev/null << 'ZRAM'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRAM

[ -f ~/.config/hypr/monitors.conf ] || echo "monitor = , preferred, auto, auto" > ~/.config/hypr/monitors.conf

cp -n ~/.dotfiles/wallpapers/* ~/Pictures/Wallpapers/ 2>/dev/null || true
WALLPAPER=$(find ~/Pictures/Wallpapers -maxdepth 1 -name '*.webp' -print -quit 2>/dev/null)
[ -n "$WALLPAPER" ] && matugen image "$WALLPAPER" -m dark -t scheme-tonal-spot

[ -f /var/lib/sbctl/keys/PK/PK.key ] || sudo sbctl create-keys

sudo mkinitcpio -P

sudo find /boot -type f \( -name '*.efi' -o -iname 'BOOTX64.EFI' -o -name 'vmlinuz-linux' \) -exec sbctl sign -s {} \;

if sudo sbctl status --json | jq -e '.setup_mode == true' >/dev/null; then
  sudo sbctl enroll-keys --microsoft
  sudo sbctl sign-all
fi
