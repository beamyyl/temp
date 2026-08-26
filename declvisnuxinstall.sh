#!/bin/bash
# =============================================================================
# Beta Visnux Install Script (im trying to add declarative support)
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
ask()   { echo -e "${CYAN}[INPUT]${NC} $*"; }

restore_live() {
    if [ -n "${LIVE_PACMAN_CONF:-}" ] && [ -f "${LIVE_PACMAN_CONF}" ]; then
        cp "${LIVE_PACMAN_CONF}" /etc/pacman.conf
    fi
    if [ -n "${LIVE_MIRRORLIST:-}" ] && [ -f "${LIVE_MIRRORLIST}" ]; then
        cp "${LIVE_MIRRORLIST}" /etc/pacman.d/mirrorlist
    fi
}

trap restore_live EXIT

# =============================================================================
# Sanity checks
# =============================================================================
command -v pacman &>/dev/null || die "'pacman' not found. Boot from the live ISO."
[ "$(id -u)" -eq 0 ] || die "This installer must be run as root."

# =============================================================================
# Reminders
# =============================================================================
clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    VISNUX INSTALLER                      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "This script will install Visnux to /mnt."
info "Your partitions must be formatted and mounted BEFORE continuing."
echo ""
echo "  Mount commands (UEFI):"
echo "    mount /dev/sdaR /mnt"
echo "    mkdir -p /mnt/boot/efi"
echo "    mount /dev/sdaB /mnt/boot/efi"
echo "    swapon /dev/sdaX"
echo ""
echo "  Mount commands (BIOS):"
echo "    mount /dev/sdaR /mnt"
echo "    swapon /dev/sdaX"
echo ""
warn "If your partitions are NOT yet mounted, press Ctrl+C now,"
warn "mount them, then re-run this script."
echo ""
read -rp "  Press ENTER once your partitions are mounted..."
echo ""

mountpoint -q /mnt || die "/mnt is not mounted."
info "Root mount point verified."
echo ""

# =============================================================================
# Boot mode selection
# =============================================================================
info "============================================================"
info " BOOT MODE"
info "============================================================"
echo ""

while true; do
    ask "Boot mode — UEFI or BIOS?"
    ask "  1) UEFI  (modern systems, GPT disk)"
    ask "  2) BIOS  (legacy / older systems, MBR or GPT disk)"
    read -rp "  Choice [1/2]: " BOOT_CHOICE
    case "$BOOT_CHOICE" in
        1) BOOT_MODE="uefi"; break ;;
        2) BOOT_MODE="bios"; break ;;
        *) warn "Invalid choice. Enter 1 or 2." ;;
    esac
done
echo ""

if [ "$BOOT_MODE" = "uefi" ]; then
    mountpoint -q /mnt/boot/efi \
        || die "/mnt/boot/efi is not mounted. Mount your EFI partition and re-run."
    info "UEFI mode selected. EFI mount verified."
else
    info "BIOS mode selected."
    echo ""
    while true; do
        ask "Enter the disk to install GRUB to (e.g. /dev/sda, /dev/vda)."
        ask "Whole disk, NOT a partition."
        read -rp "  Install disk: " GRUB_DISK
        if [ -n "$GRUB_DISK" ] && [ -b "$GRUB_DISK" ]; then
            break
        fi
        warn "Invalid block device or empty. Please try again."
    done
    info "GRUB will be installed to: $GRUB_DISK"
fi
echo ""

# =============================================================================
# Init selection
# =============================================================================
info "============================================================"
info " INIT SYSTEM"
info "============================================================"
echo ""

while true; do
    ask "Init system?"
    ask "  1) systemd"
    ask "  2) dinit"
    ask "  3) openrc"
    ask "  4) runit"
    read -rp "  Choice [1-4]: " INIT_CHOICE
    case "$INIT_CHOICE" in
        1) INIT_SYSTEM="systemd"; break ;;
        2) INIT_SYSTEM="dinit"; break ;;
        3) INIT_SYSTEM="openrc"; break ;;
        4) INIT_SYSTEM="runit"; break ;;
        *) warn "Invalid choice. Enter 1, 2, 3, or 4." ;;
    esac
done
echo ""

# =============================================================================
# Desktop Environment selection
# =============================================================================
info "============================================================"
info " DESKTOP ENVIRONMENT"
info "============================================================"
echo ""

