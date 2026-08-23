#!/bin/bash
# =============================================================================
# Visnux Install Script — made by beamyyl (archinstall SUX!)
# Supports: UEFI or BIOS
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
command -v pacman &>/dev/null || die "'pacman' not found. Are you booted from the visnux live ISO?"
[ "$(id -u)" -eq 0 ] || die "This installer must be run as root."

# =============================================================================
# Reminders
# =============================================================================
clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              VISNUX INSTALLER                            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "This script will install Visnux to /mnt."
info "Your partitions must be formatted and mounted BEFORE continuing."
echo ""
echo "  Mount commands (UEFI):"
echo ""
echo "    mount /dev/sdaR /mnt"
echo "    mkdir -p /mnt/boot/efi"
echo "    mount /dev/sdaB /mnt/boot/efi"
echo "    swapon /dev/sdaX"
echo ""
echo "  Mount commands (BIOS):"
echo ""
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

ask "Boot mode — UEFI or BIOS?"
ask "  1) UEFI  (modern systems, GPT disk)"
ask "  2) BIOS  (legacy / older systems, MBR or GPT disk)"
read -rp "  Choice [1/2]: " BOOT_CHOICE
case "$BOOT_CHOICE" in
    1) BOOT_MODE="uefi" ;;
    2) BOOT_MODE="bios" ;;
    *) die "Invalid choice. Enter 1 or 2." ;;
esac
echo ""

if [ "$BOOT_MODE" = "uefi" ]; then
    mountpoint -q /mnt/boot/efi \
        || die "/mnt/boot/efi is not mounted. Mount your EFI partition and re-run."
    info "UEFI mode selected. EFI mount verified."
else
    info "BIOS mode selected."
    echo ""
    ask "Enter the disk to install GRUB to (e.g. /dev/sda, /dev/vda)."
    ask "Whole disk, NOT a partition."
    read -rp "  Install disk: " GRUB_DISK
    [ -z "$GRUB_DISK" ] && die "Disk cannot be empty."
    [ -b "$GRUB_DISK" ] || die "'$GRUB_DISK' is not a valid block device."
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

ask "Init system?"
ask "  1) systemd"
ask "  2) OpenRC"
ask "  3) runit"
ask "  4) dinit"
ask "  5) s6"
read -rp "  Choice [1-5]: " INIT_CHOICE
case "$INIT_CHOICE" in
    1) INIT_SYSTEM="systemd" ;;
    2) INIT_SYSTEM="openrc" ;;
    3) INIT_SYSTEM="runit" ;;
    4) INIT_SYSTEM="dinit" ;;
    5) INIT_SYSTEM="s6" ;;
    *) die "Invalid choice. Enter 1, 2, 3, 4, or 5." ;;
esac
echo ""

# =============================================================================
# Multilib
# =============================================================================
ask "Enable the multilib repository (for 32-bit packages)? [Y/n]"
read -rp "  Choice: " MULTILIB_CHOICE
if [[ "$MULTILIB_CHOICE" =~ ^[Nn]$ ]]; then
    ENABLE_MULTILIB="no"
else
    ENABLE_MULTILIB="yes"
fi
echo ""

# =============================================================================
# System configuration
# =============================================================================
info "============================================================"
info " SYSTEM CONFIGURATION"
info "============================================================"
echo ""

ask "Enter a hostname for your new system."
read -rp "  Hostname: " NEW_HOSTNAME
[ -z "$NEW_HOSTNAME" ] && die "Hostname cannot be empty."
echo ""

