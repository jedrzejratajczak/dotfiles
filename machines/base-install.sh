#!/bin/bash
set -euo pipefail

# Base install script for Arch Linux on a fresh machine.
# Disk:     Single NVMe -> LUKS2 + ext4, no swap
# Boot:     systemd-boot + UKI + sd-encrypt
# Profile:  Auto-detected from /sys/class/power_supply/BAT*
#
# Usage: Boot Arch ISO, then:
#   curl -LO https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main/machines/base-install.sh
#   chmod +x base-install.sh
#   ./base-install.sh

# Tee everything to a log so a failed install leaves breadcrumbs.
# Copied into the target at /mnt/var/log/ on success.
LOG="/tmp/base-install.log"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1
trap 'echo "[base-install FAILED at line $LINENO, exit $?]. Full log: $LOG" >&2' ERR

# Preflight guards — fail early with a clear message instead of a
# half-corrupted disk halfway through.
[ "$EUID" -eq 0 ] || { echo "Must run as root (live ISO boots root by default)" >&2; exit 1; }
[ "$(uname -m)" = "x86_64" ] || { echo "x86_64 only (arch: $(uname -m))" >&2; exit 1; }
[ -d /sys/firmware/efi ] || { echo "UEFI firmware required (missing /sys/firmware/efi)" >&2; exit 1; }
command -v pacstrap >/dev/null || { echo "Not on Arch install ISO (pacstrap missing)" >&2; exit 1; }

# Live-ISO setup: Polish keyboard for LUKS password, NTP for HTTPS cert validity.
loadkeys pl
timedatectl set-ntp true

# pacman hits mirrors over HTTPS; clock skew > ~5min causes TLS cert
# errors. Poll until timesyncd converges (archinstall pattern).
echo "Waiting for NTP sync (up to 30s)..."
for _ in $(seq 30); do
    if [ "$(timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo no)" = "yes" ]; then
        break
    fi
    sleep 1
done

DISK="/dev/nvme0n1"
ESP="${DISK}p1"
LUKS_PART="${DISK}p2"
CRYPT_NAME="root"
HOSTNAME="arch"
USERNAME="nil"
TIMEZONE="Europe/Warsaw"
LOCALE="en_US.UTF-8"
KEYMAP="pl"

# Hardware detection (per component, not per machine profile).
ls /sys/class/power_supply/BAT* &>/dev/null && HAS_BATTERY=1 || HAS_BATTERY=0
NET_HINT=$([ $HAS_BATTERY = 1 ] \
    && echo "WiFi: nmcli device wifi connect <SSID> password <pass>" \
    || echo "ethernet")

GPU_INFO=$(lspci -nn | grep -iE "vga|3d|display" || true)
GPU_NVIDIA=0; echo "$GPU_INFO" | grep -qi "NVIDIA"          && GPU_NVIDIA=1
GPU_AMD=0;    echo "$GPU_INFO" | grep -qiE "AMD|ATI|Radeon" && GPU_AMD=1
GPU_INTEL=0;  echo "$GPU_INFO" | grep -qi "Intel"           && GPU_INTEL=1

# SOF firmware unconditional (~10MB, harmless where unused).
EXTRA_PKGS=(sof-firmware)
MKINITCPIO_MODULES=""
if [ $GPU_NVIDIA = 1 ]; then
    EXTRA_PKGS+=(nvidia-open)
    MKINITCPIO_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
elif [ $GPU_AMD = 1 ]; then
    EXTRA_PKGS+=(vulkan-radeon)
    MKINITCPIO_MODULES="amdgpu"
elif [ $GPU_INTEL = 1 ]; then
    EXTRA_PKGS+=(vulkan-intel)
    MKINITCPIO_MODULES="i915"
fi

# CPU microcode package based on vendor (hardcoding amd-ucode breaks Intel).
if grep -q GenuineIntel /proc/cpuinfo; then
    UCODE="intel-ucode"
else
    UCODE="amd-ucode"
fi

echo "=== Arch Linux base install ==="
echo ""
echo "Disk:     $DISK"
echo "Hostname: $HOSTNAME"
echo "User:     $USERNAME"
echo ""
echo "WARNING: This will WIPE $DISK completely."
read -p "Continue? [y/N] " confirm
[[ "$confirm" == [yY] ]] || exit 1

# --- 1. Partitioning ---
echo "[1/9] Partitioning..."
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"
sgdisk -n 2:0:0 -t 2:8309 "$DISK"
# Force kernel to re-read the new partition table before the next
# command tries to open $LUKS_PART (cryptsetup can race sgdisk otherwise).
partprobe "$DISK"

