#!/bin/bash
set -euo pipefail

[ "$EUID" -eq 0 ] || exit 1
[ "$(uname -m)" = "x86_64" ] || exit 1
[ -d /sys/firmware/efi ] || exit 1
command -v pacstrap >/dev/null || exit 1

loadkeys pl
timedatectl set-ntp true
sleep 1

pacman -Sy --needed --noconfirm archlinux-keyring

DISK="/dev/nvme0n1"
ESP="${DISK}p1"
LUKS_PART="${DISK}p2"
CRYPT_NAME="root"
HOSTNAME="arch"
USERNAME="nil"
TIMEZONE="Europe/Warsaw"
LOCALE="en_US.UTF-8"
KEYMAP="pl"

ls /sys/class/power_supply/BAT* &>/dev/null && HAS_BATTERY=1 || HAS_BATTERY=0

GPU_INFO=$(lspci -nn | grep -iE "vga|3d|display" || true)
GPU_NVIDIA=0; echo "$GPU_INFO" | grep -qi "NVIDIA"          && GPU_NVIDIA=1
GPU_AMD=0;    echo "$GPU_INFO" | grep -qiE "AMD|ATI|Radeon" && GPU_AMD=1
GPU_INTEL=0;  echo "$GPU_INFO" | grep -qi "Intel"           && GPU_INTEL=1

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

if grep -q GenuineIntel /proc/cpuinfo; then
    UCODE="intel-ucode"
else
    UCODE="amd-ucode"
fi

read -p "Wipe $DISK? [y/N] " confirm
[[ "$confirm" == [yY] ]] || exit 1

swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
for m in /dev/mapper/*; do
    [ "$m" = "/dev/mapper/control" ] && continue
    [ -e "$m" ] || continue
    cryptsetup close "$(basename "$m")" 2>/dev/null || true
done
partprobe "$DISK" 2>/dev/null || true

sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 "$DISK"
sgdisk -n 2:0:0 -t 2:8309 "$DISK"
partprobe "$DISK"

wipefs -a "$LUKS_PART" "$ESP"
cryptsetup luksFormat \
    --type luks2 \
    --pbkdf argon2id \
    --hash sha512 \
    --key-size 512 \
    --use-urandom \
    "$LUKS_PART"
cryptsetup open "$LUKS_PART" "$CRYPT_NAME"

mkfs.ext4 -q "/dev/mapper/$CRYPT_NAME"
mkfs.fat -F 32 "$ESP"

mount "/dev/mapper/$CRYPT_NAME" /mnt
mount --mkdir -o umask=0077,noatime "$ESP" /mnt/boot

pacstrap -K /mnt \
    base linux linux-firmware \
    "$UCODE" "${EXTRA_PKGS[@]}" \
    nano networkmanager \
    cryptsetup sudo git stow base-devel

genfstab -U /mnt >> /mnt/etc/fstab

LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PART")

cat > /mnt/root/chroot-setup.sh << CHROOT
#!/bin/bash
set -euo pipefail

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

sed -i 's/^#en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#pl_PL\.UTF-8 UTF-8/pl_PL.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

echo "$HOSTNAME" > /etc/hostname

sed -i 's/^MODULES=.*/MODULES=($MKINITCPIO_MODULES)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf

mkdir -p /etc/cmdline.d
# rd.luks.options=UUID=tpm2-device=auto tells sd-encrypt to attempt TPM2
# unlock before falling back to the passphrase prompt. Per Arch Wiki
# (dm-crypt/System configuration § Trusted Platform Module and FIDO2 keys),
# this option must be set in addition to rd.luks.name. The per-UUID form
# scopes the option to this specific LUKS volume so a future second
# encrypted device isn't accidentally auto-unlocked too.
echo "rd.luks.name=${LUKS_UUID}=root rd.luks.options=${LUKS_UUID}=tpm2-device=auto root=/dev/mapper/root rw" > /etc/cmdline.d/root.conf
if [ "$GPU_NVIDIA" = "1" ]; then
  echo "nvidia_drm.modeset=1 nvidia_drm.fbdev=1" > /etc/cmdline.d/nvidia.conf
fi

cat > /etc/mkinitcpio.d/linux.preset << 'PRESET'
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

default_uki="/boot/EFI/Linux/arch-linux.efi"

fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
PRESET

mkdir -p /boot/EFI/Linux
bootctl install

cat > /boot/loader/loader.conf << 'LOADER'
default  arch-linux.efi
timeout  4
console-mode max
editor   no
LOADER

mkinitcpio -p linux

passwd

useradd -m -G wheel -s /bin/bash $USERNAME
passwd $USERNAME
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager.service
systemctl enable systemd-boot-update.service
CHROOT

chmod +x /mnt/root/chroot-setup.sh
arch-chroot /mnt /root/chroot-setup.sh
rm /mnt/root/chroot-setup.sh

arch-chroot /mnt /bin/bash -c "
    su - $USERNAME -c '
        git clone https://github.com/jedrzejratajczak/dotfiles.git ~/.dotfiles
    '
"

umount -R /mnt
cryptsetup close "$CRYPT_NAME"
