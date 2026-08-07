# LaptopAP — unattended-installer ISO for a minimal WiFi-bridge AP host.
#
# Boots from ISO, wipes the first fixed disk, installs a standalone NixOS
# that creates an `ap` user with a baked-in yescrypt hash, and bridges
# any wired LAN connection to a WiFi AP (no NAT). Independent of the
# shared role modules — this is a throwaway work-laptop AP.
#
# Uses nixpkgs-stable (not unstable) for kernel/initrd stability.
# The installed system's full closure is baked into the ISO so nixos-install
# can install without any network access (no DNS resolution at install time).
{ inputs, ... }:
let
  stable = inputs.nixpkgs-stable;

  # The installed system as a separate NixOS evaluation.
  # Its toplevel closure is baked into the ISO store so nixos-install
  # can copy it to the target disk without any network access.
  installedSystem = stable.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ./installed/default.nix
      # Minimal hardware stub so it evaluates without real hardware.
      # nixos-install will use the real hardware-configuration.nix
      # generated on the target, but the closure is the same.
      ({ lib, ... }: {
        fileSystems."/" = lib.mkForce { device = "/dev/sda2"; fsType = "ext4"; };
        fileSystems."/boot" = lib.mkForce { device = "/dev/sda1"; fsType = "vfat"; };
        boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "nvme" "ahci" "sd_mod" "usb_storage" "xhci_pci" ];
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;
        nixpkgs.hostPlatform = "x86_64-linux";
      })
    ];
  };
in
{
  flake.nixosConfigurations.LaptopAP = stable.lib.nixosSystem {
    system = "x86_64-linux";

    modules = [
      # ISO installer base — produces a bootable CD/DVD image.
      "${stable}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      "${stable}/nixos/modules/installer/cd-dvd/channel.nix"

      # Live ISO environment + unattended installer (single module).
      ./live/default.nix

      # witr — process/port/container/file tracing CLI. Ships in both
      # unstable and stable nixpkgs, so no flake input / overlay is needed.
      # Useful in the live ISO for diagnosing installation failures.
      ({ pkgs, ... }: {
        environment.systemPackages = [ pkgs.witr ];
      })

      # Bake the installed system's full closure into the ISO store so
      # nixos-install can install it without network access.
      {
        isoImage.storeContents = [
          installedSystem.config.system.build.toplevel
        ];
        # Write the toplevel path to a file in the ISO so the auto-install
        # script can find it at runtime.
        environment.etc."installed-system-toplevel".text =
          "${installedSystem.config.system.build.toplevel}";
      }

      # NOTE: ./installed/default.nix is NOT imported as a module here.
      # It is the config for the *installed* system, not the live ISO.
      # live/default.nix copies it into the ISO's Nix store as a file
      # via the prepare-installed-config service, then nixos-install
      # evaluates it on the target disk.
    ];
  };
}
