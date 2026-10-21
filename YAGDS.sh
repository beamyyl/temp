#!/usr/bin/env bash
# =============================================================================
# YAGDS — Yet Another Gentoo Declarative System
# Gentoo counterpart to YADAIS. Installer: UEFI/BIOS; OpenRC/systemd/dinit.
# Runtime manager: apk sync | apk sync --upgrade | apk check
# =============================================================================
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info(){ echo -e "${GREEN}[INFO]${NC}  $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC}  $*"; }
die(){ echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }
ask(){ echo -e "${CYAN}[INPUT]${NC} $*"; }

for cmd in arch-chroot genfstab links; do command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found. Run this from a live environment with arch-chroot, genfstab and links installed."; done

clear || true
printf '\n\033[0;36m============================================================\n=              GENTOO DECLARATIVE INSTALLER                =\n============================================================\033[0m\n\n'
info 'This script installs Gentoo to /mnt/gentoo.'
warn 'Partitions must already be formatted and mounted. This script does not format disks.'
echo 'UEFI example: mount ROOT /mnt/gentoo; mount EFI /mnt/gentoo/efi --mkdir'
echo 'BIOS example: mount ROOT /mnt/gentoo (BIOS/GPT requires a 1 MiB BIOS boot partition)'
read -rp 'Press ENTER when ready...'
mountpoint -q /mnt/gentoo || die '/mnt/gentoo is not mounted.'

ask 'Boot mode: 1) UEFI  2) BIOS'; read -rp 'Choice [1/2]: ' BOOT_CHOICE
case "$BOOT_CHOICE" in 1) BOOT_MODE=uefi;; 2) BOOT_MODE=bios;; *) die 'Invalid boot mode.';; esac
if [[ $BOOT_MODE == uefi ]]; then mountpoint -q /mnt/gentoo/efi || die '/mnt/gentoo/efi is not mounted.'; else
  read -rp 'Whole disk for GRUB (e.g. /dev/sda): ' GRUB_DISK
  [[ -b $GRUB_DISK ]] || die "Not a block device: $GRUB_DISK"
fi
ask 'Init system: 1) OpenRC  2) systemd  3) dinit (requires guru overlay)'; read -rp 'Choice [1/2/3]: ' INIT_CHOICE
case "$INIT_CHOICE" in 1) INIT_SYSTEM=openrc;; 2) INIT_SYSTEM=systemd;; 3) INIT_SYSTEM=dinit;; *) die 'Invalid init choice.';; esac
read -rp 'Hostname [gentoo]: ' NEW_HOSTNAME; NEW_HOSTNAME=${NEW_HOSTNAME:-gentoo}
read -rp 'Locale [en_US.UTF-8]: ' LOCALE; LOCALE=${LOCALE:-en_US.UTF-8}
ask 'Open the Gentoo stage3 download page now; download the matching amd64 desktop stage3 into /mnt/gentoo.'
read -rp 'Press ENTER to open Links...'; (cd /mnt/gentoo && links 'https://www.gentoo.org/downloads/amd64/#stage-tarballs')
TARBALL=$(find /mnt/gentoo -maxdepth 1 -type f -name 'stage3-amd64-*.tar.xz' -print -quit)
[[ -n $TARBALL ]] || die 'No stage3-amd64-*.tar.xz found in /mnt/gentoo.'
info "Extracting $(basename "$TARBALL")..."
tar xpf "$TARBALL" --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
rm -f "$TARBALL"

mkdir -p /mnt/gentoo/etc/portage/package.use /mnt/gentoo/etc/portage/package.accept_keywords /mnt/gentoo/etc/portage/package.mask /mnt/gentoo/etc/portage/binrepos.conf
cat > /mnt/gentoo/etc/portage/make.conf <<'MAKECONF'
# Managed by apk from /etc/gentoo/gentoo.conf. This file is declarative.
COMMON_FLAGS="-O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
MAKEOPTS="-j11 -l10"
#USE="X wayland networkmanager sound-server pipewire screencast pulseaudio bluetooth -systemd"
FEATURES="parallel-install parallel-fetch -merge-wait"
ACCEPT_LICENSE="*"
LC_MESSAGES=C.UTF-8
GRUB_PLATFORMS="efi-64"
MAKECONF
cat > /mnt/gentoo/etc/portage/package.use/00installkernel <<'EOF_USE'
sys-kernel/installkernel grub dracut
EOF_USE
cat > /mnt/gentoo/etc/portage/package.use/00networkmanager <<'EOF_USE'
net-misc/networkmanager wifi
net-wireless/wpa_supplicant dbus
EOF_USE
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/resolv.conf
genfstab -U /mnt/gentoo > /mnt/gentoo/etc/fstab
mkdir -p /mnt/gentoo/etc/portage/repos.conf
cat > /mnt/gentoo/etc/portage/repos.conf/gentoo.conf <<'EOF_REPO'
[DEFAULT]
main-repo = gentoo

