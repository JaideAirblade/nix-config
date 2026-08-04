# Hardware configuration for the Projet-Printserver VM.
#
# This is a libvirt VM in the ad-lab network. Unlike physical hosts that
# use nixos-generate-config, VM hardware is declared manually — we know
# exactly what QEMU provides.
#
# The disk is a single qcow2 image managed by libvirt. The VM is created
# by `just lab-create-printserver` which runs virt-install with this
# config's disk and network parameters.
{ modulesPath, lib, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # QEMU virtio disk — the qcow2 image is created by virt-install.
  # libvirt names it vol-* in the default pool; the /dev/disk/by-id/
  # path is stable across reboots.
  fileSystems."/" = {
    device = "/dev/disk/by-label/root";
    fsType = "ext4";
    autoFormat = true;
  };

  # Boot via BIOS (simpler for VMs, no UEFI needed for a print server).
  # mkForce: the common boot module enables systemd-boot (UEFI). This VM
  # uses SeaBIOS, so we disable systemd-boot and use GRUB instead.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.grub = {
    enable = lib.mkForce true;
    device = "/dev/vda";
  };

  # QEMU virtio kernel modules.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_net"
    "virtio_scsi"
  ];
  boot.initrd.kernelModules = [ "virtio_blk" ];

  # No firmware needed — QEMU provides SeaBIOS.
  hardware.enableAllFirmware = lib.mkForce false;
}
