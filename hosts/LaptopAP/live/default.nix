# Live ISO environment + unattended installer.
#
# This is what runs when booting the ISO: a minimal root-autologin shell
# with a systemd service that automatically wipes the first non-removable
# disk, installs NixOS from the embedded installed-system config, and
# reboots into the installed system.
{ lib, pkgs, ... }:
{
  # Identifiable hostname on the live medium.
  networking.hostName = "nixos-installer";
  networking.networkmanager.enable = lib.mkForce false;

  # DHCP on all wired interfaces so the installer can reach the network.
  networking.useDHCP = true;

  # Quiet, fast boot — no graphical environment needed.
  # The installation-device profile defaults to autologin as "nixos";
  # override it since we want root for the installer.
  services.getty.autologinUser = lib.mkForce "root";

  # Keep running with the lid closed — the install may happen headless.
  services.logind.lidSwitch = lib.mkForce "ignore";

  environment.systemPackages = with pkgs; [
    parted
    dosfstools
    nixos-install
    util-linux
    iproute2
    gptfdisk
  ];

  # Copy the installed-system config into the ISO's Nix store so
  # nixos-install can consume it without network access.
  systemd.services.prepare-installed-config = {
    wantedBy = [ "multi-user.target" ];
    before = [ "auto-install.service" ];
    script = ''
      cp ${../installed/default.nix} /etc/installed-system.nix
    '';
    serviceConfig.Type = "oneshot";
  };

  # Unattended installer — wipes the first non-removable disk and installs.
  systemd.services.auto-install = {
    wantedBy = [ "multi-user.target" ];
    # Run after the channel-init service unpacks nixpkgs and the config is ready.
    after = [ "prepare-installed-config.service" "nix-daemon.service" ];
    wants = [ "prepare-installed-config.service" ];

    # Don't start if we're already on the installed system (not the ISO).
    unitConfig.ConditionPathExists = "/etc/NIXOS_INSTALLER";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Send output to the journal so we can debug failures.
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };

    path = with pkgs; [
      parted
      dosfstools
      nixos-install
      nixos-install-tools
      nix
      util-linux
      coreutils
      iproute2
      gptfdisk
      e2fsprogs
      gawk
      efibootmgr
      systemd
    ];

    script = ''
      set -euxo pipefail

      # Find the first non-removable disk by scanning /sys/block.
      # Falls back to /dev/sda if detection fails.
      disk=""
      for dev in /sys/block/sd* /sys/block/vd* /sys/block/nvme*n*; do
        [ -e "$dev" ] || continue
        base=$(basename "$dev")
        # Skip removable devices, USB sticks, the ISO medium itself.
        if [ -f "$dev/removable" ] && [ "$(cat "$dev/removable")" = "1" ]; then
          continue
        fi
        # Skip loop, ram, dm, cdrom devices.
        case "$base" in
          loop*|ram*|dm-*|sr*) continue ;;
        esac
        disk="/dev/$base"
        break
      done

      if [ -z "$disk" ]; then
        echo "No suitable non-removable disk found, falling back to /dev/sda"
        disk="/dev/sda"
      fi

      echo "Installing NixOS to $disk"

      # Wipe all partition tables and signatures.
      sgdisk --zap-all "$disk" 2>/dev/null || true
      dd if=/dev/zero of="$disk" bs=1M count=10 conv=fsync || true
      partprobe "$disk" 2>/dev/null || true
      sleep 2

      # Get disk size in MiB for percentage-based partitioning.
      disk_size_mib=$(blockdev --getsize64 "$disk" 2>/dev/null | awk '{printf "%.0f", $1/1048576}')
      if [ -z "$disk_size_mib" ] || [ "$disk_size_mib" -lt 1024 ]; then
        echo "ERROR: Disk $disk is too small (''${disk_size_mib:-0} MiB), need at least 1 GiB"
        exit 1
      fi
      echo "Disk size: $disk_size_mib MiB"

      # EFI partition: 512MiB (fixed), root: rest of disk.
      esp_end=513
      parted -s "$disk" mklabel gpt
      parted -s "$disk" mkpart ESP fat32 1MiB "''${esp_end}MiB"
      parted -s "$disk" set 1 esp on
      parted -s "$disk" mkpart primary "''${esp_end}MiB" 100%

      # Re-read partition table.
      partprobe "$disk" 2>/dev/null || true
      sleep 2

      # Resolve partition device names (nvme0n1p1 vs sda1 vs vda1).
      if echo "$disk" | grep -qE "nvme|mmcblk"; then
        esp_dev="''${disk}p1"
        root_dev="''${disk}p2"
      else
        esp_dev="''${disk}1"
        root_dev="''${disk}2"
      fi

      # Wait for partition devices to appear.
      for i in $(seq 1 10); do
        [ -b "$esp_dev" ] && [ -b "$root_dev" ] && break
        sleep 1
      done
      [ -b "$esp_dev" ] || { echo "ERROR: $esp_dev did not appear"; exit 1; }
      [ -b "$root_dev" ] || { echo "ERROR: $root_dev did not appear"; exit 1; }

      # Format.
      mkfs.fat -F32 -n ESP "$esp_dev"
      mkfs.ext4 -F -L nixos "$root_dev"

      # Mount.
      mount "$root_dev" /mnt
      mkdir -p /mnt/boot
      mount "$esp_dev" /mnt/boot

      # Generate hardware-configuration.nix from the mounted target.
      nixos-generate-config --root /mnt

      # Write a configuration.nix that merges the generated
      # hardware-configuration with the embedded installed-system config.
      # This is used by nixos-rebuild on the installed system later.
      cat > /mnt/etc/nixos/configuration.nix <<'CONF'
{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    /etc/installed-system.nix
  ];
}
CONF

      # Find the pre-built installed system toplevel in the Nix store.
      # It was baked into the ISO via isoImage.storeContents.
      # The path is stored in /etc/installed-system-toplevel at build time.
      toplevel=$(cat /etc/installed-system-toplevel)
      if [ -z "$toplevel" ] || [ ! -d "$toplevel" ]; then
        echo "ERROR: pre-built toplevel not found: $toplevel"
        exit 1
      fi
      echo "Using pre-built system: $toplevel"

      # Wait for the nixpkgs channel to be unpacked so nixos-install
      # can evaluate the bootloader config.
      echo "Waiting for nixpkgs channel..."
      for i in $(seq 1 60); do
        [ -d /nix/var/nix/profiles/per-user/root/channels/nixos ] && break
        sleep 2
      done
      export NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"

      # Install the pre-built closure. nixos-install copies the closure
      # from the ISO's Nix store (no network needed for packages), but
      # still evaluates the bootloader config to install systemd-boot.
      nixos-install \
        --root /mnt \
        --system "$toplevel" \
        --no-channel-copy \
        --no-root-password

      # Ensure the installed system is the default boot entry.
      # nixos-install should do this via switch-to-configuration, but
      # some firmware needs an explicit efibootmgr call.
      esp_partnum=$(cat /sys/class/block/$(basename "$esp_dev")/partition 2>/dev/null || echo "1")
      esp_uuid=$(blkid -s PARTUUID -o value "$esp_dev" 2>/dev/null || echo "")
      if [ -n "$esp_uuid" ]; then
        # Remove any existing NixOS entry, then create a new one as Boot0000.
        efibootmgr -b 0000 -B 2>/dev/null || true
        efibootmgr -c -d "$(lsblk -ndo PKNAME "$disk" 2>/dev/null | head -1 || echo "$disk")" \
          -p "$esp_partnum" -L "NixOS LaptopAP" \
          -l "\EFI\systemd\systemd-bootx64.efi" 2>/dev/null || true
        # Set it as first in boot order.
        efibootmgr -o 0000,0001,0002,0003 2>/dev/null || true
        echo "Boot order set to NixOS LaptopAP first"
      fi

      echo "Installation complete, rebooting in 10 seconds..."
      sleep 10
      reboot
    '';
  };

  # Marker file so the service only runs in the ISO, not the installed system.
  environment.etc."NIXOS_INSTALLER".text = "1";
}