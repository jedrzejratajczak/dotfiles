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

# Live-ISO setup: Polish keyboard for LUKS password, NTP for HTTPS cert validity.
loadkeys pl
timedatectl set-ntp true

DISK="/dev/nvme0n1"
ESP="${DISK}p1"
LUKS_PART="${DISK}p2"
CRYPT_NAME="root"
HOSTNAME="arch"
USERNAME="nil"
TIMEZONE="Europe/Warsaw"
LOCALE="en_US.UTF-8"
KEYMAP="pl"

if ls /sys/class/power_supply/BAT* &>/dev/null; then
    PROFILE="laptop"
    EXTRA_PKGS=(sof-firmware)
    MKINITCPIO_MODULES="amdgpu"
    NET_HINT="WiFi: nmcli device wifi connect <SSID> password <pass>"
else
    PROFILE="desktop"
    EXTRA_PKGS=(nvidia-open)
    MKINITCPIO_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
    NET_HINT="ethernet"
fi

echo "=== Arch Linux base install ($PROFILE) ==="
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

# --- 2. Encryption ---
echo "[2/9] Setting up LUKS2 encryption..."
wipefs -a "$LUKS_PART" "$ESP"
echo "Enter disk encryption password:"
cryptsetup luksFormat "$LUKS_PART"
echo "Re-enter password to open:"
cryptsetup open "$LUKS_PART" "$CRYPT_NAME"

# --- 3. Formatting ---
echo "[3/9] Formatting..."
mkfs.ext4 -q "/dev/mapper/$CRYPT_NAME"
mkfs.fat -F 32 "$ESP"

# --- 4. Mounting ---
echo "[4/9] Mounting..."
mount "/dev/mapper/$CRYPT_NAME" /mnt
mount --mkdir "$ESP" /mnt/boot
chmod 700 /mnt/boot

# --- 5. Base install ---
echo "[5/9] Installing base system..."
pacstrap -K /mnt \
    base linux linux-headers linux-firmware \
    amd-ucode "${EXTRA_PKGS[@]}" \
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

# Locale
sed -i 's/^#$LOCALE UTF-8/$LOCALE UTF-8/' /etc/locale.gen
sed -i 's/^#pl_PL.UTF-8 UTF-8/pl_PL.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname

# mkinitcpio
sed -i 's/^MODULES=.*/MODULES=($MKINITCPIO_MODULES)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf

# Kernel command line for UKI
mkdir -p /etc/cmdline.d
echo "rd.luks.name=${LUKS_UUID}=root root=/dev/mapper/root rw" > /etc/cmdline.d/root.conf

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
umount -R /mnt

echo ""
echo "=== Installation complete ==="
echo ""
echo "Remove USB and reboot. After first boot:"
echo "  1. Log in, connect $NET_HINT"
echo "  2. cd ~/.dotfiles && ./install.sh"
echo "  3. Reboot into BIOS, enable Secure Boot"
echo "  4. cd ~/.dotfiles && ./install.sh  (enrolls TPM2 automatically)"
