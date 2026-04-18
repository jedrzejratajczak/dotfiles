# Arch Linux + Hyprland dotfiles

LUKS2 full-disk encryption, Secure Boot (sbctl-managed keys), TPM2 auto-unlock with PIN, ufw, USBGuard, DNS-over-TLS, kernel hardening (kptr/dmesg/bpf/ptrace), DMA protection (IOMMU).

## Install

### 1. BIOS

- Set Supervisor Password
- Secure Boot: **Disabled**
- USB Boot: **Enabled**

### 2. Connect to Wi-Fi

```bash
iwctl
# station wlan0 scan
# station wlan0 connect "SSID"
# exit
ping -c 3 archlinux.org
```

### 3. Base install

```bash
curl -LO https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main/machines/base-install.sh
chmod +x base-install.sh
./base-install.sh
poweroff
```

### 4. First boot, connect Wi-Fi (laptop)

```bash
nmcli device wifi connect "SSID" password "pass"
```

### 5. Environment

```bash
cd ~/.dotfiles
./install.sh
sudo reboot
```

### 6. BIOS

- Secure Boot: **Enabled**

### 7. Environment (second pass, TPM enrollment)

```bash
cd ~/.dotfiles
./install.sh
```

Enter LUKS password, then set a TPM PIN.

### 8. BIOS lockdown

- USB Boot: **Disabled**

### 9. Post-install

```bash
warp-cli registration new && warp-cli connect
```

## After BIOS/firmware update

PCR values change and TPM unlock fails. Boot with LUKS password, then:

```bash
cd ~/.dotfiles && ./tpm-reenroll.sh
```

## Machine-specific

`~/.config/zsh/local.zsh` is gitignored for per-machine aliases and SSH configs.
