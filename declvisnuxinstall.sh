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
echo -e "${CYAN}║                    VISNUX INSTALLER                      ║${NC}"
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

    info "Bootstrapping Visnux..."
    command -v pacstrap &>/dev/null || die "'pacstrap' not found."

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
# VPK declarative package manifest
# =============================================================================
info "============================================================"
info " WRITING VPK PACKAGE MANIFEST"
info "============================================================"

mkdir -p /mnt/etc/visnux /mnt/var/lib/vpk /mnt/usr/bin

cat > /mnt/usr/bin/vpk <<'VPK_EOF'
#!/bin/bash
# =============================================================================
# vpk — Visnux Declarative Package Sync Tool
# usage: vpk [--check | --sync | --path /path/to/manifest]
# =============================================================================

set -euo pipefail

MANIFEST="/etc/visnux/packages.decl"
ACTION="sync"
STATE_FILE="/var/lib/vpk/state"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--check) ACTION="check"; shift ;;
        -s|--sync)  ACTION="sync"; shift ;;
        -p|--path)
            [[ $# -ge 2 ]] || { echo -e "${RED}[FAIL]${NC} --path requires a manifest path."; exit 1; }
            MANIFEST="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: vpk [--check | --sync | --path /path/to/manifest]"
            exit 0
            ;;
        *)
            echo -e "${RED}[FAIL]${NC} Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ ! -f "$MANIFEST" ]]; then
    echo -e "${RED}[FAIL]${NC} Manifest '$MANIFEST' not found!"
    exit 1
fi

echo -e "${CYAN}[VPK]${NC} Reading manifest: $MANIFEST"

# Parse every "pkgs = { ... }" block. Package names are comma-separated.
# Comments and whitespace are ignored, so the manifest can be formatted
# however you like as long as package names stay inside a pkgs = { ... } block.
parse_manifest() {
    awk '
        BEGIN { in_block=0 }
        {
            line=$0
            sub(/#.*/, "", line)

            if (!in_block && line ~ /^[[:space:]]*pkgs[[:space:]]*=[[:space:]]*\{/) {
                in_block=1
                sub(/^.*\{/, "", line)
            }

            if (in_block) {
                if (line ~ /\}/) {
                    sub(/\}.*/, "", line)
                    in_block=0
                }

                n=split(line, parts, ",")
                for (i=1; i<=n; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                    if (parts[i] != "")
                        print parts[i]
                }
            }
        }
    ' "$MANIFEST" | sort -u
}

mapfile -t DECLARED_ARRAY < <(parse_manifest)

if [[ ${#DECLARED_ARRAY[@]} -eq 0 ]]; then
    echo -e "${YELLOW}[WARN]${NC} No packages extracted from $MANIFEST"
    exit 0
fi

echo -e "${GREEN}[INFO]${NC} ${#DECLARED_ARRAY[@]} declared packages parsed."

mkdir -p "$(dirname "$STATE_FILE")"

# The state file contains ONLY packages previously managed by vpk.
# This is what makes removals safe: vpk does not remove arbitrary packages
# that happen to be installed outside of the declarative manifest.
mapfile -t PREVIOUS_ARRAY < <(
    if [[ -f "$STATE_FILE" ]]; then
        sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$STATE_FILE" | sort -u
    fi
)

MISSING=()
for pkg in "${DECLARED_ARRAY[@]}"; do
    if ! pacman -Q "$pkg" &>/dev/null; then
        MISSING+=("$pkg")
    fi
done

REMOVED=()
if [[ ${#PREVIOUS_ARRAY[@]} -gt 0 ]]; then
    for pkg in "${PREVIOUS_ARRAY[@]}"; do
        if ! printf '%s\n' "${DECLARED_ARRAY[@]}" | grep -qFx "$pkg"; then
            if pacman -Q "$pkg" &>/dev/null; then
                REMOVED+=("$pkg")
            fi
        fi
    done
fi

echo -e "${GREEN}[INFO]${NC} Desired state: ${#DECLARED_ARRAY[@]} package(s)."

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${YELLOW}[ADD]${NC} ${#MISSING[@]} declared package(s) missing from system:"
    printf '  + %s\n' "${MISSING[@]}"
fi

if [[ ${#REMOVED[@]} -gt 0 ]]; then
    echo -e "${YELLOW}[REMOVE]${NC} ${#REMOVED[@]} package(s) no longer declared:"
    printf '  - %s\n' "${REMOVED[@]}"
fi

if [[ ${#MISSING[@]} -eq 0 && ${#REMOVED[@]} -eq 0 ]]; then
    echo -e "${GREEN}[OK]${NC} System matches manifest state cleanly."
    cp <(printf '%s\n' "${DECLARED_ARRAY[@]}") "$STATE_FILE"
    exit 0
fi

if [[ "$ACTION" == "check" ]]; then
    echo -e "${YELLOW}[CHECK]${NC} Declarative state differs from the manifest."
    exit 1
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${CYAN}[SYNC]${NC} Installing declared packages..."
    pacman -S --needed --noconfirm "${MISSING[@]}"
fi

if [[ ${#REMOVED[@]} -gt 0 ]]; then
    echo -e "${CYAN}[SYNC]${NC} Removing packages no longer declared..."
    pacman -Rns --noconfirm "${REMOVED[@]}"
fi

# Only write the new state after every pacman operation succeeded.
printf '%s\n' "${DECLARED_ARRAY[@]}" > "$STATE_FILE"

echo -e "${GREEN}[OK]${NC} Sync complete!"

VPK_EOF
chmod +x /mnt/usr/bin/vpk

# The installer still performs imperative configuration (services, GRUB
# installation/configuration, files, symlinks, users, swap, branding, etc.).
# VPK owns only packages listed in this manifest.
csv() {
    local value="$*"
    value="${value// /, }"
    printf '%s' "$value"
}

VPK_BOOT_PKGS="grub"
if [ "$BOOT_MODE" = "uefi" ]; then
    VPK_BOOT_PKGS="$VPK_BOOT_PKGS efibootmgr"
fi

VPK_DRIVER_PKGS="mesa lib32-mesa vulkan-intel lib32-vulkan-intel vulkan-radeon lib32-vulkan-radeon \
vulkan-nouveau lib32-vulkan-nouveau vulkan-swrast lib32-vulkan-swrast libva intel-media-driver"

if [ "$INIT_SYSTEM" = "systemd" ]; then
    VPK_INIT_PKGS="networkmanager"
else
    VPK_INIT_PKGS="networkmanager-${INIT_SYSTEM} dbus-${INIT_SYSTEM} turnstile turnstile-${INIT_SYSTEM}"
fi

if [ "$DESKTOP_ENV" = "none" ]; then
    VPK_DESKTOP_PKGS=""
elif [ "$INIT_SYSTEM" = "systemd" ] && [ "$DESKTOP_ENV" = "kde" ]; then
    VPK_DESKTOP_PKGS="plasma ark konsole dolphin xdg-desktop-portal-kde wl-clipboard kitty fastfetch sddm power-profiles-daemon"
elif [ "$INIT_SYSTEM" = "systemd" ] && [ "$DESKTOP_ENV" = "xfce" ]; then
    VPK_DESKTOP_PKGS="xfce4 xfce4-whiskermenu-plugin ark xclip maim xfce4-pulseaudio-plugin kitty fastfetch sddm power-profiles-daemon"
elif [ "$DESKTOP_ENV" = "kde" ]; then
    VPK_DESKTOP_PKGS="plasma konsole dolphin kitty ark xdg-desktop-portal-kde fastfetch wl-clipboard \
sddm-${INIT_SYSTEM} power-profiles-daemon-${INIT_SYSTEM} pipewire pipewire-${INIT_SYSTEM} \
pipewire-pulse pipewire-pulse-${INIT_SYSTEM} wireplumber wireplumber-${INIT_SYSTEM}"
else
    VPK_DESKTOP_PKGS="xorg-server xfce4 xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin \
kitty ark fastfetch sddm-${INIT_SYSTEM} xclip maim power-profiles-daemon-${INIT_SYSTEM} \
pipewire pipewire-${INIT_SYSTEM} pipewire-pulse pipewire-pulse-${INIT_SYSTEM} \
wireplumber wireplumber-${INIT_SYSTEM}"
fi

cat > /mnt/etc/visnux/packages.decl <<EOF
# /etc/visnux/packages.decl
#
# VPK owns packages listed in this file.
# Service enabling, GRUB installation, symlinks, configuration files, users,
# swap, branding, and other system changes remain in the installer.

[kernel]
pkgs = { linux, linux-headers, linux-firmware, sof-firmware }

[bootmgr]
pkgs = { $(csv "$VPK_BOOT_PKGS") }

[desktop]
pkgs = { $(csv "$VPK_DESKTOP_PKGS") }

[fonts]
pkgs = { ttf-iosevka-nerd, ttf-adwaitamono-nerd }

[cli-tools]
pkgs = { neovim, nano, sudo, fish, flatpak }

[network]
pkgs = { $(csv "$VPK_INIT_PKGS") }

[drivers]
pkgs = { $(csv "$VPK_DRIVER_PKGS") }

[extra]
pkgs = { git, papirus-icon-theme }
EOF

info "VPK manifest written to /mnt/etc/visnux/packages.decl"

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
DESKTOP_ENV="${DESKTOP_ENV}"
NEW_HOSTNAME="${NEW_HOSTNAME}"
GRUB_DISK="${GRUB_DISK}"

hwclock --systohc

# VPK handles package installation. Everything below this point that is not
# a package operation remains imperative on purpose.
vpk --sync

mkdir -p /usr/share/icons/hicolor/scalable/apps/
mkdir -p /usr/share/pixmaps/

echo "\${NEW_HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${NEW_HOSTNAME}.localdomain \${NEW_HOSTNAME}
EOF

cat > /etc/os-release <<'EOF'
NAME="Visnux"
PRETTY_NAME="Visnux Linux"
ID=visnux
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;85;255;85"
HOME_URL="https://visnux.duckdns.org/"
DOCUMENTATION_URL="https://visnux.duckdns.org/"
LOGO=visnux
EOF

cat > /etc/lsb-release <<'EOF'
DISTRIB_ID="Visnux"
DISTRIB_RELEASE="rolling"
DISTRIB_DESCRIPTION="Visnux Linux"
EOF

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# =============================================================================
# Desktop / system packages
# =============================================================================

if [ "\${INIT_SYSTEM}" = "systemd" ]; then

    if [ "\${DESKTOP_ENV}" = "kde" ]; then
        systemctl enable NetworkManager
        systemctl enable sddm --force

    elif [ "\${DESKTOP_ENV}" = "xfce" ]; then
        systemctl enable NetworkManager
        systemctl enable sddm --force

    else
        info "Skipping Desktop Environment installation."
        systemctl enable NetworkManager
    fi

else

    if [ "\${DESKTOP_ENV}" = "kde" ]; then
        info "KDE package set is declared in /etc/visnux/packages.decl."

    elif [ "\${DESKTOP_ENV}" = "xfce" ]; then
        info "Xfce package set is declared in /etc/visnux/packages.decl."

    else
        info "Skipping Desktop Environment installation."
    fi

    case "\${INIT_SYSTEM}" in
        openrc)
            rc-update add dbus default
            rc-update add elogind default
            rc-update add NetworkManager default
            rc-update add turnstile default
            if [ "\${DESKTOP_ENV}" != "none" ]; then
                rc-update add sddm default
                rc-update add power-profiles-daemon default
            fi
            ;;

        runit)
            mkdir -p /etc/runit/runsvdir/default
            for service in dbus elogind NetworkManager turnstiled; do
                if [ -d "/etc/runit/sv/\${service}" ] && [ ! -e "/etc/runit/runsvdir/default/\${service}" ]; then
                    ln -sf "/etc/runit/sv/\${service}" "/etc/runit/runsvdir/default/\${service}"
                fi
            done
            if [ "\${DESKTOP_ENV}" != "none" ] &&
               [ -d "/etc/runit/sv/sddm" ] &&
               [ ! -e "/etc/runit/runsvdir/default/sddm" ]; then
                ln -sf /etc/runit/sv/sddm /etc/runit/runsvdir/default/sddm
                ln -sf /etc/runit/sv/power-profiles-daemon /etc/runit/runsvdir/default/power-profiles-daemon
            fi
            ;;

        dinit)
            ln -sf ../dbus /etc/dinit.d/boot.d/
            ln -sf ../elogind /etc/dinit.d/boot.d/
            ln -sf ../NetworkManager /etc/dinit.d/boot.d/
            ln -sf ../turnstiled /etc/dinit.d/boot.d/
            if [ "\${DESKTOP_ENV}" != "none" ]; then
                ln -sf ../sddm /etc/dinit.d/boot.d/
                ln -sf ../power-profiles-daemon /etc/dinit.d/boot.d/
            fi
            ;;
    esac

fi

# =============================================================================
# DRIVERS
# =============================================================================

info "GPU driver packages are declared in /etc/visnux/packages.decl."

# =============================================================================
# GRUB
# =============================================================================

info "Installing GRUB..."

if [ "\${BOOT_MODE}" = "uefi" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=visnux
else
    grub-install --recheck "\${GRUB_DISK}"
fi

sed -i 's/GRUB_DISTRIBUTOR="Arch"/GRUB_DISTRIBUTOR="Visnux"/' /etc/default/grub
sed -i 's/GRUB_DISTRIBUTOR="Artix"/GRUB_DISTRIBUTOR="Visnux"/' /etc/default/grub

git clone https://github.com/realv1sta/larphub
cp -r larphub/neveraskmewhatthisis/Office-sidebar /boot/grub/themes
cp larphub/visnux.svg /usr/share/icons/hicolor/scalable/apps/visnux.svg
cp larphub/visnux.png /usr/share/pixmaps/visnux.png
mkdir -p ~/.config/fastfetch
chmod +x larphub/colorlogo.sh && cd larphub/ && ./colorlogo.sh > ~/.config/fastfetch/logo.txt
cp neveraskmewhatthisis/config.jsonc ~/.config/fastfetch/
mkdir -p /etc/skel/.config
cp -r neveraskmewhatthisis/xfce4 /etc/skel/.config/
cp -r neveraskmewhatthisis/fish /etc/skel/.config/
cp neveraskmewhatthisis/plasma-org.kde.plasma.desktop-appletsrc /etc/skel/.config/
cp -r neveraskmewhatthisis/otherconfigs/* /etc/skel/.config
git clone https://github.com/beamyyl/fastfetch
cp -r fastfetch/* /etc/skel/.config/
./colorlogo.sh > /etc/skel/.config/fastfetch/logo.txt
mkdir -p /usr/share/wallpapers/
mkdir -p /usr/share/backgrounds/visnux
cp -r walls/visnux-walls/* /usr/share/wallpapers/
cp -r walls/visnux-walls/* /usr/share/backgrounds/visnux/
cd ..
rm -rf larphub

fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

echo 'GRUB_THEME=/boot/grub/themes/Office-sidebar/theme.txt' | tee -a /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo ""
info "============================================================"
info " Set the ROOT password:"
info "============================================================"

while ! passwd; do
    warn "Password change failed or passwords did not match. Please try again."
done

echo ""
echo -e "\${CYAN}[INPUT]\${NC} Would you like to create a new user? (y/n)"
read -rp "  Choice: " CREATE_USER

if [[ "\${CREATE_USER}" =~ ^[Yy]$ ]]; then

    while true; do
        echo -e "\${CYAN}[INPUT]\${NC} Enter the new username:"
        read -rp "  Username: " NEW_USER

        if [ -n "\${NEW_USER}" ]; then
            break
        fi

        warn "Username cannot be empty. Please try again."
    done

    echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
    chmod 440 /etc/sudoers.d/wheel

    useradd -m -G wheel,audio,video,input -s /usr/bin/fish "\${NEW_USER}"

    info "User '\${NEW_USER}' created and added to: wheel, audio, video, input"
    info "Set a password for '\${NEW_USER}':"

    while ! passwd "\${NEW_USER}"; do
        warn "Password change failed or passwords did not match. Please try again."
    done

    info "Cloning and setting up dotfiles for '\${NEW_USER}'..."
    su - "\${NEW_USER}" -c "cd ~ && mkdir -p ~/.config && git clone https://github.com/beamyyl/maindots && cp -r maindots/* ~/.config/ && rm -rf maindots && [ ! -f ~/.config/fastfetch/config.jsonc ] || sed -i 's/\"top\": 2/\"top\": 1/' ~/.config/fastfetch/config.jsonc"
    info "Dotfiles installed successfully."
    info "User setup complete."

elif [[ "\${CREATE_USER}" =~ ^[Nn]$ ]]; then
    info "Skipping user creation."
else
    warn "Invalid choice '\${CREATE_USER}'. Skipping user creation."
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
