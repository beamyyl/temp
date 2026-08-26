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
echo -e "${CYAN}[INPUT]${NC} Do you want to install Visnux in a declarative way?"
echo "  This installs VPK and uses /etc/visnux/visnux.conf."
echo "  [y] Declarative (VPK)"
echo "  [n] Traditional / imperative installer"
read -rp "  Choice [y/N]: " DECLARATIVE_CHOICE
if [[ "$DECLARATIVE_CHOICE" =~ ^[Yy]$ ]]; then
    DECLARATIVE_MODE="yes"
else
    DECLARATIVE_MODE="no"
fi
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
DECLARATIVE_MODE="${DECLARATIVE_MODE}"

hwclock --systohc

if [ "\${DECLARATIVE_MODE}" != "yes" ]; then
    pacman -Sy --noconfirm git
    pacman -S --noconfirm ttf-iosevka-nerd ttf-adwaitamono-nerd
    pacman -S --noconfirm fish flatpak
    pacman -S --noconfirm papirus-icon-theme
fi
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

if [ "\${DECLARATIVE_MODE}" = "yes" ]; then
    info "Declarative installation selected. Generating /etc/visnux/visnux.conf..."

    mkdir -p /etc/visnux /var/lib/vpk
    DESKTOP_METAPKGS=""
    DESKTOP_PKGS=""
    SERVICE_PKGS="networkmanager"
    ENABLED_SERVICES="NetworkManager"

    if [ "\${DESKTOP_ENV}" = "kde" ]; then
        DESKTOP_METAPKGS="plasma"
        DESKTOP_PKGS="ark konsole dolphin xdg-desktop-portal-kde wl-clipboard"
    elif [ "\${DESKTOP_ENV}" = "xfce" ]; then
        DESKTOP_METAPKGS="xfce4"
        DESKTOP_PKGS="xfce4-whiskermenu-plugin ark xclip maim xfce4-pulseaudio-plugin"
    else
        info "Skipping Desktop Environment installation."
    fi

    if [ "\${DESKTOP_ENV}" != "none" ]; then
        SERVICE_PKGS="\${SERVICE_PKGS} sddm power-profiles-daemon"
        ENABLED_SERVICES="\${ENABLED_SERVICES} sddm power-profiles-daemon"
    fi

    cat > /etc/visnux/visnux.conf <<EOF
# =============================================================================
# Visnux Declarative Configuration
# =============================================================================

[kernel]
pkgs = { linux, linux-headers, linux-firmware, sof-firmware }

[bootmgr]
pkgs = { grub, efibootmgr }

[desktop]
metapkgs = { \${DESKTOP_METAPKGS} }
pkgs = { \${DESKTOP_PKGS} }

[fonts]
pkgs = { ttf-iosevka-nerd, ttf-adwaitamono-nerd }

[packages]
pkgs = { git, papirus-icon-theme, neovim, nano, sudo, fish, flatpak, fastfetch, kitty }

[services]
pkgs = { \${SERVICE_PKGS} }
enabled = { \${ENABLED_SERVICES} }

[drivers]
pkgs = { mesa, lib32-mesa, vulkan-intel, lib32-vulkan-intel, vulkan-radeon, lib32-vulkan-radeon, vulkan-nouveau, lib32-vulkan-nouveau, vulkan-swrast, lib32-vulkan-swrast, libva, intel-media-driver }

# =============================================================================
# Users
# =============================================================================
# A user is added automatically only if you choose to create one.
#
# Template:
# [user:alice]
# groups = { wheel, audio, video, input }
# shell = /usr/bin/fish
#
# [user-services]
# alice = { pipewire, wireplumber, pipewire-pulse }


# do NOT change the lines below this comment
init = \${INIT_SYSTEM}
EOF

    cat > /usr/bin/vpk <<'VPK_EOF'
#!/bin/bash
# =============================================================================
# vpk — Visnux Declarative Package Sync Tool
# usage: vpk [sync | check] [--path /path/to/manifest]
# =============================================================================

set -euo pipefail

MANIFEST="/etc/visnux/visnux.conf"
ACTION="sync"
STATE_DIR="/var/lib/vpk"
PACKAGE_STATE="\$STATE_DIR/packages.state"
SERVICE_STATE="\$STATE_DIR/services.state"
USER_STATE="\$STATE_DIR/users.state"
USER_SERVICE_STATE="\$STATE_DIR/user-services.state"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