info "Configuration summary:"
echo "    Boot mode : $BOOT_MODE"
echo "    Init      : $INIT_SYSTEM"
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
    command -v pacstrap &>/dev/null || die "'pacstrap' not found."
    
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

    info "Bootstrapping Visnux (Artix base)..."
    command -v pacstrap &>/dev/null || die "'pacstrap' not found."
    
    INIT_PKGS=""
    case "$INIT_SYSTEM" in
        openrc) INIT_PKGS="openrc elogind-openrc" ;;
        runit)  INIT_PKGS="runit runit-rc elogind-runit" ;;
        dinit)  INIT_PKGS="dinit elogind-dinit" ;;
        s6)     INIT_PKGS="s6-base s6-linux-init s6-rc s6-scripts elogind-s6" ;;
    esac

    pacstrap -C "$ARTIX_CONF" /mnt base base-devel linux linux-firmware sof-firmware \
        artix-keyring artix-mirrorlist $INIT_PKGS

    info "Fixing mirrorlist clobber and applying pacman tweaks..."
    
    # Brute-force a known-working Artix mirror so the chroot doesn't hang on Arch servers
    echo 'Server = https://mirrors.rit.edu/artixlinux/$repo/os/$arch' > /mnt/etc/pacman.d/mirrorlist

    # Apply fast downloads to the new chroot before we install artix-archlinux-support
    sed -i 's/^#*ParallelDownloads = .*/ParallelDownloads = 12/' /mnt/etc/pacman.conf
    sed -i '/^ParallelDownloads = 12/a Color\nILoveCandy' /mnt/etc/pacman.conf
    
    # Reinstall the mirrorlist package purely inside the chroot to populate the rest of the mirrors
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
# Fstab
# =============================================================================
info "============================================================"
info " FSTAB"
info "============================================================"

command -v genfstab &>/dev/null || die "'genfstab' not found."
info "Generating /etc/fstab..."
genfstab -U /mnt > /mnt/etc/fstab

info "fstab contents:"
cat /mnt/etc/fstab
echo ""

# =============================================================================
# In-chroot script
# =============================================================================
info "============================================================"
info " WRITING IN-CHROOT SCRIPT"
info "============================================================"

cat > /mnt/root/chroot-install.sh <<CHROOT_EOF
#!/bin/bash
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "\${GREEN}[CHROOT]\${NC}  \$*"; }
warn()  { echo -e "\${YELLOW}[CHROOT]\${NC}  \$*"; }

BOOT_MODE="${BOOT_MODE}"
INIT_SYSTEM="${INIT_SYSTEM}"
NEW_HOSTNAME="${NEW_HOSTNAME}"
GRUB_DISK="${GRUB_DISK}"

hwclock --systohc

pacman -Sy --noconfirm git

echo "\${NEW_HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${NEW_HOSTNAME}.localdomain \${NEW_HOSTNAME}
EOF

cat > /etc/os-release <<'EOF'
NAME="Visnux"
PRETTY_NAME="Visnux (Version Yes.)"
ID=visnux
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://visnux.org/"
DOCUMENTATION_URL="https://wiki.visnux.org/"
SUPPORT_URL="https://bbs.visnux.org/"
BUG_REPORT_URL="https://gitlab.visnux.org/groups/visnux/-/issues"
PRIVACY_POLICY_URL="https://terms.visnux.org/docs/privacy-policy/"
LOGO=visnux
EOF

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

if [ "\${INIT_SYSTEM}" = "systemd" ]; then

    pacman -S plasma konsole dolphin kitty fastfetch sddm networkmanager vim nano sudo --noconfirm

    systemctl enable NetworkManager
    systemctl enable sddm --force

