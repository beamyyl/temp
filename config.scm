(use-modules (gnu)
             (gnu services)
             (gnu services base)
             (guix packages)
             (gnu packages vim))

(use-service-modules cups desktop networking ssh xorg)

(operating-system
  (locale "en_US.utf8")
  (timezone "Europe/Bucharest")
  (keyboard-layout (keyboard-layout "us"))
  (host-name "guix")

  (users (cons* (user-account
                  (name "beamy")
                  (comment "Beamy")
                  (group "users")
                  (home-directory "/home/beamy")
                  (supplementary-groups '("wheel" "netdev" "audio" "video")))
                %base-user-accounts))

  (packages (append (list vim)
                    %base-packages))

  (services (modify-services (append (list (service network-manager-service-type)
                                           (service wpa-supplicant-service-type)
                                           (service ntp-service-type)
                                           (service gpm-service-type))
                                     %base-services)
              (guix-service-type config =>
                                 (guix-configuration
                                   (inherit config)
                                   (substitute-urls
                                     (append (list "https://substitutes.nonguix.org")
                                             %default-substitute-urls))
                                   (authorized-keys
                                     (append (list (plain-file "nonguix.pub"
                                                               "(public-key (ecc (curve Ed25519) (q #C1FD53E5D4CE971933EC50C9F307AE2171A2D3B52C804642A7A35F84F3A4EA98#)))"))
                                             %default-authorized-guix-keys))))))

  (bootloader (bootloader-configuration
                (bootloader grub-bootloader)
                (targets (list "/dev/sda"))
                (keyboard-layout keyboard-layout)))

  (file-systems (cons* (file-system
                         (mount-point "/")
                         (device (uuid "1894ede5-64cf-410d-a414-48b9318c41ea"))
                         (type "ext4"))
                       %base-file-systems)))