if [[ "\$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "\$0" "\$@"
    fi
    echo -e "\${RED}[FAIL]\${NC} vpk must run as root."
    exit 1
fi

while [[ \$# -gt 0 ]]; do
    case "\$1" in
        sync) ACTION="sync"; shift ;;
        check|-c|--check) ACTION="check"; shift ;;
        --path|-p)
            [[ \$# -ge 2 ]] || { echo -e "\${RED}[FAIL]\${NC} --path requires a manifest path."; exit 1; }
            MANIFEST="\$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: vpk [sync|check] [--path /path/to/manifest]"
            echo "  sync   Reconcile the manifest and run pacman -Syu first (default)."
            echo "  check  Check declarative state without changing anything."
            exit 0
            ;;
        --sync|-s)
            echo -e "\${RED}[FAIL]\${NC} --sync is no longer a VPK command. Use: vpk sync"
            exit 1
            ;;
        *) echo -e "\${RED}[FAIL]\${NC} Unknown option: \$1"; exit 1 ;;
    esac
done

[[ -f "\$MANIFEST" ]] || { echo -e "\${RED}[FAIL]\${NC} Manifest '\$MANIFEST' not found!"; exit 1; }

mkdir -p "\$STATE_DIR"

echo -e "\${CYAN}[VPK]\${NC} Reading manifest: \$MANIFEST"

if [[ "\$ACTION" == "sync" ]]; then
    echo -e "\${CYAN}[UPGRADE]\${NC} Running pacman -Syu..."
    pacman -Syu --noconfirm
fi

INIT="systemd"
declare -a DECLARED_PKGS=()
declare -a META_PKGS=()
declare -a SERVICE_PKGS=()
declare -a ENABLED_SERVICES=()
declare -A USERS=()
declare -A USER_GROUPS=()
declare -A USER_SHELLS=()
declare -A USER_SERVICES=()

trim() {
    local x="\$1"
    x="\${x#"\${x%%[![:space:]]*}"}"
    x="\${x%"\${x##*[![:space:]]}"}"
    printf '%s' "\$x"
}

parse_list() {
    local body="\$1" item
    body="\${body//,/ }"
    read -ra _items <<< "\$body"
    for item in "\${_items[@]}"; do
        item="\$(trim "\$item")"
        [[ -n "\$item" ]] && printf '%s\n' "\$item"
    done
}

SECTION=""
CURRENT_USER=""

while IFS= read -r line || [[ -n "\$line" ]]; do
    line="\${line%%#*}"
    line="\$(trim "\$line")"
    [[ -z "\$line" ]] && continue

    if [[ "\$line" =~ ^\[user:([^]]+)\]\$ ]]; then
        CURRENT_USER="\${BASH_REMATCH[1]}"
        SECTION="user"
        USERS["\$CURRENT_USER"]=1
        continue
    fi

    if [[ "\$line" =~ ^\[([^]]+)\]\$ ]]; then
        SECTION="\${BASH_REMATCH[1]}"
        CURRENT_USER=""
        continue
    fi

    if [[ "\$line" =~ ^init[[:space:]]*=[[:space:]]*([a-zA-Z0-9_-]+)\$ ]]; then
        INIT="\${BASH_REMATCH[1]}"
        continue
    fi

    if [[ "\$SECTION" == "user" && -n "\$CURRENT_USER" ]]; then
        if [[ "\$line" =~ ^groups[[:space:]]*=[[:space:]]*\{(.*)\}\$ ]]; then
            USER_GROUPS["\$CURRENT_USER"]="\${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "\$line" =~ ^shell[[:space:]]*=[[:space:]]*(.*)\$ ]]; then
            USER_SHELLS["\$CURRENT_USER"]="\$(trim "\${BASH_REMATCH[1]}")"
            continue
        fi
    fi

    if [[ "\$SECTION" == "user-services" && "\$line" =~ ^([^=]+)=[[:space:]]*\{(.*)\}\$ ]]; then
        user="\$(trim "\${BASH_REMATCH[1]}")"
        USER_SERVICES["\$user"]="\${BASH_REMATCH[2]}"
        continue
    fi

    if [[ "\$line" =~ ^metapkgs[[:space:]]*=[[:space:]]*\{(.*)\}\$ ]]; then
        [[ "\$SECTION" == "desktop" ]] || { echo -e "\${RED}[FAIL]\${NC} metapkgs is only valid in [desktop]."; exit 1; }
        while IFS= read -r pkg; do [[ -n "\$pkg" ]] && META_PKGS+=("\$pkg"); done < <(parse_list "\${BASH_REMATCH[1]}")
        continue
    fi

    if [[ "\$line" =~ ^pkgs[[:space:]]*=[[:space:]]*\{(.*)\}\$ ]]; then
        while IFS= read -r pkg; do
            [[ -z "\$pkg" ]] && continue
            if [[ "\$SECTION" == "services" ]]; then SERVICE_PKGS+=("\$pkg"); else DECLARED_PKGS+=("\$pkg"); fi
        done < <(parse_list "\${BASH_REMATCH[1]}")
        continue
    fi

    if [[ "\$SECTION" == "services" && "\$line" =~ ^enabled[[:space:]]*=[[:space:]]*\{(.*)\}\$ ]]; then
        while IFS= read -r service; do
            [[ -n "\$service" ]] && ENABLED_SERVICES+=("\$service")
        done < <(parse_list "\${BASH_REMATCH[1]}")
    fi
