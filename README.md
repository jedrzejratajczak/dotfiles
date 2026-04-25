# Arch Linux + Hyprland dotfiles

LUKS2, Secure Boot, TPM2 + PIN, ufw, USBGuard, DNS-over-TLS, kernel hardening, DMA protection.

## Install

### 1. BIOS

- Set Supervisor Password
- Secure Boot: **Disabled**
- USB Boot: **Enabled**

### 2. Live USB

Connect to Wi-Fi:

```bash
iwctl
# station wlan0 scan
# station wlan0 connect "SSID"
# exit
ping -c 3 archlinux.org
```

Install:

```bash
# If you have the install pendrive (with bootstrap.sh):
mount /dev/sdX1 /mnt && bash /mnt/bootstrap.sh

# Otherwise, fetch base-install directly:
curl -LO https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main/machines/base-install.sh
chmod +x base-install.sh
./base-install.sh
```

Then `poweroff`.

### 3. First boot

Connect to Wi-Fi:

```bash
nmcli device wifi connect "SSID" password "pass"
```

Install:

```bash
cd ~/.dotfiles
./install.sh
sudo reboot
```

### 4. BIOS

- Secure Boot: **Enabled**
- USB Boot: **Disabled**

### 5. Second boot

```bash
cd ~/.dotfiles
./install.sh
warp-cli registration new && warp-cli connect
```

## After BIOS update

```bash
cd ~/.dotfiles && ./tpm-reenroll.sh
```
