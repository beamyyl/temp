#!/bin/bash
# =============================================================================
# Visnux Install Script — made by beamyyl (archinstall SUX!)
#
# Supports:
#   UEFI or BIOS
#   systemd, OpenRC, runit, dinit, s6
#
# systemd:
#   Native Arch Linux repositories
#
# OpenRC / runit / dinit / s6:
#   Artix Linux repositories:
#       system
#       world
#       galaxy
#   + Arch Linux multilib:
#       multilib
#
# IMPORTANT:
#   This installer is run from the Visnux/Arch live ISO.
#   It does NOT require an Artix ISO.
#
# Artix bootstrap:
#   1. Temporarily use the RIT Artix worldwide mirror.
#   2. Temporarily disable signature checking ONLY for:
#        artix-keyring
#        artix-mirrorlist
#   3. Populate the Artix keyring.
#   4. Restore normal signature verification.
#   5. Install artix-archlinux-support and artools-base normally.
#   6. Use Artix basestrap/fstabgen/artix-chroot.
#
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
ask()   { echo -e "${CYAN}[INPUT]${NC} $*"; }

# =============================================================================
# Constants
# =============================================================================

ARTIX_BOOTSTRAP_MIRROR='https://mirrors.rit.edu/artixlinux'

# Temporary files used only by the live environment.
ARTIX_TMP_CONF="/tmp/visnux-artix-pacman.conf"
ARTIX_TMP_BOOTSTRAP_CONF="/tmp/visnux-artix-bootstrap-pacman.conf"

# Backup of the live ISO's original Arch configuration.
LIVE_PACMAN_CONF_BACKUP="/tmp/visnux-live-pacman.conf"
LIVE_MIRRORLIST_BACKUP="/tmp/visnux-live-mirrorlist"

ARTIX_BOOTSTRAP_DONE=0
LIVE_CONFIG_MODIFIED=0

# =============================================================================
# Cleanup / recovery
# =============================================================================

restore_live_environment() {
    if [ "$LIVE_CONFIG_MODIFIED" -eq 1 ]; then
        info "Restoring live ISO pacman configuration..."

        if [ -f "$LIVE_PACMAN_CONF_BACKUP" ]; then
            cp "$LIVE_PACMAN_CONF_BACKUP" /etc/pacman.conf
        fi

        if [ -f "$LIVE_MIRRORLIST_BACKUP" ]; then
            cp "$LIVE_MIRRORLIST_BACKUP" /etc/pacman.d/mirrorlist
        fi

        LIVE_CONFIG_MODIFIED=0
    fi

    rm -f \
        "$ARTIX_TMP_CONF" \
        "$ARTIX_TMP_BOOTSTRAP_CONF" \
        "$LIVE_PACMAN_CONF_BACKUP" \
        "$LIVE_MIRRORLIST_BACKUP"
}

trap restore_live_environment EXIT

# =============================================================================
# Sanity checks
# =============================================================================

for cmd in pacman mountpoint; do
    command -v "$cmd" &>/dev/null \
        || die "'$cmd' not found. Are you booted from the Visnux live ISO?"
done

[ "$(id -u)" -eq 0 ] \
    || die "This installer must be run as root."

# These are required for the Artix bootstrap path.
for cmd in curl bsdtar; do
    command -v "$cmd" &>/dev/null \
        || die "'$cmd' not found. The Visnux live ISO needs '$cmd' for Artix installation."
done

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
# Boot mode
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
    1)
        BOOT_MODE="uefi"
        ;;
    2)
        BOOT_MODE="bios"
        ;;
    *)
        die "Invalid choice. Enter 1 or 2."
        ;;
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
# Init system selection
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
echo ""

read -rp "  Choice [1-5]: " INIT_CHOICE

case "$INIT_CHOICE" in
    1)
        INIT_SYSTEM="systemd"
        ;;
    2)
        INIT_SYSTEM="openrc"
        ;;
    3)
        INIT_SYSTEM="runit"
        ;;
    4)
        INIT_SYSTEM="dinit"
        ;;
    5)
        INIT_SYSTEM="s6"
        ;;
    *)
        die "Invalid choice. Enter 1, 2, 3, 4, or 5."
        ;;
esac

echo ""

# =============================================================================
# Multilib
# =============================================================================

info "============================================================"
info " MULTILIB"
info "============================================================"
echo ""

ask "Enable 32-bit / multilib support? (y/n)"
read -rp "  Choice [y/N]: " MULTILIB_CHOICE