[gentoo]
location = /var/db/repos/gentoo
sync-type = git
sync-uri = https://github.com/gentoo/gentoo.git
auto-sync = yes
EOF_REPO
printf '%s\n' "$NEW_HOSTNAME" > /mnt/gentoo/etc/hostname
printf 'hostname="%s"\n' "$NEW_HOSTNAME" > /mnt/gentoo/etc/conf.d/hostname
cat > /mnt/gentoo/etc/hosts <<EOF_HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${NEW_HOSTNAME}.localdomain ${NEW_HOSTNAME}
EOF_HOSTS
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys; mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev; mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run; mount --make-slave /mnt/gentoo/run

cat > /mnt/gentoo/etc/gentoo.conf <<'MANIFEST'
# Gentoo declarative system manifest. Edit after installation: /etc/gentoo/gentoo.conf

[kernel]
pkgs = { sys-kernel/gentoo-kernel-bin sys-kernel/linux-firmware sys-firmware/sof-firmware }

[bootmgr]
pkgs = { sys-boot/grub }

[desktop]
metapkgs = { }
pkgs = { }

[packages]
pkgs = { app-portage/gentoolkit app-admin/sudo app-editors/neovim }
# blacklist = { }

[fonts]
pkgs = { }

[services]
pkgs = { net-misc/networkmanager sys-process/cronie }
enabled = { NetworkManager cronie }

[make.conf]
# Special directive, consumed by apk and not copied to make.conf:
enable-binpkgs = false
COMMON_FLAGS="-O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
MAKEOPTS="-j11 -l10"
FEATURES="parallel-install parallel-fetch -merge-wait"
#USE="X wayland networkmanager sound-server pipewire screencast pulseaudio bluetooth -systemd"
ACCEPT_LICENSE="*"
LC_MESSAGES=C.UTF-8
GRUB_PLATFORMS="efi-64"

[package.use]
sys-kernel/installkernel grub dracut
net-misc/networkmanager wifi
net-wireless/wpa_supplicant dbus

[package.accept_keywords]

[package.mask]

[eselect-repos]
enabled = false
repos = { guru gentoo-zt }
unmask = { '*/*::guru ~amd64' '*/*::gentoo-zt **' }

[hostname]
hostname = __HOSTNAME__

[timezone]
# timezone = Europe/Bucharest

# User example:
# [user:beamy]
# groups = { wheel audio video }
# shell = /bin/bash

init = __INIT_SYSTEM__
MANIFEST
sed -i "s|__HOSTNAME__|$NEW_HOSTNAME|g; s|__INIT_SYSTEM__|$INIT_SYSTEM|g" /mnt/gentoo/etc/gentoo.conf
if [[ $INIT_SYSTEM == dinit ]]; then
  sed -i 's/^enabled = false$/enabled = true/' /mnt/gentoo/etc/gentoo.conf
fi

cat > /mnt/gentoo/root/chroot-install.sh <<'CHROOT'
#!/usr/bin/env bash
set -Eeuo pipefail
BOOT_MODE='__BOOT_MODE__'; INIT_SYSTEM='__INIT_SYSTEM__'; GRUB_DISK='__GRUB_DISK__'; NEW_HOSTNAME='__NEW_HOSTNAME__'; LOCALE='__LOCALE__'
info(){ echo -e "\033[0;32m[CHROOT]\033[0m $*"; }; warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }; die(){ echo -e "\033[0;31m[FAIL]\033[0m $*" >&2; exit 1; }
info 'Synchronizing Gentoo repository and updating metadata...'
getuto -q 2>/dev/null || true
emerge-webrsync -q || emaint sync -a
info 'Selecting init profile...'
eselect profile list
if [[ $INIT_SYSTEM == systemd ]]; then
  PROFILE_NUM=$(eselect profile list | grep -E 'desktop.*systemd' | grep -vE 'gnome|kde' | head -n1 | awk -F'[][]' '{print $2}')
