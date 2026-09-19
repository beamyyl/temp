#!/bin/bash
# =============================================================================
# YADAIS (Yet Another Declarative Artix Install Script)
# Supports: UEFI / BIOS + OpenRC / dinit
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
ask()   { echo -e "${CYAN}[INPUT]${NC} $*"; }

for cmd in basestrap fstabgen artix-chroot; do
    command -v "$cmd" &>/dev/null \
        || die "'$cmd' not found. Are you booted from the Artix live ISO?"
done

clear
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}=                    ARTIX INSTALLER                       =${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
info "This script will install Artix to /mnt."
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

info "============================================================"
info " BOOT MODE, INIT SYSTEM"
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

while true; do
    ask "Init system?"
    ask "  1) OpenRC"
    ask "  2) dinit"
    read -rp "  Choice [1/2]: " INIT_CHOICE
    case "$INIT_CHOICE" in
        1) INIT_SYSTEM="openrc"; break ;;
        2) INIT_SYSTEM="dinit"; break ;;
        *) warn "Invalid choice. Enter 1 or 2." ;;
    esac
done
echo ""
info "Selected: boot=$BOOT_MODE  init=$INIT_SYSTEM"
echo ""

info "============================================================"
info " SYSTEM CONFIGURATION"
info "============================================================"
echo ""

while true; do
    ask "Do you want to use an existing configuration, or manually edit a template before the installer?"
    ask "  1) Existing  (uses artix.conf sitting next to this script, unmodified)"
    ask "  2) Template  (open a starting manifest in an editor before continuing)"
    read -rp "  Choice [1/2]: " CONFIG_CHOICE
    case "$CONFIG_CHOICE" in
        1) CONFIG_MODE="existing"; break ;;
        2) CONFIG_MODE="template"; break ;;
        *) warn "Invalid choice. Enter 1 or 2." ;;
    esac
done
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDITOR_CHOICE=""
KERNEL_PKGS="linux linux-firmware sof-firmware base base-devel"

if [ "$CONFIG_MODE" = "existing" ]; then
    MANIFEST_SOURCE="$SCRIPT_DIR/artix.conf"
    [ -f "$MANIFEST_SOURCE" ] \
        || die "No artix.conf found next to this script at '$MANIFEST_SOURCE'. Place one there, or choose Template instead."
    sed -i -E "s/^[[:space:]]*init[[:space:]]*=.*/init = $INIT_SYSTEM/" "$MANIFEST_SOURCE"
    info "Using existing configuration: $MANIFEST_SOURCE"
else
    MANIFEST_SOURCE="/tmp/artix-template.conf"

    while true; do
        ask "Which editor would you like to use?"
        ask "  1) nano"
        ask "  2) vim"
        read -rp "  Choice [1/2]: " EDITOR_PICK
        case "$EDITOR_PICK" in
            1) EDITOR_CHOICE="nano"; break ;;
            2) EDITOR_CHOICE="vim"; break ;;
            *) warn "Invalid choice. Enter 1 or 2." ;;
        esac
    done
    echo ""

    info "Installing $EDITOR_CHOICE so you can edit the manifest..."
    pacman -Sy --noconfirm nano vim glibc
    
    BOOTMGR_PKGS="grub"
    BOOTMGR_CONFIG="boot_disk = \"$GRUB_DISK\""
    if [ "$BOOT_MODE" = "uefi" ]; then
        BOOTMGR_PKGS="grub efibootmgr"
        BOOTMGR_CONFIG="efi_dir = \"/boot/efi\""
    fi

    SERVICE_PKGS="dbus networkmanager cronie turnstile"
    ENABLED_SERVICES="dbus elogind NetworkManager cronie"
    if [ "$INIT_SYSTEM" = "openrc" ]; then
        ENABLED_SERVICES="$ENABLED_SERVICES turnstile"
    else
        ENABLED_SERVICES="$ENABLED_SERVICES turnstiled"
    fi

    cat > "$MANIFEST_SOURCE" <<EOF
# Artix's configuration file

[kernel]
pkgs = { $KERNEL_PKGS }

[bootmgr]
pkgs = { $BOOTMGR_PKGS }
$BOOTMGR_CONFIG

[desktop]
metapkgs = { }
pkgs = { }

[packages]
pkgs = { sudo neovim }
# blacklist = { }

[fonts]
pkgs = { ttf-iosevka-nerd ttf-adwaitamono-nerd }