while true; do
    ask "Desktop Environment?"
    ask "  1) KDE Plasma"
    ask "  2) Xfce4"
    ask "  3) Skip installing a Desktop Environment"
    read -rp "  Choice [1-3]: " DE_CHOICE
    case "$DE_CHOICE" in
        1) DESKTOP_ENV="kde"; break ;;
        2) DESKTOP_ENV="xfce"; break ;;
        3) DESKTOP_ENV="none"; break ;;
        *) warn "Invalid choice. Enter 1, 2, or 3." ;;
    esac
done
echo ""

# =============================================================================
# Multilib
# =============================================================================
while true; do
    ask "Enable the multilib repository (for 32-bit packages)? [Y/n]"
    read -rp "  Choice: " MULTILIB_CHOICE
    if [[ "$MULTILIB_CHOICE" =~ ^[Nn]$ ]]; then
        ENABLE_MULTILIB="no"; break
    elif [[ "$MULTILIB_CHOICE" =~ ^[Yy]$ ]] || [ -z "$MULTILIB_CHOICE" ]; then
        ENABLE_MULTILIB="yes"; break
    else
        warn "Please enter Y or n."
    fi
done
echo ""

# =============================================================================
# System configuration
# =============================================================================
info "============================================================"
info " SYSTEM CONFIGURATION"
info "============================================================"
echo ""

while true; do
    ask "Enter a hostname for your new system."
    read -rp "  Hostname: " NEW_HOSTNAME
    if [ -n "$NEW_HOSTNAME" ]; then
        break
    fi
    warn "Hostname cannot be empty. Please try again."
done
echo ""

info "Configuration summary:"
echo "    Boot mode : $BOOT_MODE"
echo "    Init      : $INIT_SYSTEM"
echo "    Desktop   : $DESKTOP_ENV"
echo "    Multilib  : $ENABLE_MULTILIB"
echo "    Hostname  : $NEW_HOSTNAME"
echo ""
read -rp "  Press ENTER to continue..."
echo ""

# =============================================================================
# Base install
# =============================================================================
info "============================================================"
info " BASE INSTALL"
info "============================================================"
echo ""

if [ "$INIT_SYSTEM" = "systemd" ]; then
    command -v pacstrap &>/devnull || die "'pacstrap' not found."

    info "Enabling parallel downloads on host..."
    sed -i 's/^#*ParallelDownloads = .*/ParallelDownloads = 12/' /etc/pacman.conf

    info "Installing base and the kernel..."
    pacman -Sy archlinux-keyring --noconfirm

    pacstrap /mnt base base-devel linux linux-firmware sof-firmware

    info "Applying pacman tweaks to chroot..."
    sed -i 's/^#*ParallelDownloads = .*/ParallelDownloads = 12/' /mnt/etc/pacman.conf
    sed -i '/^ParallelDownloads = 12/a Color\nILoveCandy' /mnt/etc/pacman.conf

    if grep -q '^\[multilib\]$' /mnt/etc/pacman.conf; then
        sed -i '/^\[multilib\]/,/^\[/ s#^Include = /etc/pacman.d/mirrorlist$#Include = /etc/pacman.d/mirrorlist#' /mnt/etc/pacman.conf
    elif [ "$ENABLE_MULTILIB" = "yes" ]; then
        cat >> /mnt/etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    fi
else
    info "Preparing Artix repositories for pacstrap..."

    ARTIX_BOOTSTRAP_CONF="/tmp/visnux-artix-bootstrap.conf"
    cat > "$ARTIX_BOOTSTRAP_CONF" <<EOF
[options]
Architecture = auto
Color
CheckSpace
ParallelDownloads = 12
SigLevel = Never

[system]
Server = https://mirrors.rit.edu/artixlinux/\$repo/os/\$arch
EOF

    info "Installing Artix keyring on the live system..."
    pacman --config "$ARTIX_BOOTSTRAP_CONF" -Sy --noconfirm artix-keyring
    pacman-key --init
    pacman-key --populate artix

    ARTIX_CONF="/tmp/visnux-artix.conf"
    cat > "$ARTIX_CONF" <<EOF