elif [[ $INIT_SYSTEM == openrc ]]; then
  PROFILE_NUM=$(eselect profile list | grep -E 'desktop' | grep -vE 'systemd|gnome|kde' | head -n1 | awk -F'[][]' '{print $2}')
else
  PROFILE_NUM=$(eselect profile list | grep -E 'desktop' | grep -vE 'systemd|gnome|kde' | head -n1 | awk -F'[][]' '{print $2}')
  warn 'dinit is an overlay-based init; the selected base profile is OpenRC until migration completes.'
fi
[[ -n $PROFILE_NUM ]] || die 'Could not find an appropriate desktop profile; select it manually and rerun this step.'
eselect profile set "$PROFILE_NUM"
eselect profile show

# CPU flags: preserve YAGIS behavior.
emerge -q --ask=n app-portage/cpuid2cpuflags
mkdir -p /etc/portage/package.use
printf '*/* %s\n' "$(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
info 'CPU flags configured:'; cat /etc/portage/package.use/00cpu-flags

mkdir -p /etc/portage/binrepos.conf
cat > /etc/portage/binrepos.conf/gentoo.conf <<'BINREPOS'
[gentoo]
priority = 9998
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
location = /var/cache/binhost/gentoo
BINREPOS
# Initial binary config follows manifest directive; apk manages this file later.

# Locale setup.
grep -qE "^${LOCALE//./\.} UTF-8$" /etc/locale.gen || echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen || true
LOCALE_NUM=$(eselect locale list | grep -F "$LOCALE" | head -n1 | awk -F'[][]' '{print $2}' || true)
[[ -z $LOCALE_NUM ]] || eselect locale set "$LOCALE_NUM"
env-update && source /etc/profile || true

# Essential system packages. Declarative reconciliation installs the rest.
emerge -q --ask=n sys-kernel/installkernel sys-boot/grub app-admin/sudo app-portage/gentoolkit net-misc/networkmanager app-admin/syslog-ng sys-process/cronie
if [[ $INIT_SYSTEM == openrc ]]; then
  rc-update add NetworkManager default || true; rc-update add syslog-ng default || true; rc-update add cronie default || true
elif [[ $INIT_SYSTEM == systemd ]]; then
  emerge -q --ask=n sys-apps/systemd
  systemctl enable NetworkManager || true
else
  warn 'dinit requested: installing dinit from guru is handled by apk after the repo is enabled; OpenRC remains installed as a safe fallback.'
fi

if [[ $BOOT_MODE == uefi ]]; then
  emerge -q --ask=n sys-boot/efibootmgr || true
  grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo
else
  grub-install --recheck "$GRUB_DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg

mkdir -p /etc/gentoo /var/lib/apk
cat > /usr/bin/apk <<'APK'
#!/usr/bin/env bash
# apk — Gentoo declarative package reconciler (not Alpine's apk).
set -Eeuo pipefail
MANIFEST=/etc/gentoo/gentoo.conf; ACTION=sync; DO_UPGRADE=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info(){ echo -e "${GREEN}[APK]${NC} $*"; }; warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }; die(){ echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }
if [[ $EUID -ne 0 ]]; then command -v sudo >/dev/null && exec sudo "$0" "$@"; die 'Run as root or install sudo.'; fi
while (($#)); do case "$1" in sync) ACTION=sync; shift;; check|-c|--check) ACTION=check; shift;; --upgrade) DO_UPGRADE=1; shift;; --path|-p) (($# >= 2)) || die '--path requires a path'; MANIFEST=$2; shift 2;; -h|--help) echo 'Usage: apk [sync [--upgrade] | check] [--path FILE]'; exit 0;; *) die "Unknown argument: $1";; esac; done
[[ -f $MANIFEST ]] || die "Manifest not found: $MANIFEST"
STATE=/var/lib/apk; mkdir -p "$STATE"
PKG_STATE=$STATE/packages.state; REPO_STATE=$STATE/repos.state; BINPKG_STATE=$STATE/binpkgs.state
trim(){ local x=$1; x=${x#"${x%%[![:space:]]*}"}; x=${x%"${x##*[![:space:]]}"}; printf '%s' "$x"; }
list(){ local s=${1//,/ }; read -ra a <<< "$s"; printf '%s\n' "${a[@]}" | sed '/^[[:space:]]*$/d'; }
# Parse section blocks without interpreting shell expressions.
SECTION=; declare -a WANT_PKGS=() WANT_SERVICES=() WANT_META=() MAKE_LINES=() USE_LINES=() KEYWORD_LINES=() MASK_LINES=() REPOS=() REPO_UNMASK=()
REPOS_ENABLED=false; BINPKGS=false; HOSTNAME_WANT=; TIMEZONE_WANT=; INIT=openrc; CURRENT_USER=; declare -A USERS=() USER_GROUPS=() USER_SHELLS=(); declare -a ENABLE_SERVICES=()
while IFS= read -r line || [[ -n $line ]]; do
  line=${line%%#*}; line=$(trim "$line"); [[ -z $line ]] && continue
  if [[ $line =~ ^\[user:([^]]+)\]$ ]]; then CURRENT_USER=${BASH_REMATCH[1]}; SECTION=user; USERS[$CURRENT_USER]=1; continue; fi
  if [[ $line =~ ^\[([^]]+)\]$ ]]; then SECTION=${BASH_REMATCH[1]}; CURRENT_USER=; continue; fi
  if [[ $line =~ ^init[[:space:]]*=[[:space:]]*([a-zA-Z0-9_-]+)$ ]]; then INIT=${BASH_REMATCH[1]}; continue; fi
  if [[ $SECTION == user ]]; then
    [[ $line =~ ^groups[[:space:]]*=[[:space:]]*\{(.*)\}$ ]] && { USER_GROUPS[$CURRENT_USER]=${BASH_REMATCH[1]}; continue; }
    [[ $line =~ ^shell[[:space:]]*=[[:space:]]*(.*)$ ]] && { USER_SHELLS[$CURRENT_USER]=$(trim "${BASH_REMATCH[1]}"); continue; }
  fi
  if [[ $line =~ ^pkgs[[:space:]]*=[[:space:]]*\{(.*)\}$ ]]; then
    mapfile -t a < <(list "${BASH_REMATCH[1]}"); case $SECTION in services) WANT_SERVICES+=("${a[@]}");; desktop) WANT_PKGS+=("${a[@]}");; *) WANT_PKGS+=("${a[@]}");; esac; continue
  fi
  if [[ $line =~ ^metapkgs[[:space:]]*=[[:space:]]*\{(.*)\}$ ]]; then mapfile -t a < <(list "${BASH_REMATCH[1]}"); WANT_META+=("${a[@]}"); continue; fi
  if [[ $line =~ ^enabled[[:space:]]*=[[:space:]]*\{(.*)\}$ && $SECTION == services ]]; then mapfile -t a < <(list "${BASH_REMATCH[1]}"); ENABLE_SERVICES+=("${a[@]}"); continue; fi
  if [[ $SECTION == make.conf ]]; then
    if [[ $line =~ ^enable-binpkgs[[:space:]]*=[[:space:]]*(true|false)$ ]]; then BINPKGS=${BASH_REMATCH[1]}; else MAKE_LINES+=("$line"); fi; continue
  fi
  if [[ $SECTION == package.use ]]; then USE_LINES+=("$line"); continue; fi
  if [[ $SECTION == package.accept_keywords ]]; then KEYWORD_LINES+=("$line"); continue; fi
  if [[ $SECTION == package.mask ]]; then MASK_LINES+=("$line"); continue; fi
  if [[ $SECTION == eselect-repos ]]; then
    case $line in enabled\ =\ true) REPOS_ENABLED=true;; enabled\ =\ false) REPOS_ENABLED=false;; repos\ =\ \{*\}) body=${line#*\{}; body=${body%\}}; mapfile -t a < <(list "$body"); REPOS+=("${a[@]}");; unmask\ =\ \{*\}) body=${line#*\{}; body=${body%\}}; body=${body//\'/}; mapfile -t a < <(list "$body"); REPO_UNMASK+=("${a[@]}");; esac; continue
  fi
  if [[ $SECTION == hostname && $line =~ ^hostname[[:space:]]*=[[:space:]]*(.*)$ ]]; then HOSTNAME_WANT=$(trim "${BASH_REMATCH[1]}"); fi
  if [[ $SECTION == timezone && $line =~ ^timezone[[:space:]]*=[[:space:]]*(.*)$ ]]; then TIMEZONE_WANT=$(trim "${BASH_REMATCH[1]}"); fi
done < "$MANIFEST"
[[ $INIT == openrc || $INIT == systemd || $INIT == dinit ]] || die "Invalid init '$INIT'"
# Always retain gentoolkit as part of the declarative tooling baseline.
WANT_PKGS+=(app-portage/gentoolkit)
# Merge package declarations and service packages into a unique list.
for p in "${WANT_SERVICES[@]}"; do WANT_PKGS+=("$p"); done
mapfile -t WANT_PKGS < <(printf '%s\n' "${WANT_PKGS[@]}" | sed '/^$/d' | sort -u)
# Manifest-owned Portage config files are deliberately replaced with tee (not tee -a).
if [[ $ACTION == sync ]]; then
  mkdir -p /etc/portage/package.use /etc/portage/package.accept_keywords /etc/portage/package.mask
  printf '%s\n' "${MAKE_LINES[@]}" | tee /etc/portage/make.conf >/dev/null
  PREVIOUS_BINPKGS=$(cat "$BINPKG_STATE" 2>/dev/null || echo false)
  if [[ $BINPKGS == true ]]; then
    if ! grep -Fq 'getbinpkg binpkg-request-signature' /etc/portage/make.conf; then
      printf '\nFEATURES="${FEATURES} getbinpkg binpkg-request-signature"\n' >> /etc/portage/make.conf
    fi
    mkdir -p /etc/portage/binrepos.conf
    cat > /etc/portage/binrepos.conf/gentoo.conf <<'BINREPO'
[gentoo]
priority = 9998
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
location = /var/cache/binhost/gentoo
BINREPO
    if grep -q 'gentoo-v3' "$MANIFEST"; then :; fi
  else
    sed -i '/^FEATURES=/s/ getbinpkg//; /^FEATURES=/s/ binpkg-request-signature//' /etc/portage/make.conf || true
    rm -f /etc/portage/binrepos.conf/gentoo.conf
  fi
  printf '%s\n' "$BINPKGS" > "$BINPKG_STATE"
  if [[ $PREVIOUS_BINPKGS != "$BINPKGS" ]]; then info "Binary package setting changed: $PREVIOUS_BINPKGS -> $BINPKGS"; fi
  printf '%s\n' "${USE_LINES[@]}" | tee /etc/portage/package.use/dectoo >/dev/null
  printf '%s\n' "${KEYWORD_LINES[@]}" | tee /etc/portage/package.accept_keywords/dectoo >/dev/null
  printf '%s\n' "${MASK_LINES[@]}" | tee /etc/portage/package.mask/dectoo >/dev/null
fi
# Repo state: ensure eselect-repository, add/remove declared overlays, sync new ones.
if [[ $REPOS_ENABLED == true ]]; then
  if ! command -v eselect-repository >/dev/null 2>&1; then emerge -q --ask=n app-eselect/eselect-repository; fi
  old_repos=(); [[ -f $REPO_STATE ]] && mapfile -t old_repos < "$REPO_STATE"
  for r in "${REPOS[@]}"; do
    if ! eselect repository list -i 2>/dev/null | grep -Eq "(^|[[:space:]])${r}([[:space:]]|$)"; then
      eselect repository enable "$r" || warn "Could not enable repository '$r'; check its name/configuration."
      emaint sync -r "$r" || warn "Repository sync failed for '$r'."
    fi
  done
  for r in "${old_repos[@]}"; do [[ " ${REPOS[*]} " == *" $r "* ]] || eselect repository disable "$r" || true; done
  printf '%s\n' "${REPOS[@]}" | sed '/^$/d' | sort -u > "$REPO_STATE"
  printf '%s\n' "${REPO_UNMASK[@]}" | tee /etc/portage/package.accept_keywords/repos >/dev/null
else
  if command -v eselect-repository >/dev/null 2>&1; then
    old_repos=(); [[ -f $REPO_STATE ]] && mapfile -t old_repos < "$REPO_STATE"
    for r in "${old_repos[@]}"; do eselect repository disable "$r" || true; done
    emerge -C --ask=n app-eselect/eselect-repository || true
  fi
  rm -f /etc/portage/package.accept_keywords/repos "$REPO_STATE"
fi
# Additions/removals are computed against the prior managed target list.
old_pkgs=(); [[ -f $PKG_STATE ]] && mapfile -t old_pkgs < "$PKG_STATE"
missing=(); removed=()
for p in "${WANT_PKGS[@]}"; do [[ -n $p ]] || continue; q=${p%%/*}; if ! emerge -q --pretend --oneshot "$p" >/dev/null 2>&1; then die "Unknown or unavailable package target '$p'. Check repository and manifest."; fi; if ! emerge -q --pretend --emptytree --oneshot "$p" >/dev/null 2>&1; then :; fi; if ! emerge -q --pretend --verbose "$p" 2>/dev/null | grep -q '\[ebuild\|\[binary\|\[installed\]'; then :; fi; if ! equery -q list "$p" >/dev/null 2>&1; then missing+=("$p"); fi; done
for p in "${old_pkgs[@]}"; do [[ -n $p ]] || continue; if [[ ! " ${WANT_PKGS[*]} " == *" $p "* ]] && equery -q list "$p" >/dev/null 2>&1; then removed+=("$p"); fi; done
if [[ $ACTION == check ]]; then
  ((${#missing[@]} == 0 && ${#removed[@]} == 0)) || { echo '[CHECK] Declarative package state differs.'; exit 1; }
  echo '[OK] Declared packages appear installed.'; exit 0
fi
if ((${#missing[@]})); then info "Installing missing packages: ${missing[*]}"; if [[ $BINPKGS == true ]]; then emerge -q --ask=n --getbinpkg "${missing[@]}"; else emerge -q --ask=n "${missing[@]}"; fi; fi
if ((${#removed[@]})); then info "Removing no-longer-declared packages: ${removed[*]}"; emerge -C -q --ask=n "${removed[@]}"; fi
printf '%s\n' "${WANT_PKGS[@]}" | sort -u > "$PKG_STATE"
# CPU flags remain managed from YAGIS's cpuid2cpuflags setup.
if command -v cpuid2cpuflags >/dev/null 2>&1; then printf '*/* %s\n' "$(cpuid2cpuflags)" | tee /etc/portage/package.use/00cpu-flags >/dev/null; fi
# Hostname/timezone reconciliation.
if [[ -n $HOSTNAME_WANT && $(cat /etc/hostname 2>/dev/null || true) != "$HOSTNAME_WANT" ]]; then echo "$HOSTNAME_WANT" > /etc/hostname; hostname "$HOSTNAME_WANT" || true; fi
if [[ -n $TIMEZONE_WANT && -e /usr/share/zoneinfo/$TIMEZONE_WANT ]]; then ln -sf "/usr/share/zoneinfo/$TIMEZONE_WANT" /etc/localtime; fi
# Service management.
for s in "${ENABLE_SERVICES[@]}"; do
  case $INIT in
    openrc) rc-update add "$s" default || warn "Could not enable OpenRC service '$s'.";;
    systemd) systemctl enable "$s" || warn "Could not enable systemd service '$s'.";;
    dinit) mkdir -p /etc/dinit.d/boot.d; [[ -e /etc/dinit.d/$s ]] && ln -sfn "../$s" "/etc/dinit.d/boot.d/$s" || warn "dinit service '$s' not found.";;
  esac