done < "\$MANIFEST"

case "\$INIT" in
    systemd|openrc|runit|dinit) ;;
    *) echo -e "\${RED}[FAIL]\${NC} Invalid init '\$INIT'."; exit 1 ;;
esac

# =============================================================================
# Package reconciliation
# =============================================================================
# A manifest target can be either a real package or a pacman package group.
# Groups such as xfce4/plasma are NOT entries in pacman's installed-package
# database, so pacman -Qq "\$target" is not a valid group-presence test.

is_package() {
    pacman -Qq "\$1" &>/dev/null
}
is_group() {
    pacman -Sg "\$1" &>/dev/null
}
group_members() {
    pacman -Sg "\$1" | awk '{print \$2}' | sort -u
}
declare -A desired_target_kind=()
declare -A desired_group_members=()
declare -A desired_install_pkg=()
declare -a invalid_targets=()

add_package_target() {
    local target="\$1"
    [[ -n "\$target" ]] || return
    if is_package "\$target" || pacman -Si "\$target" &>/dev/null; then
        desired_target_kind["\$target"]="package"
        desired_install_pkg["\$target"]=1
    else
        invalid_targets+=("\$target")
    fi
}
add_meta_target() {
    local target="\$1"
    [[ -n "\$target" ]] || return
    if ! is_group "\$target"; then invalid_targets+=("\$target"); return; fi
    desired_target_kind["\$target"]="group"
    desired_group_members["\$target"]="\$(group_members "\$target")"
    while IFS= read -r member; do [[ -n "\$member" ]] && desired_install_pkg["\$member"]=1; done <<< "\${desired_group_members[\$target]}"
}
for pkg in "\${DECLARED_PKGS[@]}"; do add_package_target "\$pkg"; done
for meta in "\${META_PKGS[@]}"; do add_meta_target "\$meta"; done
for pkg in "\${SERVICE_PKGS[@]}"; do
    if [[ "\$INIT" == "systemd" ]]; then add_package_target "\$pkg"; else add_package_target "\$pkg-\$INIT"; fi
done