[options]
Architecture = auto
Color
CheckSpace
ParallelDownloads = 12
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[system]
Server = https://mirrors.rit.edu/artixlinux/\$repo/os/\$arch
[world]
Server = https://mirrors.rit.edu/artixlinux/\$repo/os/\$arch
[galaxy]
Server = https://mirrors.rit.edu/artixlinux/\$repo/os/\$arch
EOF

    info "Bootstrapping Visnux..."
    command -v pacstrap &>/devnull || die "'pacstrap' not found."

    INIT_PKGS=""
    case "$INIT_SYSTEM" in
        openrc) INIT_PKGS="openrc elogind-openrc" ;;
        runit)  INIT_PKGS="runit runit-rc elogind-runit" ;;
        dinit)  INIT_PKGS="dinit elogind-dinit" ;;
    esac

    pacstrap -C "$ARTIX_CONF" /mnt base base-devel linux linux-firmware sof-firmware artix-keyring artix-mirrorlist $INIT_PKGS

    echo 'Server = https://mirrors.rit.edu/artixlinux/$repo/os/$arch' > /mnt/etc/pacman.d/mirrorlist

    sed -i 's/^#*ParallelDownloads = .*/ParallelDownloads = 12/' /mnt/etc/pacman.conf
    sed -i '/^ParallelDownloads = 12/a Color\nILoveCandy' /mnt/etc/pacman.conf

    arch-chroot /mnt pacman -Sy --noconfirm artix-mirrorlist

    info "Installing Arch repository support inside the chroot..."
    arch-chroot /mnt pacman -Sy --noconfirm artix-archlinux-support
    arch-chroot /mnt pacman-key --populate archlinux

    info "Configuring Visnux pacman.conf..."
    if [ "$ENABLE_MULTILIB" = "yes" ]; then
        if ! grep -q '^\[multilib\]$' /mnt/etc/pacman.conf; then
            cat >> /mnt/etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
        fi
    fi
fi

# =============================================================================
# Generate fstab
# =============================================================================
info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# =============================================================================
# Generate package manifest & vpk
# =============================================================================
info "============================================================"
info " GENERATING PACKAGE MANIFEST & VPK"
info "============================================================"

mkdir -p /mnt/etc/visnux

if [ "$BOOT_MODE" = "uefi" ]; then
    BOOTMGR_PKGS="grub, efibootmgr"
else
    BOOTMGR_PKGS="grub"
fi

DRV_PKGS="mesa, vulkan-intel, vulkan-radeon, vulkan-nouveau, vulkan-swrast, libva, intel-media-driver"
if [ "$ENABLE_MULTILIB" = "yes" ]; then
    DRV_PKGS="$DRV_PKGS, lib32-mesa, lib32-vulkan-intel, lib32-vulkan-radeon, lib32-vulkan-nouveau, lib32-vulkan-swrast"
fi

DE_PKGS="networkmanager"
if [ "$INIT_SYSTEM" = "systemd" ]; then
    if [ "$DESKTOP_ENV" = "kde" ]; then
        DE_PKGS="$DE_PKGS, plasma, ark, konsole, dolphin, xdg-desktop-portal-kde, wl-clipboard, sddm, power-profiles-daemon"
    elif [ "$DESKTOP_ENV" = "xfce" ]; then
        DE_PKGS="$DE_PKGS, xfce4, xfce4-whiskermenu-plugin, ark, xclip, maim, xfce4-pulseaudio-plugin, sddm, power-profiles-daemon"
    fi
else
    DE_PKGS="$DE_PKGS, networkmanager-${INIT_SYSTEM}, dbus, dbus-${INIT_SYSTEM}, turnstile, turnstile-${INIT_SYSTEM}"
    if [ "$DESKTOP_ENV" = "kde" ]; then
        DE_PKGS="$DE_PKGS, plasma, konsole, dolphin, ark, xdg-desktop-portal-kde, wl-clipboard, sddm, sddm-${INIT_SYSTEM}, power-profiles-daemon, power-profiles-daemon-${INIT_SYSTEM}, pipewire, pipewire-${INIT_SYSTEM}, pipewire-pulse, pipewire-pulse-${INIT_SYSTEM}, wireplumber, wireplumber-${INIT_SYSTEM}"
    elif [ "$DESKTOP_ENV" = "xfce" ]; then
        DE_PKGS="$DE_PKGS, xorg-server, xfce4, xfce4-whiskermenu-plugin, xfce4-pulseaudio-plugin, ark, xclip, maim, sddm, sddm-${INIT_SYSTEM}, power-profiles-daemon, power-profiles-daemon-${INIT_SYSTEM}, pipewire, pipewire-${INIT_SYSTEM}, pipewire-pulse, pipewire-pulse-${INIT_SYSTEM}, wireplumber, wireplumber-${INIT_SYSTEM}"
    fi