done
# Minimal declared user reconciliation, preserving homes on removal.
for u in "${!USERS[@]}"; do
  shell=${USER_SHELLS[$u]:-/bin/bash}; groups=${USER_GROUPS[$u]:-}
  if ! id "$u" >/dev/null 2>&1; then
    args=(-m -s "$shell"); if [[ -n $groups ]]; then mapfile -t gs < <(list "$groups"); args+=(-G "$(IFS=,; echo "${gs[*]}")"); fi
    useradd "${args[@]}" "$u"
  else
    usermod -s "$shell" "$u"
    if [[ -n $groups ]]; then mapfile -t gs < <(list "$groups"); usermod -aG "$(IFS=,; echo "${gs[*]}")" "$u"; fi
  fi
done
# Init transitions. OpenRC -> dinit is explicit and state-tracked; systemd migration is not guessed.
INIT_STATE=$STATE/init.state; OLD_INIT=$(cat "$INIT_STATE" 2>/dev/null || true)
if [[ $INIT == dinit && $OLD_INIT == openrc ]]; then
  if ! eselect repository list -i 2>/dev/null | grep -q guru; then warn "dinit migration requires the guru overlay. Enable it with: eselect repository enable guru; emaint sync -r guru"; else
    printf '%s\n' 'sys-apps/dinit sysv-utils' 'sys-apps/turnstile dinit' 'sys-apps/openrc -sysvinit' | tee /etc/portage/package.use/dinit >/dev/null
    emerge -q --ask=n sys-apps/openrc
    emerge -q --ask=n sys-apps/dinit sys-apps/dinit-services sys-apps/turnstile
    if grep -q '^#*[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
      sed -i -E 's/^#*[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT="([^"]*)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 init=\/usr\/sbin\/dinit"/' /etc/default/grub
    else echo 'GRUB_CMDLINE_LINUX_DEFAULT="init=/usr/sbin/dinit"' >> /etc/default/grub; fi
  fi