case "$MULTILIB_CHOICE" in
    y|Y)
        ENABLE_MULTILIB="yes"
        ;;
    *)
        ENABLE_MULTILIB="no"
        ;;
esac

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
# SYSTEMD / ARCH INSTALL
# =============================================================================

if [ "$INIT_SYSTEM" = "systemd" ]; then

    info "============================================================"
    info " ARCH / SYSTEMD INSTALL"
    info "============================================================"
    echo ""

    info "Installing base and the kernel..."

    # Keep the existing Visnux systemd installation behavior.
    pacman -Sy archlinux-keyring --noconfirm

    pacstrap /mnt \
        base \
        base-devel \
        linux \
        linux-firmware \
        sof-firmware

    # -------------------------------------------------------------------------
    # Arch multilib
    # -------------------------------------------------------------------------

    if [ "$ENABLE_MULTILIB" = "yes" ]; then
        info "Enabling Arch multilib..."

        sed -i \
            '/^\[multilib\]/,/^[[:space:]]*$/ {
                s/^#Include = \/etc\/pacman\.d\/mirrorlist$/Include = \/etc\/pacman.d\/mirrorlist/
                s/^# Include = \/etc\/pacman\.d\/mirrorlist$/Include = \/etc\/pacman.d\/mirrorlist/
            }' \
            /mnt/etc/pacman.conf

        # More reliable fallback in case the exact Arch pacman.conf layout
        # differs from the expected one.
        if ! grep -A2 -q '^\[multilib\]' /mnt/etc/pacman.conf \
            || ! grep -A2 -q '^Include = /etc/pacman.d/mirrorlist' /mnt/etc/pacman.conf; then

            cat >> /mnt/etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
        fi
    fi

    # =========================================================================
    # FSTAB
    # =========================================================================

    info "============================================================"
    info " FSTAB"
    info "============================================================"

    info "Generating /etc/fstab..."

    genfstab -U /mnt > /mnt/etc/fstab

    info "fstab contents:"
    cat /mnt/etc/fstab
    echo ""

# =============================================================================
# ARTIX INSTALL
# =============================================================================

else

    info "============================================================"
    info " ARTIX / $INIT_SYSTEM INSTALL"
    info "============================================================"
    echo ""

    # =========================================================================
    # Save live Arch configuration
    # =========================================================================

    info "Saving live ISO Arch pacman configuration..."

    cp /etc/pacman.conf "$LIVE_PACMAN_CONF_BACKUP"

    if [ -f /etc/pacman.d/mirrorlist ]; then
        cp /etc/pacman.d/mirrorlist "$LIVE_MIRRORLIST_BACKUP"
    else
        die "/etc/pacman.d/mirrorlist does not exist on the live ISO."
    fi

    # =========================================================================
    # TEMPORARY ARTIX BOOTSTRAP CONFIG
    #
    # This configuration is ONLY used to obtain:
    #   artix-keyring
    #   artix-mirrorlist
    #
    # Signature verification is intentionally disabled ONLY for this bootstrap
    # transaction, because the live Arch keyring does not yet trust Artix.
    # =========================================================================

    info "Preparing temporary Artix bootstrap configuration..."

    cat > "$ARTIX_TMP_BOOTSTRAP_CONF" <<EOF
[options]
Architecture = auto
Color
CheckSpace
SigLevel = Never

[system]
Server = ${ARTIX_BOOTSTRAP_MIRROR}/\$repo/os/\$arch
EOF

    # =========================================================================
    # Bootstrap Artix keyring + exact packaged mirrorlist
    # =========================================================================

    info "Bootstrapping the Artix keyring and mirrorlist..."
    warn "GPG verification is disabled ONLY for this temporary transaction."

    pacman \
        --config "$ARTIX_TMP_BOOTSTRAP_CONF" \
        -Sy \
        --noconfirm \
        artix-keyring \
        artix-mirrorlist

    # =========================================================================
    # Populate Artix trust
    # =========================================================================

    info "Initializing/populating the Artix pacman keyring..."

    pacman-key --init
    pacman-key --populate artix

    # =========================================================================
    # Now restore normal signature verification.
    #
    # The temporary bootstrap config is replaced by a normal verified config.
    # =========================================================================

    info "Restoring normal GPG verification..."

    cat > "$ARTIX_TMP_CONF" <<EOF