fi

cat > /mnt/etc/visnux/packages.decl <<DECL_EOF
# /etc/visnux/packages.decl
# Generated by Visnux Installer

[kernel]
pkgs = { linux, linux-headers, linux-firmware, sof-firmware }

[bootmgr]
pkgs = { $BOOTMGR_PKGS }

[drivers]
pkgs = { $DRV_PKGS }

[desktop]
pkgs = { $DE_PKGS }

[fonts]
pkgs = { ttf-iosevka-nerd, ttf-adwaitamono-nerd }

[cli-tools]
pkgs = { git, neovim, nano, sudo, fish, flatpak, fastfetch, kitty, papirus-icon-theme }
DECL_EOF

mkdir -p /mnt/usr/bin
cat > /mnt/usr/bin/vpk <<'VPKEOF'
#!/bin/bash
# =============================================================================
# vpk — Visnux Package Sync Tool
# usage: vpk [--check | --sync | --path /path/to/manifest]
# =============================================================================

set -euo pipefail
MANIFEST="/etc/visnux/packages.decl"
ACTION="sync"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${GREEN}[vpk]${NC} $*"; }
warn() { echo -e "${YELLOW}[vpk WARN]${NC} $*"; }
die()  { echo -e "${RED}[vpk FATAL]${NC} $*"; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) ACTION="check"; shift ;;
        --sync)  ACTION="sync"; shift ;;
        --path)  MANIFEST="$2"; shift 2 ;;
        -h|--help)
            echo "vpk: package syncing tool"
            echo "Options: --check (lists missing), --sync (installs missing), --path (specify manifest)"
            exit 0
            ;;
        *) die "Unknown arg: $1" ;;
    esac
done

if [[ ! -f "$MANIFEST" ]]; then
    die "Manifest not found at $MANIFEST."
fi