[services]
# pkgs = { $SERVICE_PKGS pipewire wireplumber pipewire-pulse }
pkgs = { $SERVICE_PKGS }
enabled = { $ENABLED_SERVICES }

[drivers]
pkgs = { }
# Or all opensource drivers:
# pkgs = { vulkan-intel xf86-video-intel libva-intel-driver intel-media-driver lib32-libva-intel-driver lib32-vulkan-intel xf86-video-amdgpu vulkan-radeon amd-ucode lib32-vulkan-radeon lib32-mesa vulkan-nouveau lib32-vulkan-nouveau xf86-video-nouveau mesa intel-ucode  }

[sudo]
# wheel = allowed
# wheel = allowed no_sudo_password

[hostname]
hostname = artix

[timezone]
# timezone = Region/Capital

# User example
# [user:beamy]
# groups = { wheel audio video input }
# shell = /bin/bash
# [user-services]
# beamy = { pipewire wireplumber pipewire-pulse }

# Do NOT change the init line. If you wanna switch inits, clean reinstall is the safest way to do so.
init = $INIT_SYSTEM
EOF

    info "Opening $MANIFEST_SOURCE in $EDITOR_CHOICE. Save and quit when you're done."
    read -rp "  Press ENTER to open the editor..."
    "$EDITOR_CHOICE" "$MANIFEST_SOURCE"
fi

KERNEL_PKGS="$(awk '/^\[kernel\]/{f=1; next} /^\[/{f=0} f' "$MANIFEST_SOURCE" | grep -m1 'pkgs' | sed -E 's/.*\{(.*)\}.*/\1/' | xargs)"
if [ -z "$KERNEL_PKGS" ]; then
    warn "No packages found in [kernel] — falling back to: linux linux-firmware sof-firmware base base-devel"
    KERNEL_PKGS="linux linux-firmware sof-firmware base base-devel"
fi

NEW_HOSTNAME="$(awk '/^\[hostname\]/{f=1; next} /^\[/{f=0} f && /^[[:space:]]*hostname[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/, ""); print; exit}' "$MANIFEST_SOURCE")"
if [ -z "$NEW_HOSTNAME" ]; then
    NEW_HOSTNAME="artix"
fi

info "Configuration summary:"
echo "   Boot mode : $BOOT_MODE"
echo "   Init      : $INIT_SYSTEM"
echo "   Hostname  : $NEW_HOSTNAME"
echo "   Config    : $CONFIG_MODE"
echo "   Kernel    : $KERNEL_PKGS"
echo ""
read -rp "  Press ENTER to continue..."
echo ""

info "============================================================"
info " BASE INSTALL"
info "============================================================"
echo ""

info "Installing $KERNEL_PKGS and $INIT_SYSTEM..."
basestrap /mnt $KERNEL_PKGS "${INIT_SYSTEM}" "elogind-${INIT_SYSTEM}"

info "Copying the manifest into the target..."
mkdir -p /mnt/etc/artix
cp "$MANIFEST_SOURCE" /mnt/etc/artix/artix.conf

info "============================================================"
info " FSTAB"
info "============================================================"

info "Generating /etc/fstab..."
fstabgen -U /mnt > /mnt/etc/fstab
info "fstab contents:"
cat /mnt/etc/fstab
echo ""

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
CONFIG_MODE="${CONFIG_MODE}"

hwclock --systohc
pacman -Sy --noconfirm

echo "\${NEW_HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${NEW_HOSTNAME}.localdomain \${NEW_HOSTNAME}
EOF

info "Enabling multilib support..."
pacman -S --noconfirm artix-archlinux-support
pacman-key --populate archlinux

if ! grep -q '^\[multilib\]\$' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'MULTILIB_EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
MULTILIB_EOF
fi

# Generate the locales
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

info "Installing apk..."
cat > /usr/bin/apk <<'APK_EOF'
#!/bin/bash
# =============================================================================
# apk - Artix Declarative Package Sync Tool
# usage: apk [sync | check] [--path /path/to/manifest]
# =============================================================================

set -euo pipefail

MANIFEST="/etc/artix/artix.conf"
ACTION="sync"
REINSTALL_BOOTLOADER=0
STATE_DIR="/var/lib/apk"
PACKAGE_STATE="\$STATE_DIR/packages.state"
SERVICE_STATE="\$STATE_DIR/services.state"
BOOTMGR_STATE="\$STATE_DIR/bootmgr.state"
USER_STATE="\$STATE_DIR/users.state"
USER_SERVICE_STATE="\$STATE_DIR/user-services.state"
KERNEL_STATE="\$STATE_DIR/kernel.state"
BLACKLIST_STATE="\$STATE_DIR/blacklist.state"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

