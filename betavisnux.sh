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
echo -e "${CYAN}║             VISNUX INSTALLER                             ║${NC}"
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
ENABLE_MULTILIB="yes"

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
    info "Installing base and the kernel..."
    pacman -Sy archlinux-keyring --noconfirm
    pacstrap /mnt base base-devel linux linux-firmware sof-firmware

    if grep -q '^\[multilib\]$' /mnt/etc/pacman.conf; then
        sed -i '/^\[multilib\]/,/^\[/ s#^Include = /etc/pacman.d/mirrorlist$#Include = /etc/pacman.d/mirrorlist#' /mnt/etc/pacman.conf
    else
        cat >> /mnt/etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    fi
else
    info "Preparing Artix repositories..."

    LIVE_PACMAN_CONF="/tmp/visnux-live-pacman.conf"
    LIVE_MIRRORLIST="/tmp/visnux-live-mirrorlist"
    ARTIX_BOOTSTRAP_CONF="/tmp/visnux-artix-bootstrap.conf"
    ARTIX_CONF="/tmp/visnux-artix.conf"

    cp /etc/pacman.conf "$LIVE_PACMAN_CONF"
    cp /etc/pacman.d/mirrorlist "$LIVE_MIRRORLIST"

    if pacman -Qq pacman-mirrorlist &>/dev/null; then
        pacman -Rnsdd --noconfirm pacman-mirrorlist
    fi

    cat > "$ARTIX_BOOTSTRAP_CONF" <<EOF
[options]
Architecture = auto
Color
CheckSpace
SigLevel = Never

[system]
Server = https://mirrors.rit.edu/artixlinux/\$repo/os/\$arch
EOF

    info "Installing Artix keyring and mirrorlist..."
    pacman --config "$ARTIX_BOOTSTRAP_CONF" -Sy --noconfirm artix-keyring artix-mirrorlist

    pacman-key --init
    pacman-key --populate artix

    cat > "$ARTIX_CONF" <<EOF
[options]
Architecture = auto
Color
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[system]
Include = /etc/pacman.d/mirrorlist

[world]
Include = /etc/pacman.d/mirrorlist

[galaxy]
Include = /etc/pacman.d/mirrorlist
EOF

    info "Installing Arch repository support..."
    pacman --config "$ARTIX_CONF" -Sy --noconfirm artix-archlinux-support
    pacman-key --populate archlinux

    [ -f /etc/pacman.d/mirrorlist ] || die "Artix mirrorlist was not installed."
    [ -f /etc/pacman.d/mirrorlist-arch ] || die "Arch mirrorlist was not installed."

    cp /etc/pacman.d/mirrorlist-arch /tmp/visnux-mirrorlist-arch
    cp "$LIVE_PACMAN_CONF" /mnt/etc/pacman.conf
    cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
    cp /tmp/visnux-mirrorlist-arch /mnt/etc/pacman.d/mirrorlist-arch

    sed -i \
        -e 's/^\[core\]$/[system]/' \
        -e 's/^\[extra\]$/[world]/' \
        /mnt/etc/pacman.conf

    if ! grep -q '^\[galaxy\]$' /mnt/etc/pacman.conf; then
        cat >> /mnt/etc/pacman.conf <<'EOF'

[galaxy]
Include = /etc/pacman.d/mirrorlist
EOF
    fi

    if [ "$ENABLE_MULTILIB" = "yes" ]; then
        if grep -q '^\[multilib\]$' /mnt/etc/pacman.conf; then
            sed -i '/^\[multilib\]/,/^\[/ s#^Include = /etc/pacman.d/mirrorlist$#Include = /etc/pacman.d/mirrorlist-arch#' /mnt/etc/pacman.conf
            if ! sed -n '/^\[multilib\]/,/^\[/p' /mnt/etc/pacman.conf | grep -q '^Include = /etc/pacman.d/mirrorlist-arch$'; then
                sed -i '/^\[multilib\]/a Include = /etc/pacman.d/mirrorlist-arch' /mnt/etc/pacman.conf
            fi
        else
            cat >> /mnt/etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
        fi
    fi

    command -v basestrap &>/dev/null || die "'basestrap' not found after installing artools support."
    command -v fstabgen &>/dev/null || die "'fstabgen' not found after installing artools support."
    command -v artix-chroot &>/dev/null || die "'artix-chroot' not found after installing artools support."

    case "$INIT_SYSTEM" in
        openrc)
            basestrap /mnt base base-devel openrc linux linux-firmware sof-firmware
            ;;
        runit)
            basestrap /mnt base base-devel runit runit-rc linux linux-firmware sof-firmware
            ;;
        dinit)
            basestrap /mnt base base-devel dinit linux linux-firmware sof-firmware
            ;;
        s6)
            basestrap /mnt base base-devel s6-base s6-linux-init s6-rc s6-scripts linux linux-firmware sof-firmware
            ;;
    esac
fi

# =============================================================================
# Fstab
# =============================================================================
info "============================================================"
info " FSTAB"
info "============================================================"

if [ "$INIT_SYSTEM" = "systemd" ]; then
    command -v genfstab &>/dev/null || die "'genfstab' not found."
    info "Generating /etc/fstab..."
    genfstab -U /mnt > /mnt/etc/fstab
else
    info "Generating /etc/fstab..."
    fstabgen -U /mnt > /mnt/etc/fstab
fi

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

sed -i 's/^#*ParallelDownloads = .*/ParallelDownloads = 12/' /etc/pacman.conf
sed -i '/^ParallelDownloads = 12/a Color\nILoveCandy' /etc/pacman.conf

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

    pacman -S plasma konsole dolphin kitty fastfetch sddm sddm-\${INIT_SYSTEM} networkmanager networkmanager-\${INIT_SYSTEM} elogind elogind-\${INIT_SYSTEM} dbus dbus-\${INIT_SYSTEM} vim nano sudo --noconfirm

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
            dinitctl enable dbus
            dinitctl enable elogind
            dinitctl enable NetworkManager
            dinitctl enable sddm
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

if [ "$INIT_SYSTEM" = "systemd" ]; then
    arch-chroot /mnt /bin/bash /root/chroot-install.sh
else
    artix-chroot /mnt /bin/bash /root/chroot-install.sh
fi

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
        "$ARTIX_CONF" \
        /tmp/visnux-mirrorlist-arch \
        "$LIVE_PACMAN_CONF" \
        "$LIVE_MIRRORLIST"
fi

info "Unmounting filesystems..."
umount -R /mnt 2>/dev/null || true

echo ""
info "============================================================"
info " All done! Remove your installation media and reboot."
info "============================================================"
