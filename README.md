# dotfiles

Arch Linux + Hyprland with full disk encryption, Secure Boot, and TPM2 auto-unlock.

## Fresh install (desktop)

### BIOS setup

1. Load Optimized Defaults
2. Set administrator password
3. Disable CSM
4. Enable fTPM (AMD fTPM configuration → Firmware TPM)
5. Enable EXPO I for RAM
6. Disable Secure Boot (temporarily, for installation)

### Base system

Boot from Arch ISO, connect ethernet, then:

```bash
curl -LO https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main/machines/desktop/base-install.sh
chmod +x base-install.sh
./base-install.sh
```

Remove USB and reboot.

### Environment setup

Log in, connect ethernet, then:

```bash
cd ~/.dotfiles
./install.sh
```

Reboot into BIOS, enable Secure Boot, boot into system, run `./install.sh` again (enrolls TPM2 automatically). After this, LUKS unlocks automatically on boot.

## Fresh install (laptop)

### BIOS setup

1. Set administrator password
2. Disable Secure Boot (temporarily, for installation)

### Base system

Boot from Arch ISO, connect to WiFi, then:

```bash
curl -LO https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main/machines/laptop/base-install.sh
chmod +x base-install.sh
./base-install.sh
```

Remove USB and reboot. Environment setup and Secure Boot + TPM2 are the same as desktop.

## Existing system

```bash
git clone https://github.com/jedrzejratajczak/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

## Machine-specific config

`~/.config/zsh/local.zsh` is gitignored. Use it for per-machine aliases, variables, and SSH configs.