if [[ "\$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "\$0" "\$@"
    fi
    echo -e "\${RED}[FAIL]\${NC} apk must run as root."
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
            echo "Usage: apk [sync|check] [--path /path/to/manifest] [--reinstall-bootloader]"
            echo "  sync   Reconcile the manifest and run pacman -Syu first (default)."
            echo "  check  Check declarative state without changing anything."
            exit 0
            ;;
        --sync|-s)
            echo -e "\${RED}[FAIL]\${NC} --sync is no longer an APK command. Use: apk sync"
            exit 1
            ;;
        --reinstall-bootloader)
            REINSTALL_BOOTLOADER=1
            shift
            ;;
        *) echo -e "\${RED}[FAIL]\${NC} Unknown option: \$1"; exit 1 ;;
    esac
done

[[ -f "\$MANIFEST" ]] || { echo -e "\${RED}[FAIL]\${NC} Manifest '\$MANIFEST' not found!"; exit 1; }

mkdir -p "\$STATE_DIR"

echo -e "\${CYAN}[APK]\${NC} Reading manifest: \$MANIFEST"

if [[ "\$ACTION" == "sync" ]]; then
    echo -e "\${CYAN}[UPGRADE]\${NC} Running pacman -Syu..."
    pacman -Syu --noconfirm
fi

INIT="openrc"
declare -a DECLARED_PKGS=()
declare -a META_PKGS=()
declare -a SERVICE_PKGS=()
declare -a ENABLED_SERVICES=()
declare -a KERNEL_PKGS_LIST=()
declare -a BLACKLIST_PKGS=()
declare -a PACKAGES_SECTION_PKGS=()
declare -A USERS=()
declare -A USER_GROUPS=()
declare -A USER_SHELLS=()
declare -A USER_SERVICES=()
WHEEL_SUDO_MODE=""
DECLARED_HOSTNAME=""
DECLARED_TIMEZONE=""
BOOTMGR_PKGS=()
EFI_DIR=""
BOOT_DISK=""

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

    if [[ "\$SECTION" == "sudo" && "\$line" =~ ^wheel[[:space:]]*=[[:space:]]*(.+)\$ ]]; then
        WHEEL_SUDO_MODE="\$(trim "\${BASH_REMATCH[1]}")"
        continue
    fi
        if [[ "\$SECTION" == "bootmgr" && "\$line" =~ ^efi_dir[[:space:]]*=[[:space:]]*(.*)\$ ]]; then
        EFI_DIR="\${BASH_REMATCH[1]}"
        EFI_DIR="\${EFI_DIR%\"}"
        EFI_DIR="\${EFI_DIR#\"}"
        continue
    fi

    if [[ "\$SECTION" == "bootmgr" && "\$line" =~ ^boot_disk[[:space:]]*=[[:space:]]*(.*)\$ ]]; then
        BOOT_DISK="\${BASH_REMATCH[1]}"
        BOOT_DISK="\${BOOT_DISK%\"}"
        BOOT_DISK="\${BOOT_DISK#\"}"
        continue
    fi

    if [[ "\$SECTION" == "hostname" && "\$line" =~ ^hostname[[:space:]]*=[[:space:]]*(.+)\$ ]]; then
        DECLARED_HOSTNAME="\$(trim "\${BASH_REMATCH[1]}")"
        continue
    fi

    if [[ "\$SECTION" == "timezone" && "\$line" =~ ^timezone[[:space:]]*=[[:space:]]*(.+)\$ ]]; then
        DECLARED_TIMEZONE="\$(trim "\${BASH_REMATCH[1]}")"
        continue
    fi

    if [[ "\$line" =~ ^blacklist[[:space:]]*=[[:space:]]*\{(.*)\}\$ ]]; then
        [[ "\$SECTION" == "packages" ]] || { echo -e "\${RED}[FAIL]\${NC} blacklist is only valid in [packages]."; exit 1; }
        while IFS= read -r pkg; do [[ -n "\$pkg" ]] && BLACKLIST_PKGS+=("\$pkg"); done < <(parse_list "\${BASH_REMATCH[1]}")
        continue
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
            if [[ "\$SECTION" == "services" ]]; then
                SERVICE_PKGS+=("\$pkg")
            else
                if [[ "\$SECTION" == "kernel" ]]; then
                    KERNEL_PKGS_LIST+=("\$pkg")
                fi
                if [[ "\$SECTION" == "packages" ]]; then
                    PACKAGES_SECTION_PKGS+=("\$pkg")
                fi
                if [[ "\$SECTION" == "bootmgr" ]]; then
                    BOOTMGR_PKGS+=("\$pkg")
                fi
                DECLARED_PKGS+=("\$pkg")
            fi
        done < <(parse_list "\${BASH_REMATCH[1]}")
        continue
    fi

    if [[ "\$SECTION" == "services" && "\$line" =~ ^enabled[[:space:]]*=[[:space:]]*\{(.*)\}\$ ]]; then
        while IFS= read -r service; do
            [[ -n "\$service" ]] && ENABLED_SERVICES+=("\$service")
        done < <(parse_list "\${BASH_REMATCH[1]}")
    fi