RAW_LIST=$(awk '
    /^[ \t]*\[/ {in_block=1}
    /^[ \t]*pkgs[ \t]*=[ \t]*{/ && in_block {
        gsub(/.*\{/,"");
        while ($0 !~ /\}/) { print; getline }
        gsub(/\}.*/,"");
        print;
        in_block=0
    }' "$MANIFEST" | tr -d ' ' | tr ',' '\n' | grep -v '^$' || true)

if [[ -z "$RAW_LIST" ]]; then
    info "Manifest is empty or invalid."
    exit 0
fi

MISSING=()
mapfile -t ALL_PKGS <<< "$RAW_LIST"
for pkg in "${ALL_PKGS[@]}"; do
    if ! pacman -Qq "$pkg" &>/devnull; then
        MISSING+=("$pkg")
    fi
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
    info "System matches manifest."
    exit 0
fi

if [[ "$ACTION" == "check" ]]; then
    info "Missing packages:"
    for m in "${MISSING[@]}"; do echo "  - $m"; done
    exit 0
fi

info "Syncing packages:"
echo "${MISSING[@]}"
pacman -Sy --needed --noconfirm "${MISSING[@]}"
info "Sync complete."
VPKEOF

chmod +x /mnt/usr/bin/vpk

# =============================================================================
# Generate the in-chroot installer script
# =============================================================================
CHROOT_SCRIPT="/mnt/root/chroot-install.sh"
cat > "$CHROOT_SCRIPT" <<EOF
#!/bin/bash
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "\${GREEN}[CHROOT-INFO]\${NC}  \$*"; }
warn()  { echo -e "\${YELLOW}[CHROOT-WARN]\${NC}  \$*"; }
die()   { echo -e "\${RED}[CHROOT-FAIL]\${NC}  \$*"; exit 1; }
ask()   { echo -e "\${CYAN}[CHROOT-INPUT]\${NC} \$*"; }

info "Syncing packages with vpk..."
vpk --sync

if [ "$DESKTOP_ENV" = "kde" ] && pacman -Qq plasma-bigscreen &>/devnull; then
    pacman -Rnsdd plasma-bigscreen --noconfirm || true
fi

info "Configuring timezone, locale, and hostname..."
ln -sf /usr/share/zoneinfo/Europe/Bucharest /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#ro_RO.UTF-8 UTF-8/ro_RO.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$NEW_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $NEW_HOSTNAME.localdomain $NEW_HOSTNAME
HOSTS_EOF

info "Setting root password..."
while true; do
    passwd root && break
    warn "Passwords did not match. Try again."
done

info "Installing and configuring GRUB..."
if [ "$BOOT_MODE" = "uefi" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Visnux
else
    grub-install --target=i386-pc "$GRUB_DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg

info "Enabling services..."
if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl enable NetworkManager || true
    if [ "$DESKTOP_ENV" != "none" ]; then
        systemctl enable sddm || true
        systemctl enable power-profiles-daemon || true
    fi
elif [ "$INIT_SYSTEM" = "dinit" ]; then
    dinitctl enable NetworkManager || true
    dinitctl enable dbus || true
    if [ "$DESKTOP_ENV" != "none" ]; then
        dinitctl enable sddm || true
        dinitctl enable power-profiles-daemon || true
    fi
elif [ "$INIT_SYSTEM" = "runit" ]; then
    ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default/ || true
    ln -s /etc/runit/sv/dbus /etc/runit/runsvdir/default/ || true
    if [ "$DESKTOP_ENV" != "none" ]; then
        ln -s /etc/runit/sv/sddm /etc/runit/runsvdir/default/ || true
        ln -s /etc/runit/sv/power-profiles-daemon /etc/runit/runsvdir/default/ || true
    fi
elif [ "$INIT_SYSTEM" = "openrc" ]; then
    rc-update add NetworkManager default || true
    rc-update add dbus default || true
    if [ "$DESKTOP_ENV" != "none" ]; then
        rc-update add sddm default || true
        rc-update add power-profiles-daemon default || true
    fi
fi

info "Creating standard user..."
while true; do
    ask "Enter the new username:"
    read -rp "  Username: " NEW_USER
    if [ -n "\$NEW_USER" ]; then
        break
    fi
    warn "Username cannot be empty. Try again."
done
useradd -m -G wheel,video,audio,storage,optical "\$NEW_USER"
while true; do
    ask "Set password for \$NEW_USER:"
    passwd "\$NEW_USER" && break
    warn "Passwords did not match. Try again."
done
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

info "Fetching beamyyl/maindots for the Visnux flair..."
if [ ! -d "/home/\$NEW_USER/.dotfiles" ]; then
    su - "\$NEW_USER" -c "git clone https://github.com/beamyyl/maindots.git ~/.dotfiles" || true
    su - "\$NEW_USER" -c "mkdir -p ~/.config/fish ~/.config/fastfetch" || true
    su - "\$NEW_USER" -c "cp -rf ~/.dotfiles/config/fish/* ~/.config/fish/ 2>/dev/null || true"
    su - "\$NEW_USER" -c "cp -rf ~/.dotfiles/config/fastfetch/* ~/.config/fastfetch/ 2>/dev/null || true"
fi

info "Changing default shell to fish for \$NEW_USER..."
chsh -s /usr/bin/fish "\$NEW_USER" || true

info "Fetching larphub wallpapers..."
mkdir -p /home/\$NEW_USER/Pictures/Wallpapers
git clone https://github.com/realv1sta/larphub.git /tmp/larphub || true
cp -r /tmp/larphub/wallpapers/* /home/\$NEW_USER/Pictures/Wallpapers/ 2>/dev/null || true
chown -R "\$NEW_USER:\$NEW_USER" /home/\$NEW_USER/Pictures/Wallpapers

info "Setting up a 4GB swapfile..."
dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
chmod 600 /swapfile
mkswap /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

info "Visnux chroot setup complete."
EOF
chmod +x "$CHROOT_SCRIPT"

# =============================================================================
# Execute the chroot script
# =============================================================================
info "============================================================"
info " ENTERING CHROOT"
info "============================================================"
echo ""
arch-chroot /mnt /root/chroot-install.sh

# =============================================================================
# Finish up
# =============================================================================
info "============================================================"
info " INSTALLATION COMPLETE"
info "============================================================"
echo ""
info "Visnux has been successfully installed."
info "You can now unmount and reboot your system."
echo ""
echo "    umount -R /mnt"
echo "    reboot"
echo ""
exit 0