elif [[ $INIT != "$OLD_INIT" && -n $OLD_INIT && $INIT == systemd ]]; then
  warn 'Automatic systemd init migration is not implemented; select a systemd profile and migrate deliberately before rebooting.'
fi
printf '%s\n' "$INIT" > "$INIT_STATE"
if [[ $DO_UPGRADE == 1 ]]; then
  info 'Performing requested @world upgrade...'
  emerge --sync
  if [[ $BINPKGS == true ]]; then emerge -uDN --with-bdeps=y --getbinpkg @world; else emerge -uDN --with-bdeps=y @world; fi
  emerge --depclean
  if [[ $BINPKGS == true ]]; then rm -rf /var/tmp/portage/ /var/cache/distfiles/ /var/cache/binhost /var/cache/binpkgs; else rm -rf /var/tmp/portage/ /var/cache/distfiles/; fi
else
  info 'Regular sync does not upgrade @world; use apk sync --upgrade for that.'
fi
# Every successful sync regenerates GRUB config.
grub-mkconfig -o /boot/grub/grub.cfg
info 'Declarative reconciliation complete.'
APK
chmod +x /usr/bin/apk

# A fresh dinit install starts from the OpenRC stage3 and uses the same tracked migration path.
if [[ $INIT_SYSTEM == dinit ]]; then printf '%s\n' openrc > /var/lib/apk/init.state; fi
# First sync installs the manifest's declared packages, but deliberately does not upgrade @world.
apk sync
info 'Setting up GRUB and root password...'
passwd
if [[ $INIT_SYSTEM == systemd ]]; then systemd-firstboot --hostname="$NEW_HOSTNAME" --locale="$LOCALE" || true; systemd-machine-id-setup || true; fi
info 'Installation stage complete.'
CHROOT
# Substitute installer selections safely into chroot script.
sed -i "s|__BOOT_MODE__|$BOOT_MODE|g; s|__INIT_SYSTEM__|$INIT_SYSTEM|g; s|__GRUB_DISK__|${GRUB_DISK:-}|g; s|__NEW_HOSTNAME__|$NEW_HOSTNAME|g; s|__LOCALE__|$LOCALE|g" /mnt/gentoo/root/chroot-install.sh
chmod +x /mnt/gentoo/root/chroot-install.sh
info 'Entering Gentoo chroot...'
arch-chroot /mnt/gentoo /bin/bash /root/chroot-install.sh
rm -f /mnt/gentoo/root/chroot-install.sh
info 'Unmounting target...'; umount -R /mnt/gentoo 2>/dev/null || true
info 'Done. Remove the live media and reboot.'
