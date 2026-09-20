{ config, lib, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.kernelPackages = pkgs.linuxPackages_zen;
  networking.hostName = "nixos"; 
  system.stateVersion = "26.05";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Bucharest";
  security.sudo.wheelNeedsPassword = false;
  nixpkgs.config.allowUnfree = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };
  users.users.beamy = {
    isNormalUser = true;
    extraGroups = [ "wheel" "input" "networkmanager" "audio" "video" ];
    shell = pkgs.fish;
  };
  programs.fish.enable = true;
  environment.systemPackages = with pkgs; [ neovim wget curl fastfetch git steam-run-free vesktop gcc appimage-run firefox papirus-icon-theme openjdk25 prismlauncher cmatrix fetch alacritty xclip maim pcmanfm ];
  # apps Apps
  fonts.packages = with pkgs; [ nerd-fonts.iosevka nerd-fonts.adwaita-mono ];

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  services.xserver.enable = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.desktopManager.cinnamon.enable = true;
  services.flatpak.enable = true;
  services.printing.enable = true;
}