[options]
Architecture = auto
Color
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[system]
Server = ${ARTIX_BOOTSTRAP_MIRROR}/\$repo/os/\$arch

[world]
Server = ${ARTIX_BOOTSTRAP_MIRROR}/\$repo/os/\$arch

[galaxy]
Server = ${ARTIX_BOOTSTRAP_MIRROR}/\$repo/os/\$arch
EOF

    # =========================================================================
    # Install Arch repository support + Artix bootstrap tools
    #
    # artix-archlinux-support brings in Arch mirrorlist/keyring support.
    # artools-base provides basestrap/fstabgen/artix-chroot.
    # =========================================================================

    info "Installing Artix bootstrap tools with normal signature verification..."

    pacman \
        --config "$ARTIX_TMP_CONF" \
        -Sy \
        --noconfirm \
        artix-archlinux-support \
        artools-base

    # archlinux-keyring is normally pulled in by Arch repository support,
    # but explicitly make sure it exists before using Arch multilib.
    info "Installing/updating Arch Linux keyring..."

    pacman \
        --config "$ARTIX_TMP_CONF" \
        -S \
        --noconfirm \
        archlinux-keyring

    pacman-key --populate artix archlinux

    # =========================================================================
    # We now have:
    #
    # /etc/pacman.d/mirrorlist
    #     = exact Artix mirrorlist supplied by artix-mirrorlist
    #
    # /etc/pacman.d/mirrorlist-arch
    #     = Arch mirrorlist supplied by Artix Arch support
    # =========================================================================

    [ -f /etc/pacman.d/mirrorlist ] \
        || die "Artix mirrorlist was not installed."

    [ -f /etc/pacman.d/mirrorlist-arch ] \
        || die "Arch mirrorlist was not installed by artix-archlinux-support."

    # =========================================================================
    # Prepare the live environment for basestrap.
    #
    # basestrap uses the live environment's pacman configuration to bootstrap
    # the target. We temporarily make the live environment use:
    #
    #   Artix system/world/galaxy
    #   Arch multilib
    #
    # Then we restore the live ISO when finished.
    # =========================================================================

    info "Preparing live environment for Artix basestrap..."

    cat > /etc/pacman.conf <<EOF
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

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

    LIVE_CONFIG_MODIFIED=1

    # =========================================================================
    # Base install
    # =========================================================================

    info "Installing Artix base, kernel, and $INIT_SYSTEM..."

    case "$INIT_SYSTEM" in
        openrc)
            basestrap /mnt \
                base \
                base-devel \
                openrc \
                elogind-openrc \
                linux \
                linux-firmware \
                sof-firmware
            ;;

        runit)
            basestrap /mnt \
                base \
                base-devel \
                runit \
                elogind-runit \
                linux \
                linux-firmware \
                sof-firmware
            ;;

        dinit)
            basestrap /mnt \
                base \
                base-devel \
                dinit \
                elogind-dinit \
                linux \
                linux-firmware \
                sof-firmware
            ;;

        s6)
            basestrap /mnt \
                base \
                base-devel \
                s6-base \
                elogind-s6 \
                linux \
                linux-firmware \
                sof-firmware
            ;;
    esac

    # =========================================================================
    # Install exact repository configuration into target.
    #
    # We deliberately start with the Arch-style pacman.conf from the live ISO,
    # then transform only the repositories we want.
    # =========================================================================

    info "Configuring target repositories..."

    cp "$LIVE_PACMAN_CONF_BACKUP" /mnt/etc/pacman.conf

    # The target gets the exact Artix mirrorlist package we just installed.
    cp /etc/pacman.d/mirrorlist \
       /mnt/etc/pacman.d/mirrorlist

    # The target gets Arch's mirrorlist provided by
    # artix-archlinux-support.
    cp /etc/pacman.d/mirrorlist-arch \
       /mnt/etc/pacman.d/mirrorlist-arch

    # -------------------------------------------------------------------------
    # Replace Arch core -> Artix system
    # Replace Arch extra -> Artix world
    #
    # DO NOT enable Arch core.
    # -------------------------------------------------------------------------

    sed -i \
        -e 's/^\[core\]$/[system]/' \
        -e 's/^\[extra\]$/[world]/' \
        /mnt/etc/pacman.conf

    # Change the existing core/extra mirrorlist Includes to the Artix list.
    sed -i \
        '/^\[system\]/,/^\[/ {
            s#^Include = /etc/pacman.d/mirrorlist-arch$#Include = /etc/pacman.d/mirrorlist#
        }' \
        /mnt/etc/pacman.conf

    sed -i \
        '/^\[world\]/,/^\[/ {
            s#^Include = /etc/pacman.d/mirrorlist-arch$#Include = /etc/pacman.d/mirrorlist#
        }' \
        /mnt/etc/pacman.conf

    # Handle the normal Arch default Include path too.
    sed -i \
        '/^\[system\]/,/^\[/ {
            s#^Include = /etc/pacman.d/mirrorlist$#Include = /etc/pacman.d/mirrorlist#
        }' \
        /mnt/etc/pacman.conf

    sed -i \
        '/^\[world\]/,/^\[/ {
            s#^Include = /etc/pacman.d/mirrorlist$#Include = /etc/pacman.d/mirrorlist#
        }' \
        /mnt/etc/pacman.conf

    # -------------------------------------------------------------------------
    # Remove Arch core if the original pacman.conf had any duplicate core
    # section that our simple substitution did not catch.
    # -------------------------------------------------------------------------

    if grep -q '^\[core\]$' /mnt/etc/pacman.conf; then
        warn "Removing remaining Arch [core] repository."
        sed -i '/^\[core\]$/,/^[[:space:]]*$/d' /mnt/etc/pacman.conf
    fi

    # -------------------------------------------------------------------------
    # Add Galaxy.
    # -------------------------------------------------------------------------

    if ! grep -q '^\[galaxy\]$' /mnt/etc/pacman.conf; then
        cat >> /mnt/etc/pacman.conf <<'EOF'