# --- 2. Encryption ---
echo "[2/9] Setting up LUKS2 encryption..."
wipefs -a "$LUKS_PART" "$ESP"
echo "Enter disk encryption password:"
# Pin crypto explicitly rather than relying on cryptsetup defaults:
# LUKS2 + argon2id + sha512 + 512-bit XTS (matches archinstall/alis).
cryptsetup luksFormat \
    --type luks2 \
    --pbkdf argon2id \
    --hash sha512 \
    --key-size 512 \
    --use-urandom \
    "$LUKS_PART"
echo "Re-enter password to open:"
cryptsetup open "$LUKS_PART" "$CRYPT_NAME"

# --- 3. Formatting ---
echo "[3/9] Formatting..."
mkfs.ext4 -q "/dev/mapper/$CRYPT_NAME"
mkfs.fat -F 32 "$ESP"

# --- 4. Mounting ---
echo "[4/9] Mounting..."
mount "/dev/mapper/$CRYPT_NAME" /mnt
# fmask/dmask enforce root-only perms on FAT (chmod is ignored on vfat).
# umask=0077 covers both in one. noatime avoids needless FAT writes.
mount --mkdir -o umask=0077,noatime "$ESP" /mnt/boot

# --- 5. Base install ---
echo "[5/9] Installing base system..."
pacstrap -K /mnt \
    base linux linux-firmware \
    "$UCODE" "${EXTRA_PKGS[@]}" \
    nano networkmanager \
    cryptsetup sudo git stow base-devel

# --- 6. Fstab ---
echo "[6/9] Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- 7. System configuration (in chroot) ---
echo "[7/9] Configuring system..."
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PART")

cat > /mnt/root/chroot-setup.sh << CHROOT
#!/bin/bash
set -euo pipefail

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale (dots escaped so sed regex doesn't wildcard-match them)
sed -i 's/^#en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#pl_PL\.UTF-8 UTF-8/pl_PL.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname

# mkinitcpio
sed -i 's/^MODULES=.*/MODULES=($MKINITCPIO_MODULES)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf

# Kernel command line for UKI
mkdir -p /etc/cmdline.d
echo "rd.luks.name=${LUKS_UUID}=root root=/dev/mapper/root rw" > /etc/cmdline.d/root.conf
if [ "$GPU_NVIDIA" = "1" ]; then
  # Belt-and-suspenders: nvidia-utils ships a modprobe conf with
  # modeset=1, but setting it at cmdline ensures early KMS even if a
  # later package ever strips that modprobe drop-in.
  echo "nvidia_drm.modeset=1 nvidia_drm.fbdev=1" > /etc/cmdline.d/nvidia.conf
fi

# UKI preset
cat > /etc/mkinitcpio.d/linux.preset << 'PRESET'
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

#default_image="/boot/initramfs-linux.img"
default_uki="/boot/EFI/Linux/arch-linux.efi"

#fallback_image="/boot/initramfs-linux-fallback.img"
fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
PRESET

# systemd-boot
mkdir -p /boot/EFI/Linux
bootctl install

cat > /boot/loader/loader.conf << 'LOADER'
default  arch-linux.efi
timeout  4
console-mode max
editor   no
LOADER

# Generate UKIs
mkinitcpio -p linux

# Root password
echo "Set root password:"
passwd

# User
useradd -m -G wheel -s /bin/bash $USERNAME
echo "Set password for $USERNAME:"
passwd $USERNAME
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable services
systemctl enable NetworkManager.service
systemctl enable systemd-boot-update.service
CHROOT

chmod +x /mnt/root/chroot-setup.sh
arch-chroot /mnt /root/chroot-setup.sh
rm /mnt/root/chroot-setup.sh

# --- 8. Clone dotfiles ---
echo "[8/9] Cloning dotfiles..."
arch-chroot /mnt /bin/bash -c "
    su - $USERNAME -c '
        git clone https://github.com/jedrzejratajczak/dotfiles.git ~/.dotfiles
    '
"

# --- 9. Done ---
echo "[9/9] Cleaning up..."
# Preserve the install log on the target so post-install debugging can
# read it after reboot. Before umount since /mnt is about to disappear.
mkdir -p /mnt/var/log
cp "$LOG" /mnt/var/log/base-install.log || true
umount -R /mnt
# umount doesn't tear down the LUKS mapper; close it explicitly so a
# second script run can re-open the same name without "already in use".
cryptsetup close "$CRYPT_NAME"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Remove USB and reboot. After first boot:"
echo "  1. Log in, connect $NET_HINT"
echo "  2. cd ~/.dotfiles && ./install.sh"
echo "  3. Reboot into BIOS, enable Secure Boot"
echo "  4. cd ~/.dotfiles && ./install.sh  (enrolls TPM2 automatically)"
