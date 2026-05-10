# Arch Linux + Hyprland dotfiles

LUKS2, Secure Boot, TPM2 + PIN, ufw, USBGuard, DNS-over-TLS, kernel hardening, DMA protection.

## Install

### 1. BIOS

- Set Supervisor Password
- Secure Boot: **Disabled**
- USB Boot: **Enabled**
- Clear / Erase / Reset Platform Keys (board-specific menu name — puts firmware into Setup Mode)

### 2. Live USB

Connect to Wi-Fi:

```bash
iwctl station wlan0 scan
iwctl station wlan0 connect "SSID"
ping -c 3 archlinux.org
```

Install:

```bash
curl -LO https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main/base-install.sh
bash base-install.sh
```

### 3. First boot

```bash
nmcli device wifi connect "SSID" password "pass"
~/.dotfiles/install.sh
```

### 4. BIOS

- Secure Boot: **Enabled**
- USB Boot: **Disabled**

### 5. Second boot — enroll TPM

```bash
~/.dotfiles/post-install.sh
```

## After BIOS update

```bash
~/.dotfiles/tpm-reenroll.sh
```