done < "\$MANIFEST"
CURRENT_BLACKLIST_SORTED="\$(printf '%s\n' "\${BLACKLIST_PKGS[@]}" | sort)"
PREVIOUS_BLACKLIST_SORTED=""
if [[ -f "\$BLACKLIST_STATE" ]]; then
    PREVIOUS_BLACKLIST_SORTED="\$(sort "\$BLACKLIST_STATE")"
fi
BLACKLIST_CHANGED=0
if [[ "\$CURRENT_BLACKLIST_SORTED" != "\$PREVIOUS_BLACKLIST_SORTED" ]]; then
    BLACKLIST_CHANGED=1
fi
case "\$INIT" in
    openrc|dinit) ;;
    *) echo -e "\${RED}[FAIL]\${NC} Invalid init '\$INIT'."; exit 1 ;;
esac

if [[ -n "\$EFI_DIR" && -n "\$BOOT_DISK" ]] || [[ -z "\$EFI_DIR" && -z "\$BOOT_DISK" ]]; then
    echo -e "\${RED}[FAIL]\${NC} [bootmgr] must contain either efi_dir or boot_disk, but not both."
    exit 1
fi

CURRENT_BOOTMGR_STATE=""
BOOTMGR_PKGS_SORTED="\$(printf '%s\n' "\${BOOTMGR_PKGS[@]}" | sort)"
if [[ -n "\$EFI_DIR" ]]; then
    CURRENT_BOOTMGR_STATE="pkgs=\$BOOTMGR_PKGS_SORTED|efi_dir=\$EFI_DIR"
else
    CURRENT_BOOTMGR_STATE="pkgs=\$BOOTMGR_PKGS_SORTED|boot_disk=\$BOOT_DISK"
fi

PREVIOUS_BOOTMGR_STATE=""
if [[ -f "\$BOOTMGR_STATE" ]]; then
    PREVIOUS_BOOTMGR_STATE="\$(cat "\$BOOTMGR_STATE")"
fi

BOOTMGR_CHANGED=0
if [[ "\$CURRENT_BOOTMGR_STATE" != "\$PREVIOUS_BOOTMGR_STATE" ]]; then
    BOOTMGR_CHANGED=1
fi

install_grub() {
    if [[ -n "\$EFI_DIR" ]]; then
        echo -e "\${CYAN}[GRUB]\${NC} Installing GRUB for UEFI..."
        grub-install --efi-directory="\$EFI_DIR"
    elif [[ -n "\$BOOT_DISK" ]]; then
        echo -e "\${CYAN}[GRUB]\${NC} Installing GRUB for BIOS..."
        grub-install --recheck "\$BOOT_DISK"
    else
        echo -e "\${RED}[FAIL]\${NC} GRUB requires either efi_dir or boot_disk."
        exit 1
    fi

    echo -e "\${CYAN}[GRUB]\${NC} Generating grub.cfg..."
    grub-mkconfig -o /boot/grub/grub.cfg
}

if [[ "\$BLACKLIST_CHANGED" -eq 1 ]]; then
    for bpkg in "\${BLACKLIST_PKGS[@]}"; do
        for ppkg in "\${PACKAGES_SECTION_PKGS[@]}"; do
            if [[ "\$bpkg" == "\$ppkg" ]]; then
                echo -e "\${YELLOW}[WARN]\${NC} '\$bpkg' is declared in [packages] pkgs AND blacklist — blacklist wins, it will not be installed/kept."
            fi
        done
    done