[galaxy]
Include = /etc/pacman.d/mirrorlist
EOF
    fi

    # -------------------------------------------------------------------------
    # Configure Arch multilib.
    #
    # IMPORTANT:
    #   This is Arch's [multilib], NOT Artix [lib32].
    # -------------------------------------------------------------------------

    if [ "$ENABLE_MULTILIB" = "yes" ]; then

        info "Enabling Arch multilib..."

        # If the original Arch config already contains [multilib], change its
        # Include to mirrorlist-arch.
        if grep -q '^\[multilib\]$' /mnt/etc/pacman.conf; then

            sed -i \
                '/^\[multilib\]/,/^[[]/ {
                    s#^#PLACEHOLDER#
                }' \
                /dev/null 2>/dev/null || true

            # Use awk because it is safer than trying to mutate an arbitrary
            # amount of whitespace/comments with sed.
            awk '
            BEGIN { in_multilib=0; changed=0 }

            /^\[multilib\]$/ {
                in_multilib=1
                print
                next
            }

            /^\[/ {
                if (in_multilib && !changed) {
                    print "Include = /etc/pacman.d/mirrorlist-arch"
                    changed=1
                }
                in_multilib=0
                print
                next
            }

            {
                if (in_multilib && $0 ~ /^[[:space:]]*Include[[:space:]]*=/) {
                    if (!changed) {
                        print "Include = /etc/pacman.d/mirrorlist-arch"
                        changed=1
                    }
                    next
                }

                print
            }

            END {
                if (in_multilib && !changed)
                    print "Include = /etc/pacman.d/mirrorlist-arch"
            }
            ' /mnt/etc/pacman.conf > /mnt/etc/pacman.conf.tmp

            mv /mnt/etc/pacman.conf.tmp /mnt/etc/pacman.conf

        else

            cat >> /mnt/etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

        fi

    else

        # Multilib is disabled. Remove the existing Arch multilib section so
        # there is no accidental Arch repository usage.
        sed -i \
            '/^\[multilib\]$/,/^[[]/ {
                /^\[multilib\]$/d
                /^Include = \/etc\/pacman.d\/mirrorlist$/d
                /^Include = \/etc\/pacman.d\/mirrorlist-arch$/d
            }' \
            /mnt/etc/pacman.conf

    fi

    # =========================================================================
    # Print final repository configuration before continuing.
    # =========================================================================

    info "Final target repository configuration:"
    echo ""
    sed -n \
        '/^\[system\]/,/^\[/p;
         /^\[world\]/,/^\[/p;
         /^\[galaxy\]/,/^\[/p;
         /^\[multilib\]/,/^\[/p' \
        /mnt/etc/pacman.conf
    echo ""

    # =========================================================================
    # FSTAB
    # =========================================================================

    info "============================================================"
    info " FSTAB"
    info "============================================================"

    info "Generating /etc/fstab..."

    fstabgen -U /mnt > /mnt/etc/fstab

    info "fstab contents:"
    cat /mnt/etc/fstab
    echo ""

fi

# =============================================================================
# From here on, both Arch/systemd and Artix/non-systemd installations use
# the same Visnux chroot configuration.
# =============================================================================

info "============================================================"
info " WRITING IN-CHROOT SCRIPT"
info "============================================================"

cat > /mnt/root/chroot-install.sh <<CHROOT_EOF
#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "\${GREEN}[CHROOT]\${NC}  \$*"; }
warn()  { echo -e "\${YELLOW}[CHROOT]\${NC}  \$*"; }

BOOT_MODE="${BOOT_MODE}"
INIT_SYSTEM="${INIT_SYSTEM}"
NEW_HOSTNAME="${NEW_HOSTNAME}"
GRUB_DISK="${GRUB_DISK}"
ENABLE_MULTILIB="${ENABLE_MULTILIB}"

# =============================================================================
# Time
# =============================================================================

hwclock --systohc

# =============================================================================
# Pacman configuration
# =============================================================================

info "Refreshing package databases..."

pacman -Sy --noconfirm

# =============================================================================
# Hostname
# =============================================================================

echo "\${NEW_HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${NEW_HOSTNAME}.localdomain \${NEW_HOSTNAME}
EOF

# =============================================================================
# Visnux identity
# =============================================================================

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

# =============================================================================
# Locale
# =============================================================================

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen

locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

# =============================================================================
# Pacman settings
# =============================================================================

sed -i 's/^#*ParallelDownloads = .*/ParallelDownloads = 12/' /etc/pacman.conf

if ! grep -q '^Color$' /etc/pacman.conf; then
    sed -i '/^ParallelDownloads = 12/a Color' /etc/pacman.conf
fi

if ! grep -q '^ILoveCandy$' /etc/pacman.conf; then
    sed -i '/^ParallelDownloads = 12/a ILoveCandy' /etc/pacman.conf
fi

# =============================================================================
# Init-specific packages and services
# =============================================================================

if [ "\${INIT_SYSTEM}" = "systemd" ]; then

    info "Installing systemd / Arch Visnux desktop..."

    pacman -S --noconfirm \
        plasma \
        konsole \
        dolphin \
        kitty \
        fastfetch \
        sddm \
        networkmanager \
        vim \
        nano \
        sudo

    systemctl enable NetworkManager
    systemctl enable sddm --force

else

    info "Installing Artix / \${INIT_SYSTEM} Visnux desktop..."

    pacman -S --noconfirm \
        plasma \
        konsole \
        dolphin \
        kitty \
        fastfetch \
        sddm \
        sddm-\${INIT_SYSTEM} \
        networkmanager \
        networkmanager-\${INIT_SYSTEM} \
        dbus \
        dbus-\${INIT_SYSTEM} \
        cronie \
        cronie-\${INIT_SYSTEM} \
        vim \
        nano \
        sudo

    case "\${INIT_SYSTEM}" in

        openrc)

            info "Configuring OpenRC services..."

            rc-update add elogind default
            rc-update add dbus default
            rc-update add NetworkManager default
            rc-update add cronie default
            rc-update add sddm default

            ;;

        runit)

            info "Configuring runit services..."

            mkdir -p /etc/runit/runsvdir/default

            for service in \
                dbus \
                elogind \
                NetworkManager \
                cronie \
                sddm
            do
                if [ -d "/etc/runit/sv/\${service}" ] \
                    && [ ! -e "/etc/runit/runsvdir/default/\${service}" ]; then
                    ln -s "/etc/runit/sv/\${service}" \
                        "/etc/runit/runsvdir/default/\${service}"
                fi
            done

            ;;

        dinit)

            info "Configuring dinit services..."

            mkdir -p /etc/dinit.d/boot.d

            for service in \
                dbus \
                elogind \
                NetworkManager \
                cronie \
                sddm
            do
                if [ -e "/etc/dinit.d/\${service}" ] \
                    && [ ! -e "/etc/dinit.d/boot.d/\${service}" ]; then
                    ln -s "../\${service}" \
                        "/etc/dinit.d/boot.d/\${service}"
                fi
            done

            ;;

        s6)

            info "Configuring s6 services..."

            mkdir -p /etc/s6/adminsv/default/contents.d

            for service in \
                dbus \
                elogind \
                NetworkManager \
                cronie \
                sddm
            do
                if [ -d "/etc/s6/rc-service/\${service}" ] \
                    || [ -d "/etc/s6/sv/\${service}" ] \
                    || [ -d "/etc/s6-rc/compiled/\${service}" ]; then
                    touch "/etc/s6/adminsv/default/contents.d/\${service}"
                fi
            done

            if command -v s6-db-reload >/dev/null 2>&1; then
                s6-db-reload || true
            fi

            ;;

    esac