else

    pacman -S plasma konsole dolphin kitty fastfetch sddm sddm-\${INIT_SYSTEM} networkmanager networkmanager-\${INIT_SYSTEM} dbus dbus-\${INIT_SYSTEM} vim nano sudo --noconfirm

    case "\${INIT_SYSTEM}" in
        openrc)
            rc-update add dbus default
            rc-update add elogind default
            rc-update add NetworkManager default
            rc-update add sddm default
            ;;
        runit)
            mkdir -p /etc/runit/runsvdir/default
            for service in dbus elogind NetworkManager sddm; do
                if [ -d "/etc/runit/sv/\${service}" ] && [ ! -e "/etc/runit/runsvdir/default/\${service}" ]; then
                    ln -s "/etc/runit/sv/\${service}" "/etc/runit/runsvdir/default/\${service}"
                fi
            done
            ;;
        dinit)
        ln -s ../dbus           /etc/dinit.d/boot.d/
        ln -s ../elogind        /etc/dinit.d/boot.d/
        ln -s ../NetworkManager /etc/dinit.d/boot.d/
        ln -s ../sddm         /etc/dinit.d/boot.d/
            ;;
        s6)
            s6-rc-bundle-update add default dbus
            s6-rc-bundle-update add default elogind
            s6-rc-bundle-update add default NetworkManager
            s6-rc-bundle-update add default sddm
            ;;
    esac

fi

info "Installing GRUB..."

if [ "\${BOOT_MODE}" = "uefi" ]; then
    pacman -S --noconfirm grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi
else
    pacman -S --noconfirm grub
    grub-install --recheck "\${GRUB_DISK}"
fi

sed -i 's/GRUB_DISTRIBUTOR="Arch"/GRUB_DISTRIBUTOR="Visnux"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo ""
info "============================================================"
info " Set the ROOT password:"
info "============================================================"
passwd

echo ""
echo -e "\${CYAN}[INPUT]\${NC} Would you like to create a new user? (y/n)"
read -rp "  Choice: " CREATE_USER

if [ "\${CREATE_USER}" = "y" ]; then
    echo -e "\${CYAN}[INPUT]\${NC} Enter the new username:"
    read -rp "  Username: " NEW_USER
    if [ -z "\${NEW_USER}" ]; then
        warn "No username entered — skipping user creation."
    else
        echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
        chmod 440 /etc/sudoers.d/wheel

        useradd -m -G wheel,audio,video,input -s /bin/bash "\${NEW_USER}"
        info "User '\${NEW_USER}' created and added to: wheel, audio, video, input"
        info "Set a password for '\${NEW_USER}':"
        passwd "\${NEW_USER}"

        info "Cloning and setting up dotfiles for '\${NEW_USER}'..."
        su - "\${NEW_USER}" -c "cd ~ && mkdir -p ~/.config && git clone https://github.com/beamyyl/maindots && cp -r maindots/* ~/.config/ && rm -rf maindots && git clone https://github.com/realv1sta/larphub && rm -f ~/.config/fastfetch/logo.txt && mkdir -p ~/.config/fastfetch && cp larphub/visnuxlogo.txt ~/.config/fastfetch/logo.txt && rm -rf larphub && [ ! -f ~/.config/fastfetch/config.jsonc ] || sed -i 's/\"top\": 2/\"top\": 0/' ~/.config/fastfetch/config.jsonc"
        info "Dotfiles installed successfully."
        info "User setup complete."
    fi
else
    info "Skipping user creation."
fi

echo ""
info "============================================================"
info " Installation complete!"
info "============================================================"
info " Exit the chroot and reboot:"
info ""
info "    exit"
info "    umount -R /mnt"
info "    reboot"
info "============================================================"
CHROOT_EOF

chmod +x /mnt/root/chroot-install.sh
info "In-chroot script written."
echo ""

# =============================================================================
# Chroot
# =============================================================================
info "============================================================"
info " ENTERING CHROOT"
info "============================================================"
echo ""

arch-chroot /mnt /bin/bash /root/chroot-install.sh

# =============================================================================
# Cleanup
# =============================================================================
info "============================================================"
info " CLEANUP"
info "============================================================"

rm -f /mnt/root/chroot-install.sh

if [ "$INIT_SYSTEM" != "systemd" ]; then
    restore_live
    rm -f \
        "$ARTIX_BOOTSTRAP_CONF" \
        "$ARTIX_CONF"
fi

info "Unmounting filesystems..."
umount -R /mnt 2>/dev/null || true

echo ""
info "============================================================"
info " All done! Remove your installation media and reboot."
info "============================================================"