fi
is_package() {
    pacman -Qq "\$1" &>/dev/null
}
is_blacklisted() {
    local pkg="\$1"
    for bpkg in "\${BLACKLIST_PKGS[@]}"; do
        [[ "\$pkg" == "\$bpkg" ]] && return 0
    done
    return 1
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
    add_package_target "\$pkg-\$INIT"
done

if [[ \${#invalid_targets[@]} -gt 0 ]]; then
    echo -e "\${RED}[FAIL]\${NC} Unknown package/group target(s):"
    printf '  ! %s\n' "\${invalid_targets[@]}"
    exit 1
fi

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
            if is_blacklisted "\$member"; then
                continue
            fi
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
        current_members="\${desired_group_members[\$target]}"
        while IFS= read -r member; do
            [[ -n "\$member" ]] || continue
            if ! grep -qxF "\$member" <<< "\$current_members" && is_package "\$member"; then
                REMOVED_PACKAGES+=("\$member")
            fi
        done < <(tr ' ' '\n' <<< "\$members")
    fi
done

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

if [[ \${#BLACKLIST_PKGS[@]} -gt 0 ]]; then
    declare -a FILTERED_MISSING_PACKAGES=()
    for pkg in "\${MISSING_PACKAGES[@]}"; do
        blacklisted=0
        for bpkg in "\${BLACKLIST_PKGS[@]}"; do
            [[ "\$pkg" == "\$bpkg" ]] && { blacklisted=1; break; }
        done
        [[ \$blacklisted -eq 0 ]] && FILTERED_MISSING_PACKAGES+=("\$pkg")
    done
    MISSING_PACKAGES=("\${FILTERED_MISSING_PACKAGES[@]}")

    for bpkg in "\${BLACKLIST_PKGS[@]}"; do
        [[ -n "\$bpkg" ]] || continue
        if is_package "\$bpkg"; then
            already=0
            for rpkg in "\${REMOVED_PACKAGES[@]}"; do [[ "\$rpkg" == "\$bpkg" ]] && { already=1; break; }; done
            [[ \$already -eq 0 ]] && REMOVED_PACKAGES+=("\$bpkg")
        fi
    done

    if [[ "\$BLACKLIST_CHANGED" -eq 1 ]]; then
        echo -e "\${YELLOW}[BLACKLIST]\${NC} Forcefully excluded: \${BLACKLIST_PKGS[*]}"
    fi
fi

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
    BOOTLOADER_REINSTALLED=0
    if [[ \${#MISSING_PACKAGES[@]} -gt 0 ]]; then
        echo -e "\${CYAN}[SYNC]\${NC} Installing declared package/group members..."
        pacman -S --needed --noconfirm "\${MISSING_PACKAGES[@]}"
    fi

    if [[ \${#REMOVED_PACKAGES[@]} -gt 0 ]]; then
        echo -e "\${CYAN}[SYNC]\${NC} Removing packages no longer declared..."
        pacman -Rns --noconfirm "\${REMOVED_PACKAGES[@]}"
    fi

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

    if [[ "\$BOOTMGR_CHANGED" -eq 1 || "\$REINSTALL_BOOTLOADER" -eq 1 ]]; then
        if [[ "\$BOOTMGR_CHANGED" -eq 1 ]]; then
            echo -e "\${CYAN}[GRUB]\${NC} [bootmgr] changed — reinstalling bootloader"
        else
            echo -e "\${CYAN}[GRUB]\${NC} Reinstalling bootloader on request"
        fi
        install_grub
        BOOTLOADER_REINSTALLED=1
    fi

    printf '%s\n' "\$CURRENT_BOOTMGR_STATE" > "\$BOOTMGR_STATE"

    CURRENT_KERNEL_SORTED="\$(printf '%s\n' "\${KERNEL_PKGS_LIST[@]}" | sort)"
    PREVIOUS_KERNEL_SORTED=""
    [[ -f "\$KERNEL_STATE" ]] && PREVIOUS_KERNEL_SORTED="\$(sort "\$KERNEL_STATE")"
    if [[ "\$CURRENT_KERNEL_SORTED" != "\$PREVIOUS_KERNEL_SORTED" && "\$BOOTLOADER_REINSTALLED" -eq 0 ]]; then
        if command -v grub-mkconfig &>/dev/null && [[ -d /boot/grub ]]; then
            echo -e "\${CYAN}[GRUB]\${NC} [kernel] changed — regenerating grub.cfg"
            grub-mkconfig -o /boot/grub/grub.cfg
        fi
    fi
    printf '%s\n' "\${KERNEL_PKGS_LIST[@]}" | sort > "\$KERNEL_STATE"
fi

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
    home="\$(getent passwd "\$user" | cut -d: -f6)"
    [[ -n "\$home" && -d "\$home" ]] && chown -R "\$user:\$user" "\$home"
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

service_enable() {
    local service="\$1"
    case "\$INIT" in
        openrc)
            rc-update add "\$service" default
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
        openrc) rc-update del "\$service" default || true ;;
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
        openrc)
            rc-update show default 2>/dev/null | grep -Eq "(^|[[:space:]])\${service}([[:space:]]|\$)"
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

user_service_enable() {
    local user="\$1" service="\$2"
    local home uid
    home="\$(getent passwd "\$user" | cut -d: -f6)"
    uid="\$(id -u "\$user")"

    case "\$INIT" in
        openrc)
            mkdir -p "\$home/.config/rc/runlevels/default"
            if [[ -e "/etc/user/init.d/\$service" ]]; then
                ln -sfn "/etc/user/init.d/\$service" "\$home/.config/rc/runlevels/default/\$service"
            else
                echo -e "\${YELLOW}[WARN]\${NC} OpenRC user service '\$service' not found for \$user."
            fi
            chown -R "\$user:\$user" "\$home/.config"
            ;;
        dinit)
            local user_dinit_dir="\$home/.config/dinit.d"
            mkdir -p "\$user_dinit_dir/boot.d"

            local src=""
            if [[ -e "/etc/dinit.d/user/\$service" ]]; then
                src="/etc/dinit.d/user/\$service"
            elif [[ -e "/usr/lib/dinit.d/user/\$service" ]]; then
                src="/usr/lib/dinit.d/user/\$service"
            elif [[ -e "\$user_dinit_dir/\$service" ]]; then
                src="\$user_dinit_dir/\$service"
            else
                echo -e "\${YELLOW}[WARN]\${NC} dinit user service '\$service' not found for \$user."
                return 1
            fi

            ln -sfn "\$src" "\$user_dinit_dir/boot.d/\$service"
            chown -R "\$user:\$user" "\$home/.config"
            ;;
    esac
}

user_service_disable() {
    local user="\$1" service="\$2"
    local home
    home="\$(getent passwd "\$user" 2>/dev/null | cut -d: -f6 || true)"
    [[ -n "\$home" ]] || return 0

    case "\$INIT" in
        openrc) rm -f "\$home/.config/rc/runlevels/default/\$service" ;;
        dinit) rm -f "\$home/.config/dinit.d/boot.d/\$service" ;;
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

if [[ "\$ACTION" == "sync" ]]; then
    mkdir -p /etc/sudoers.d
    if [[ -n "\$WHEEL_SUDO_MODE" ]]; then
        expected_sudoers=""
        if [[ "\$WHEEL_SUDO_MODE" == *no_sudo_password* ]]; then
            expected_sudoers='%wheel ALL=(ALL:ALL) NOPASSWD: ALL'
        elif [[ "\$WHEEL_SUDO_MODE" == allowed* ]]; then
            expected_sudoers='%wheel ALL=(ALL:ALL) ALL'
        else
            echo -e "\${YELLOW}[WARN]\${NC} Unknown sudo wheel mode '\$WHEEL_SUDO_MODE' in manifest, skipping."
        fi
        if [[ -n "\$expected_sudoers" ]]; then
            sudoers_changed=0
            if [[ ! -f /etc/sudoers.d/wheel ]]; then
                sudoers_changed=1
            elif ! printf '%s\n' "\$expected_sudoers" | cmp -s - /etc/sudoers.d/wheel; then
                sudoers_changed=1
            elif [[ "\$(stat -c '%a' /etc/sudoers.d/wheel)" != "440" ]]; then
                sudoers_changed=1
            fi
            if [[ "\$sudoers_changed" -eq 1 ]]; then
                if [[ "\$WHEEL_SUDO_MODE" == *no_sudo_password* ]]; then
                    echo -e "\${CYAN}[SUDO]\${NC} Granting wheel passwordless sudo"
                else
                    echo -e "\${CYAN}[SUDO]\${NC} Granting wheel sudo"
                fi
                printf '%s\n' "\$expected_sudoers" > /etc/sudoers.d/wheel
                chmod 440 /etc/sudoers.d/wheel
            fi
        fi
    elif [[ -f /etc/sudoers.d/wheel ]]; then
        echo -e "\${CYAN}[SUDO]\${NC} Removing wheel sudo access (not declared in manifest)"
        rm -f /etc/sudoers.d/wheel
    fi
fi

# Hostname

if [[ "\$ACTION" == "sync" && -n "\$DECLARED_HOSTNAME" ]]; then
    CURRENT_HOSTNAME="\$(cat /etc/hostname 2>/dev/null || true)"
    if [[ "\$CURRENT_HOSTNAME" != "\$DECLARED_HOSTNAME" ]]; then
        echo -e "\${CYAN}[HOSTNAME]\${NC} Setting hostname to \$DECLARED_HOSTNAME"
        echo "\$DECLARED_HOSTNAME" > /etc/hostname
        if [[ -f /etc/hosts ]] && grep -q '^127\.0\.1\.1' /etc/hosts; then
            sed -i "s/^127\.0\.1\.1.*/127.0.1.1   \${DECLARED_HOSTNAME}.localdomain \${DECLARED_HOSTNAME}/" /etc/hosts
        else
            echo "127.0.1.1   \${DECLARED_HOSTNAME}.localdomain \${DECLARED_HOSTNAME}" >> /etc/hosts
        fi
    fi
fi

if [[ "\$ACTION" == "sync" && -n "\$DECLARED_TIMEZONE" ]]; then
    ZONEINFO_PATH="/usr/share/zoneinfo/\$DECLARED_TIMEZONE"
    if [[ -e "\$ZONEINFO_PATH" ]]; then
        CURRENT_TIMEZONE="\$(readlink -f /etc/localtime 2>/dev/null || true)"
        EXPECTED_TIMEZONE="\$(readlink -f "\$ZONEINFO_PATH")"
        if [[ "\$CURRENT_TIMEZONE" != "\$EXPECTED_TIMEZONE" ]]; then
            echo -e "\${CYAN}[TIMEZONE]\${NC} Setting timezone to \$DECLARED_TIMEZONE"
            ln -sf "\$ZONEINFO_PATH" /etc/localtime
        fi
    else
        echo -e "\${YELLOW}[WARN]\${NC} '\$DECLARED_TIMEZONE' not found under /usr/share/zoneinfo, skipping."
    fi
fi

printf '%s\n' "\${!wanted_services[@]}" | sort > "\$SERVICE_STATE"
printf '%s\n' "\${!desired_user[@]}" | sort > "\$USER_STATE"
printf '%s\n' "\${!reconciled_user_services[@]}" | sort > "\$USER_SERVICE_STATE"
printf '%s\n' "\${BLACKLIST_PKGS[@]}" | sort > "\$BLACKLIST_STATE"

echo -e "\${GREEN}[OK]\${NC} APK reconciliation complete."
APK_EOF
chmod +x /usr/bin/apk

mkdir -p /etc/artix /var/lib/apk
info "Using the manifest at /etc/artix/artix.conf."

info "Synchronizing declarative package state..."
apk sync
sed -i 's/PRETTY_NAME="Artix Linux"/PRETTY_NAME="Artix Linux (declarative)"/' /etc/os-release

echo ""
info "============================================================"
info " Set the ROOT password:"
info "============================================================"
while ! passwd; do
    warn "Password change failed or passwords did not match. Please try again."
done

echo ""
info "============================================================"
info " Installation complete!"
info "============================================================"
info " Exit the chroot and reboot:"
info ""
info "   exit"
info "   umount -R /mnt"
info "   reboot"
info "============================================================"
CHROOT_EOF

chmod +x /mnt/root/chroot-install.sh
info "In-chroot script written."
echo ""

info "============================================================"
info " ENTERING CHROOT"
info "============================================================"
echo ""

artix-chroot /mnt /bin/bash /root/chroot-install.sh

info "============================================================"
info " CLEANUP"
info "============================================================"

rm -f /mnt/root/chroot-install.sh

info "Unmounting filesystems..."
umount -R /mnt 2>/dev/null

echo ""
info "============================================================"
info " All done! Remove your installation media and reboot."
info "============================================================"