if [[ \${#invalid_targets[@]} -gt 0 ]]; then
    echo -e "\${RED}[FAIL]\${NC} Unknown package/group target(s):"
    printf '  ! %s\n' "\${invalid_targets[@]}"
    exit 1
fi

# Previous state format:
#   package|name
#   group|name|member1 member2 ...
# Older VPK states containing only a package name are accepted as package targets.
declare -a PREVIOUS_TARGETS=()
if [[ -f "\$PACKAGE_STATE" ]]; then
    while IFS= read -r line; do
        [[ -n "\$line" ]] && PREVIOUS_TARGETS+=("\$line")
    done < "\$PACKAGE_STATE"
fi

MISSING_TARGETS=()
MISSING_PACKAGES=()
REMOVED_TARGETS=()
REMOVED_PACKAGES=()

declare -A missing_pkg=()
for target in "\${!desired_target_kind[@]}"; do
    kind="\${desired_target_kind[\$target]}"
    if [[ "\$kind" == "group" ]]; then
        missing=0
        while IFS= read -r member; do
            [[ -n "\$member" ]] || continue
            if ! is_package "\$member"; then
                missing=1
                missing_pkg["\$member"]=1
            fi
        done <<< "\${desired_group_members[\$target]}"
        (( missing )) && MISSING_TARGETS+=("\$target")
    else
        if ! is_package "\$target"; then
            MISSING_TARGETS+=("\$target")
            missing_pkg["\$target"]=1
        fi
    fi
done

for pkg in "\${!missing_pkg[@]}"; do
    MISSING_PACKAGES+=("\$pkg")
done

# Compare the current manifest against VPK's LAST SUCCESSFUL target state.
# This is what lets VPK safely remove a group such as xfce4 when it disappears
# from the manifest without touching unrelated packages.
for entry in "\${PREVIOUS_TARGETS[@]}"; do
    [[ -n "\$entry" ]] || continue

    kind="package"
    target="\$entry"
    members=""
    IFS='|' read -r first second third <<< "\$entry"
    if [[ "\$first" == "package" || "\$first" == "group" ]]; then
        kind="\$first"
        target="\$second"
        members="\$third"
    fi

    if [[ -z "\${desired_target_kind[\$target]+x}" ]]; then
        REMOVED_TARGETS+=("\$target")
        if [[ "\$kind" == "group" ]]; then
            while IFS= read -r member; do
                [[ -n "\$member" ]] || continue
                if is_package "\$member"; then
                    REMOVED_PACKAGES+=("\$member")
                fi
            done < <(tr ' ' '\n' <<< "\$members")
        elif is_package "\$target"; then
            REMOVED_PACKAGES+=("\$target")
        fi
    elif [[ "\$kind" == "group" && "\${desired_target_kind[\$target]}" == "group" ]]; then
        # If a repository changes group membership, remove old members that no
        # longer belong to the declared group.
        current_members="\${desired_group_members[\$target]}"
        while IFS= read -r member; do
            [[ -n "\$member" ]] || continue
            if ! grep -qxF "\$member" <<< "\$current_members" && is_package "\$member"; then
                REMOVED_PACKAGES+=("\$member")
            fi
        done < <(tr ' ' '\n' <<< "\$members")
    fi
done

# Deduplicate removal list.
declare -A unique_removed=()
DEDUP_REMOVED_PACKAGES=()
for pkg in "\${REMOVED_PACKAGES[@]}"; do
    [[ -n "\$pkg" ]] || continue
    if [[ -z "\${unique_removed[\$pkg]+x}" ]]; then
        unique_removed["\$pkg"]=1
        DEDUP_REMOVED_PACKAGES+=("\$pkg")
    fi
done
REMOVED_PACKAGES=("\${DEDUP_REMOVED_PACKAGES[@]}")

if [[ \${#MISSING_TARGETS[@]} -gt 0 ]]; then
    echo -e "\${YELLOW}[ADD]\${NC} \${#MISSING_TARGETS[@]} declared target(s) need installation:"
    printf '  + %s\n' "\${MISSING_TARGETS[@]}"
fi
if [[ \${#REMOVED_TARGETS[@]} -gt 0 ]]; then
    echo -e "\${YELLOW}[REMOVE]\${NC} \${#REMOVED_TARGETS[@]} declared target(s) removed from manifest:"
    printf '  - %s\n' "\${REMOVED_TARGETS[@]}"
fi

if [[ "\$ACTION" == "check" ]]; then
    if [[ \${#MISSING_TARGETS[@]} -gt 0 || \${#REMOVED_TARGETS[@]} -gt 0 ]]; then
        echo -e "\${YELLOW}[CHECK]\${NC} Declarative package state differs from the manifest."
        exit 1
    fi
fi

if [[ "\$ACTION" == "sync" ]]; then
    if [[ \${#MISSING_PACKAGES[@]} -gt 0 ]]; then
        echo -e "\${CYAN}[SYNC]\${NC} Installing declared package/group members..."
        pacman -S --needed --noconfirm "\${MISSING_PACKAGES[@]}"
    fi

    if [[ \${#REMOVED_PACKAGES[@]} -gt 0 ]]; then
        echo -e "\${CYAN}[SYNC]\${NC} Removing packages no longer declared..."
        pacman -Rns --noconfirm "\${REMOVED_PACKAGES[@]}"
    fi

    # Record the declarative targets only after all package operations succeed.
    : > "\$PACKAGE_STATE"
    for target in "\${!desired_target_kind[@]}"; do
        if [[ "\${desired_target_kind[\$target]}" == "group" ]]; then
            members="\${desired_group_members[\$target]}"
            compact_members="\$(tr '\n' ' ' <<< "\$members" | sed 's/[[:space:]]*\$//')"
            printf 'group|%s|%s\n' "\$target" "\$compact_members" >> "\$PACKAGE_STATE"
        else
            printf 'package|%s\n' "\$target" >> "\$PACKAGE_STATE"
        fi
    done
    sort -o "\$PACKAGE_STATE" "\$PACKAGE_STATE"
fi

# =============================================================================
# User reconciliation
# =============================================================================

declare -A desired_user=()
declare -A desired_groups=()
declare -A desired_shell=()
for user in "\${!USERS[@]}"; do
    desired_user["\$user"]=1
    desired_groups["\$user"]="\${USER_GROUPS[\$user]-}"
    desired_shell["\$user"]="\${USER_SHELLS[\$user]-/usr/bin/bash}"
done

mapfile -t PREVIOUS_USERS < <(cat "\$USER_STATE" 2>/dev/null | sort -u || true)
USER_ADDED=()
USER_REMOVED=()
USER_CHANGED=()

user_is_converged() {
    local user="\$1"
    local wanted_shell="\${desired_shell[\$user]}"
    local current_shell
    current_shell="\$(getent passwd "\$user" | cut -d: -f7)"
    [[ "\$current_shell" == "\$wanted_shell" ]] || return 1

    local wanted_groups actual_groups
    wanted_groups="\$(parse_list "\${desired_groups[\$user]}")"
    actual_groups="\$(id -nG "\$user" | tr ' ' '\n' | grep -vx "\$(id -gn "\$user")" | sort || true)"
    wanted_groups="\$(printf '%s\n' "\$wanted_groups" | sed '/^[[:space:]]*\$/d' | sort)"
    [[ "\$actual_groups" == "\$wanted_groups" ]]
}

for user in "\${!desired_user[@]}"; do
    if ! id "\$user" &>/dev/null; then
        USER_ADDED+=("\$user")
    elif ! user_is_converged "\$user"; then
        USER_CHANGED+=("\$user")
    fi
done
for user in "\${PREVIOUS_USERS[@]}"; do
    [[ -n "\$user" ]] || continue
    if [[ -z "\${desired_user[\$user]+x}" ]] && id "\$user" &>/dev/null; then
        USER_REMOVED+=("\$user")
    fi
done

# Validate user-service references before changing anything.
for user in "\${!USER_SERVICES[@]}"; do
    if [[ -z "\${desired_user[\$user]+x}" ]]; then
        echo -e "\${RED}[FAIL]\${NC} User-services section references undeclared user '\$user'."
        exit 1
    fi
done

if [[ "\$ACTION" == "check" ]]; then
    if [[ \${#MISSING_TARGETS[@]} -gt 0 || \${#REMOVED_TARGETS[@]} -gt 0 || \${#USER_ADDED[@]} -gt 0 || \${#USER_REMOVED[@]} -gt 0 || \${#USER_CHANGED[@]} -gt 0 ]]; then
        echo -e "\${YELLOW}[CHECK]\${NC} Declarative state differs from the manifest."
        exit 1
    fi
    echo -e "\${GREEN}[OK]\${NC} Package and user state is present."
    exit 0
fi

# Users are declarative too. VPK never deletes a home directory when a user is
# removed from the manifest; userdel is intentionally used without -r.
for user in "\${USER_ADDED[@]}"; do
    shell="\${desired_shell[\$user]}"
    groups="\${desired_groups[\$user]}"
    [[ -x "\$shell" ]] || { echo -e "\${RED}[FAIL]\${NC} Shell '\$shell' for '\$user' does not exist."; exit 1; }
    args=(-m -s "\$shell")
    if [[ -n "\$groups" ]]; then
        mapfile -t gs < <(parse_list "\$groups")
        args+=( -G "\$(IFS=,; echo "\${gs[*]}")" )
    fi
    echo -e "\${CYAN}[USER]\${NC} Creating \$user"
    useradd "\${args[@]}" "\$user"
done

for user in "\${USER_CHANGED[@]}"; do
    shell="\${desired_shell[\$user]}"
    groups="\${desired_groups[\$user]}"
    [[ -x "\$shell" ]] || { echo -e "\${RED}[FAIL]\${NC} Shell '\$shell' for '\$user' does not exist."; exit 1; }
    usermod -s "\$shell" "\$user"
    if [[ -n "\$groups" ]]; then
        mapfile -t gs < <(parse_list "\$groups")
        usermod -G "\$(IFS=,; echo "\${gs[*]}")" "\$user"
    else
        usermod -G '' "\$user"
    fi
done

# User removals happen after user-service reconciliation so VPK can clean the
# user's declarative service links before deleting the account.

# =============================================================================
# System service enablement
# =============================================================================
# This only changes boot-time enablement. It intentionally does NOT start the
# service now.
# =============================================================================

service_enable() {
    local service="\$1"
    case "\$INIT" in
        systemd)
            systemctl enable "\$service"
            ;;
        openrc)
            rc-update add "\$service" default
            ;;
        runit)
            mkdir -p /etc/runit/runsvdir/default
            [[ -d "/etc/runit/sv/\$service" ]] || return 0
            ln -sfn "/etc/runit/sv/\$service" "/etc/runit/runsvdir/default/\$service"
            ;;
        dinit)
            mkdir -p /etc/dinit.d/boot.d
            [[ -e "/etc/dinit.d/\$service" ]] || return 0
            ln -sfn "../\$service" "/etc/dinit.d/boot.d/\$service"
            ;;
    esac
}

service_disable() {
    local service="\$1"
    case "\$INIT" in
        systemd) systemctl disable "\$service" || true ;;
        openrc) rc-update del "\$service" default || true ;;
        runit) rm -f "/etc/runit/runsvdir/default/\$service" ;;
        dinit) rm -f "/etc/dinit.d/boot.d/\$service" ;;
    esac
}

declare -A wanted_services=()
for service in "\${ENABLED_SERVICES[@]}"; do wanted_services["\$service"]=1; done

mapfile -t OLD_SERVICES < <(cat "\$SERVICE_STATE" 2>/dev/null | sort -u || true)
declare -A old_services=()
for service in "\${OLD_SERVICES[@]}"; do [[ -n "\$service" ]] && old_services["\$service"]=1; done

service_is_enabled() {
    local service="\$1"
    case "\$INIT" in
        systemd)
            systemctl is-enabled --quiet "\$service" 2>/dev/null
            ;;
        openrc)
            rc-update show default 2>/dev/null | grep -Eq "(^|[[:space:]])\${service}([[:space:]]|\$)"
            ;;
        runit)
            [[ -L "/etc/runit/runsvdir/default/\$service" ]]
            ;;
        dinit)
            [[ -L "/etc/dinit.d/boot.d/\$service" ]]
            ;;
    esac
}

for service in "\${!wanted_services[@]}"; do
    if [[ -z "\${old_services[\$service]+x}" ]] || ! service_is_enabled "\$service"; then
        echo -e "\${CYAN}[ENABLE]\${NC} \$service"
        service_enable "\$service"
    fi
done
for service in "\${!old_services[@]}"; do
    if [[ -z "\${wanted_services[\$service]+x}" ]]; then
        echo -e "\${CYAN}[DISABLE]\${NC} \$service"
        service_disable "\$service"
    fi
done

# =============================================================================
# User service enablement
# =============================================================================
# User services are never started by VPK. The configuration is prepared so the
# user's service manager will enable them on the next session/boot.
# =============================================================================

user_service_enable() {
    local user="\$1" service="\$2"
    local home uid
    home="\$(getent passwd "\$user" | cut -d: -f6)"
    uid="\$(id -u "\$user")"

    case "\$INIT" in
        systemd)
            mkdir -p "\$home/.config/systemd/user/default.target.wants"
            if [[ -e "/usr/lib/systemd/user/\$service.service" ]]; then
                ln -sfn "/usr/lib/systemd/user/\$service.service" \
                    "\$home/.config/systemd/user/default.target.wants/\$service.service"
            else
                echo -e "\${YELLOW}[WARN]\${NC} systemd user unit '\$service.service' not found for \$user."
            fi
            chown -R "\$user:\$user" "\$home/.config/systemd"
            ;;
        openrc)
            mkdir -p "\$home/.config/rc/runlevels/default"
            if [[ -e "/etc/user/init.d/\$service" ]]; then
                ln -sfn "/etc/user/init.d/\$service" "\$home/.config/rc/runlevels/default/\$service"
            else
                echo -e "\${YELLOW}[WARN]\${NC} OpenRC user service '\$service' not found for \$user."
            fi
            chown -R "\$user:\$user" "\$home/.config/rc"
            ;;
        runit)
            mkdir -p "\$home/.local/service"
            if [[ -d "/etc/runit/sv/\$service" ]]; then
                ln -sfn "/etc/runit/sv/\$service" "\$home/.local/service/\$service"
            else
                echo -e "\${YELLOW}[WARN]\${NC} runit service '\$service' not found for \$user."
            fi
            chown -R "\$user:\$user" "\$home/.local"
            ;;
        dinit)
            # dinit user services cannot be enabled from the installation
            # chroot with --offline: there is no boot service hierarchy for the
            # user's dinit session yet. Try the normal user manager only when
            # it is actually available. A failed enable is intentionally NOT
            # considered reconciled, so the next post-boot vpk sync retries.
            if command -v dinitctl >/dev/null 2>&1; then
                if ! runuser -u "\$user" -- env HOME="\$home" dinitctl --user enable "\$service"; then
                    echo -e "\${YELLOW}[WARN]\${NC} dinit user service '\$service' for '\$user' could not be enabled yet."
                    echo -e "\${YELLOW}[WARN]\${NC} This is expected during installation; run 'vpk --sync' after first boot."
                    return 1
                fi
            else
                echo -e "\${YELLOW}[WARN]\${NC} dinitctl not found; cannot enable user service '\$service'."
                return 1
            fi
            ;;
    esac
}

user_service_disable() {
    local user="\$1" service="\$2"
    local home
    home="\$(getent passwd "\$user" 2>/dev/null | cut -d: -f6 || true)"
    [[ -n "\$home" ]] || return 0

    case "\$INIT" in
        systemd) rm -f "\$home/.config/systemd/user/default.target.wants/\$service.service" ;;
        openrc) rm -f "\$home/.config/rc/runlevels/default/\$service" ;;
        runit) rm -f "\$home/.local/service/\$service" ;;
        dinit)
            if command -v dinitctl >/dev/null 2>&1; then
                runuser -u "\$user" -- env HOME="\$home" dinitctl --user --offline disable "\$service" || true
            fi
            ;;
    esac
}

mapfile -t OLD_USER_SERVICES < <(cat "\$USER_SERVICE_STATE" 2>/dev/null || true)
declare -A wanted_user_services=()
declare -A old_user_services=()

for user in "\${!USER_SERVICES[@]}"; do
    while IFS= read -r service; do
        [[ -n "\$service" ]] || continue
        wanted_user_services["\$user|\$service"]=1
    done < <(parse_list "\${USER_SERVICES[\$user]}")
done
for entry in "\${OLD_USER_SERVICES[@]}"; do
    [[ -n "\$entry" ]] && old_user_services["\$entry"]=1
done

declare -A reconciled_user_services=()
for entry in "\${!wanted_user_services[@]}"; do
    user="\${entry%%|*}"
    service="\${entry#*|}"

    if [[ -n "\${old_user_services[\$entry]+x}" ]]; then
        reconciled_user_services["\$entry"]=1
        continue
    fi

    echo -e "\${CYAN}[USER ENABLE]\${NC} \$service for \$user"
    if user_service_enable "\$user" "\$service"; then
        reconciled_user_services["\$entry"]=1
    fi
done
for entry in "\${!old_user_services[@]}"; do
    if [[ -z "\${wanted_user_services[\$entry]+x}" ]]; then
        user="\${entry%%|*}"
        service="\${entry#*|}"
        if id "\$user" &>/dev/null; then
            echo -e "\${CYAN}[USER DISABLE]\${NC} \$service for \$user"
            user_service_disable "\$user" "\$service"
        fi
    fi
done

for user in "\${USER_REMOVED[@]}"; do
    echo -e "\${CYAN}[USER]\${NC} Removing account \$user (home directory is preserved)"
    userdel "\$user"
done

# =============================================================================
# Save state only after successful reconciliation.
# =============================================================================
# Package state was already written above, immediately after successful package
# reconciliation. Do not overwrite it here with the old package-list format.
printf '%s\n' "\${!wanted_services[@]}" | sort > "\$SERVICE_STATE"
printf '%s\n' "\${!desired_user[@]}" | sort > "\$USER_STATE"
printf '%s\n' "\${!reconciled_user_services[@]}" | sort > "\$USER_SERVICE_STATE"

echo -e "\${GREEN}[OK]\${NC} VPK reconciliation complete."

VPK_EOF
    chmod +x /usr/bin/vpk
    info "Synchronizing declarative package state..."
    vpk sync
else
# =============================================================================

if [ "\${INIT_SYSTEM}" = "systemd" ]; then

    if [ "\${DESKTOP_ENV}" = "kde" ]; then
        pacman -S plasma ark konsole dolphin xdg-desktop-portal-kde wl-clipboard kitty fastfetch sddm networkmanager neovim nano sudo power-profiles-daemon --noconfirm
        systemctl enable NetworkManager
        systemctl enable sddm --force
        pacman -Rnsdd plasma-bigscreen --noconfirm

    elif [ "\${DESKTOP_ENV}" = "xfce" ]; then
        pacman -S xfce4 xfce4-whiskermenu-plugin ark xclip maim xfce4-pulseaudio-plugin kitty fastfetch sddm networkmanager neovim nano sudo power-profiles-daemon --noconfirm
        systemctl enable NetworkManager
        systemctl enable sddm --force

    else
        info "Skipping Desktop Environment installation."
        pacman -S networkmanager neovim nano sudo --noconfirm
        systemctl enable NetworkManager
    fi

else

    if [ "\${DESKTOP_ENV}" = "kde" ]; then
        DE_PKGS="plasma konsole dolphin"
        DESKTOP_PKGS="kitty ark xdg-desktop-portal-kde fastfetch wl-clipboard sddm sddm-\${INIT_SYSTEM} power-profiles-daemon power-profiles-daemon-\${INIT_SYSTEM} pipewire pipewire-\${INIT_SYSTEM} pipewire-pulse pipewire-pulse-\${INIT_SYSTEM} wireplumber wireplumber-\${INIT_SYSTEM}"

    elif [ "\${DESKTOP_ENV}" = "xfce" ]; then
        DE_PKGS="xorg-server xfce4 xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin"
        DESKTOP_PKGS="kitty ark fastfetch sddm xclip maim sddm-\${INIT_SYSTEM} power-profiles-daemon power-profiles-daemon-\${INIT_SYSTEM} pipewire pipewire-\${INIT_SYSTEM} pipewire-pulse pipewire-pulse-\${INIT_SYSTEM} wireplumber wireplumber-\${INIT_SYSTEM}"

    else
        DE_PKGS=""
        DESKTOP_PKGS=""
        info "Skipping Desktop Environment installation."
    fi

    pacman -S \
        \${DE_PKGS} \
        \${DESKTOP_PKGS} \
        turnstile turnstile-\${INIT_SYSTEM} \
        networkmanager networkmanager-\${INIT_SYSTEM} \
        dbus dbus-\${INIT_SYSTEM} \
        neovim nano sudo \
        --noconfirm

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


fi
# =============================================================================
# DRIVERS
# =============================================================================

if [ "\${DECLARATIVE_MODE}" = "yes" ]; then
    info "Drivers are declaratively managed by VPK."
else
# =============================================================================

info "Installing mesa drivers for intel, amd and nouveau..."
sudo pacman -S mesa lib32-mesa \
  vulkan-intel lib32-vulkan-intel \
  vulkan-radeon lib32-vulkan-radeon \
  vulkan-nouveau lib32-vulkan-nouveau \
  vulkan-swrast lib32-vulkan-swrast \
  libva intel-media-driver --noconfirm --needed


fi
# =============================================================================
# GRUB
# =============================================================================

info "Installing GRUB..."
if [ "\${DECLARATIVE_MODE}" = "yes" ]; then
    if [ "\${BOOT_MODE}" = "UEFI" ]; then
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
    else
        grub-install --recheck "\${GRUB_DISK}"
    fi
else
    if [ "\${BOOT_MODE}" = "UEFI" ]; then
        pacman -S --noconfirm grub efibootmgr
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
    else
        pacman -S --noconfirm grub
        grub-install --recheck "\${GRUB_DISK}"
    fi
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

    if [ "\${DECLARATIVE_MODE}" = "yes" ]; then
        cat >> /etc/visnux/visnux.conf <<EOF

[user:\${NEW_USER}]
groups = { wheel, audio, video, input }
shell = /usr/bin/fish
EOF
        info "Added '\${NEW_USER}' to /etc/visnux/visnux.conf."
        info "VPK now owns the declarative state of this user."
        vpk sync
    fi

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
