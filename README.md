# dotfiles

Arch Linux + Hyprland with LUKS2, Secure Boot (sbctl), TPM2 auto-unlock with PIN.

## Fresh install

### 1. BIOS

- Set Supervisor Password
- Secure Boot: **Disabled**
- USB Boot: **Enabled**
- Network Stack: **Disabled**
- (Desktop only) Disable CSM, enable fTPM, enable EXPO

### 2. Boot Arch ISO, connect to network

```bash
loadkeys pl
timedatectl set-ntp true
```

Wi-Fi:

```bash
iwctl
# station wlan0 scan
# station wlan0 connect "SSID"
# exit
ping -c 3 archlinux.org
```

### 3. Base install

Desktop:

```bash
curl -LO https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main/machines/desktop/base-install.sh
```

Laptop:

```bash
curl -LO https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main/machines/laptop/base-install.sh
```

```bash
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

## Verify

```bash
bootctl status | grep -i "secure boot"
sudo sbctl status && sudo sbctl verify
sudo systemd-cryptenroll /dev/nvme0n1p2
sudo ufw status verbose
systemctl is-active usbguard
resolvectl status | grep -i "DNS over TLS"
```

## After BIOS/firmware update

PCR values change and TPM unlock fails. Boot with LUKS password, then:

```bash
cd ~/.dotfiles && ./tpm-reenroll.sh
```

## Existing system

```bash
git clone https://github.com/jedrzejratajczak/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && ./install.sh
```

## Machine-specific

`~/.config/zsh/local.zsh` is gitignored for per-machine aliases and SSH configs.
