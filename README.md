# dotfiles

Arch Linux + Hyprland rice with full disk encryption, Secure Boot, and TPM2 auto-unlock.

## Fresh install (desktop)

### BIOS setup (ASUS X870E-E)

1. Load Optimized Defaults
2. Set administrator password
3. Disable CSM
4. Enable fTPM (AMD fTPM configuration → Firmware TPM)
5. Enable EXPO I for RAM
6. Disable Secure Boot (temporarily, for installation)

### Base system

Boot from Arch ISO, connect ethernet, then:

```bash
curl -LO https://raw.githubusercontent.com/jedrzejratajczak/dotfiles/main/machines/nilu/base-install.sh
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

Select `desktop` profile and set up Secure Boot when prompted. Reboot.

### Secure Boot + TPM2

1. Enter BIOS, enable Secure Boot
2. Boot into system
3. Run `./install.sh` again, select Secure Boot setup — this time it will enroll TPM2

After this, LUKS unlocks automatically on boot.

### Finishing touches

1. Install Zen Browser extensions (Tridactyl, uBlock Origin)

## Fresh install (laptop)

### BIOS setup (Framework 13)

1. Set administrator password
2. Disable Secure Boot (temporarily, for installation)

Requires a manual Arch install with LUKS2, systemd-boot, and UKI (same as desktop but without NVIDIA — use the [Arch Installation Guide](https://wiki.archlinux.org/title/Installation_guide) with [dm-crypt](https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system)).

After first boot:

```bash
git clone https://github.com/jedrzejratajczak/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

Select `laptop` profile. Secure Boot + TPM2 setup is the same as desktop.

## Existing system

```bash
git clone https://github.com/jedrzejratajczak/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

Use `./install.sh -t` for a dry-run.

## Machine-specific config

`~/.config/zsh/local.zsh` is gitignored. Use it for per-machine aliases, variables, and SSH configs.