fi

# =============================================================================
# GRUB
# =============================================================================

info "Installing GRUB..."

if [ "\${BOOT_MODE}" = "uefi" ]; then

    pacman -S --noconfirm grub efibootmgr

    grub-install \
        --target=x86_64-efi \
        --efi-directory=/boot/efi

else

    pacman -S --noconfirm grub

    grub-install \
        --recheck \
        "\${GRUB_DISK}"

fi

# =============================================================================
# GRUB distributor
# =============================================================================

if grep -q '^GRUB_DISTRIBUTOR=' /etc/default/grub; then
    sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="Visnux"/' /etc/default/grub
else
    echo 'GRUB_DISTRIBUTOR="Visnux"' >> /etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg

# =============================================================================
# Root password
# =============================================================================

echo ""
info "============================================================"
info " Set the ROOT password:"
info "============================================================"

passwd

# =============================================================================
# Optional user
# =============================================================================

echo ""
echo -e "\${CYAN}[INPUT]\${NC} Would you like to create a new user? (y/n)"
read -rp "  Choice: " CREATE_USER

if [ "\${CREATE_USER}" = "y" ]; then

    echo -e "\${CYAN}[INPUT]\${NC} Enter the new username:"
    read -rp "  Username: " NEW_USER

    if [ -z "\${NEW_USER}" ]; then

        warn "No username entered — skipping user creation."

    else

        useradd \
            -m \
            -G wheel,audio,video,input \
            -s /bin/bash \
            "\${NEW_USER}"

        info "User '\${NEW_USER}' created and added to:"
        info "  wheel audio video input"

        info "Set a password for '\${NEW_USER}':"
        passwd "\${NEW_USER}"

        mkdir -p /etc/sudoers.d

        cat > /etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

        chmod 440 /etc/sudoers.d/10-wheel

        # ---------------------------------------------------------------------
        # Dotfiles
        # ---------------------------------------------------------------------

        info "Cloning and setting up dotfiles for '\${NEW_USER}'..."

        su - "\${NEW_USER}" -c '
            set -e

            cd ~

            mkdir -p ~/.config

            git clone https://github.com/beamyyl/maindots

            cp -r maindots/* ~/.config/

            rm -rf maindots

            git clone https://github.com/realv1sta/larphub

            if [ -f ~/.config/fastfetch/logo.txt ]; then
                rm ~/.config/fastfetch/logo.txt
            fi

            mkdir -p ~/.config/fastfetch

            cp larphub/visnuxlogo.txt \
                ~/.config/fastfetch/logo.txt

            rm -rf larphub

            if [ -f ~/.config/fastfetch/config.jsonc ]; then
                sed -i '\''s/"top": 2/"top": 0/'\'' \
                    ~/.config/fastfetch/config.jsonc
            fi
        '

        info "Dotfiles installed successfully."
        info "User setup complete."

    fi

else

    info "Skipping user creation."

fi

# =============================================================================
# Final repository display
# =============================================================================

echo ""

if [ "\${INIT_SYSTEM}" != "systemd" ]; then

    info "Final repository configuration:"

    echo ""

    grep -E '^\[(system|world|galaxy|multilib)\]$|^Include = ' \
        /etc/pacman.conf || true

    echo ""

fi

# =============================================================================
# Done
# =============================================================================

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

    arch-chroot /mnt \
        /bin/bash \
        /root/chroot-install.sh

else

    artix-chroot /mnt \
        /bin/bash \
        /root/chroot-install.sh

fi

# =============================================================================
# Cleanup
# =============================================================================

info "============================================================"
info " CLEANUP"
info "============================================================"

rm -f /mnt/root/chroot-install.sh

# restore_live_environment is also called by EXIT trap.
restore_live_environment

info "Unmounting filesystems..."

umount -R /mnt 2>/dev/null || true

echo ""
info "============================================================"
info " All done! Remove your installation media and reboot."
info "============================================================"
