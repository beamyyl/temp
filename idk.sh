sudo pacman-key --init
sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key F3B607488DB35A47
sudo pacman -U \
  https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst \
  https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-27-1-any.pkg.tar.zst
echo '[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist' | sudo tee -a /etc/pacman.conf
sudo pacman -Syy
sudo pacman -S linux-cachyos linux-cachyos-headers linux-firmware
