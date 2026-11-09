# Daras Linux Installer & Declarative System Manager

A declarative installation script and system manager for **Daras Linux** (an Artix/Arch-based distribution supporting OpenRC and dinit). 

This installer bootstraps a base system using `basestrap`, configures init systems and bootloaders, injects custom Daras distribution branding, and installs `apk`—the custom **Daras Declarative Package Sync Tool**.

---

## Features

- **Multi-Init Support**: Choose between `OpenRC` and `dinit` during installation.
- **Dual Boot Modes**: Native support for both **UEFI** (with `efibootmgr`) and **BIOS** (legacy MBR/GPT).
- **Declarative System State (`apk`)**: Built-in system management engine driven by `/etc/daras/daras.conf`.
- **System Reconciliation**: `apk` automatically syncs installed packages, package blacklists, system services, users, user groups, shells, and user-level init services.
- **Daras Branding**: Custom OS identity configuration (`/etc/os-release`, `/etc/lsb-release`, GRUB branding, and scalable icons).
- **Custom Repository Integration**: Includes pre-configured access to the `[daras]` custom pacman repository.

---

## File Structure & Requirements

### Pre-installation Requirements
The installation script must be run from an **Artix Live ISO** and requires the following utilities:
- `basestrap`
- `fstabgen`
- `artix-chroot`

### Directory Layout Before Running
Ensure the following files are present in the installer directory:
- `install.sh` (The main installation script)
- `daras.conf` (Optional: existing configuration manifest, required if selecting "Existing configuration" mode)
- `logo/daras.svg` (Daras SVG logo used for distribution branding)

---

## Installation Guide

### Step 1: Partition and Mount Target Drives
Before executing the script, manually partition your drive and mount target file systems under `/mnt`.

#### UEFI System Example:
```bash
mount /dev/sda2 /mnt             # Root partition
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi    # EFI system partition
swapon /dev/sda3                 # Swap partition (optional)
```

#### BIOS System Example:
```bash
mount /dev/sda1 /mnt             # Root partition
swapon /dev/sda2                 # Swap partition (optional)
```

### Step 2: Run Installer
Execute the main installer script with root privileges:

```bash
chmod +x install.sh
sudo ./install.sh
```

### Step 3: Interactive Wizard Options
1. **Boot Mode Selection**: Select `1` for UEFI or `2` for BIOS.
2. **Init System Selection**: Select `1` for OpenRC or `2` for dinit.
3. **Configuration Mode**:
   - **Existing**: Uses `daras.conf` present in the current working directory.
   - **Template**: Generates `/tmp/daras-template.conf` and opens `nano` or `vim` for editing prior to installation.
4. **Root Password**: You will be prompted to set the root password inside the chroot before completion.

---

## Declarative Configuration (`daras.conf`)

The system configuration is defined in `/etc/daras/daras.conf` (or passed to the installer). Below is an annotated manifest template:

```toml
[kernel]
pkgs = { linux linux-firmware sof-firmware base base-devel }

[bootmgr]
pkgs = { grub efibootmgr }

[desktop]
metapkgs = { }
pkgs = { }

[packages]
pkgs = { sudo neovim git fastfetch }
blacklist = { geocode-glib-common }

[fonts]
pkgs = { ttf-iosevka-nerd ttf-adwaitamono-nerd }

[services]
pkgs = { dbus networkmanager cronie turnstile }
enabled = { dbus elogind NetworkManager cronie turnstile }

[drivers]
pkgs = { vulkan-intel mesa }

[sudo]
wheel = allowed no_sudo_password

[hostname]
hostname = daras

[timezone]
timezone = UTC

[user:beamy]
groups = { wheel audio video input }
shell = /bin/bash

[user-services]
beamy = { pipewire wireplumber pipewire-pulse }

init = openrc
```

---

## Daras Package Sync Tool (`apk`)

`apk` is the declarative state manager installed to `/usr/bin/apk`. It parses `/etc/daras/daras.conf` and reconciles current system state with desired manifest declarations.

### Usage

```bash
# Perform system update and reconcile state (default)
sudo apk sync

# Check state differences without making changes
sudo apk check

# Specify an alternate manifest path
sudo apk sync --path /path/to/custom.conf
```

### Key Functions of `apk`
1. **Package Management**:
   - Automatically installs missing packages declared under `[kernel]`, `[bootmgr]`, `[packages]`, `[fonts]`, and `[drivers]`.
   - Removes installed packages that are omitted from the manifest or listed in `blacklist`.
2. **Init System Services**:
   - Manages service runlevels for **OpenRC** (`rc-update`) or service symlinks for **dinit** (`/etc/dinit.d/boot.d/`).
3. **User Account Lifecycle**:
   - Creates users declared via `[user:username]` with specified shells and supplementary group memberships.
   - Provisions user-level init services listed under `[user-services]`.
4. **System Settings**:
   - Enforces hostname in `/etc/hostname` and `/etc/hosts`.
   - Updates target timezone symlinks in `/etc/localtime`.
   - Controls `/etc/sudoers.d/wheel` privileges based on `[sudo]` configuration.

---

## License

Distributed under the MIT License. See `LICENSE` for more information.
