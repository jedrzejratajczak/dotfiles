# dotfiles

Arch Linux + Hyprland rice with full disk encryption, Secure Boot, and TPM2 auto-unlock.

## Fresh install (desktop)

### BIOS setup

1. Set administrator password
2. Disable CSM
3. Enable fTPM
4. Enable EXPO for RAM
5. Disable Secure Boot (temporarily, for installation)

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

Select your machine profile and set up Secure Boot when prompted. Reboot.

### Secure Boot + TPM2

1. Enter BIOS, enable Secure Boot
2. Boot into system
3. Run `./install.sh` again, select Secure Boot setup — this time it will enroll TPM2

After this, LUKS unlocks automatically on boot.

### Finishing touches

1. Add a wallpaper to `~/Pictures/Wallpapers/` and select it in nilwall
2. Install Zen Browser extensions (Tridactyl, uBlock Origin)

## Existing system

```bash
git clone https://github.com/jedrzejratajczak/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

Use `./install.sh -t` for a dry-run.

## Machine-specific config

`~/.config/zsh/local.zsh` is gitignored. Use it for per-machine aliases, variables, and SSH configs.
