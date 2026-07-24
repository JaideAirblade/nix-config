# libvirt + QEMU/KVM virtualisation for running Windows VMs.
#
# Provides:
# - libvirtd service (QEMU driver)
# - virt-manager (GUI for managing VMs)
# - virsh CLI (works without sudo — jaide is in libvirtd group)
# - UEFI firmware (OVMF) for Windows 11 / Server 2022
# - TPM emulation (swtpm) — Windows 11 requires TPM 2.0
# - libguestfs (virt-customize, virt-sysprep) for image manipulation
# - QEMU guest agent support in VMs
{ pkgs, lib, config, ... }:

{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      # OVMF (UEFI) is now distributed with QEMU by default in unstable —
      # no need for ovmf.enable. swtpm is still explicit for TPM emulation.
      swtpm.enable = true;  # TPM emulation (Windows 11 needs this)
    };
  };

  # GUI VM manager
  programs.virt-manager.enable = true;

  # CLI + image tools
  environment.systemPackages = with pkgs; [
    virt-manager        # GUI VM manager
    virt-viewer         # SPICE/VNC viewer for VM consoles
    bridge-utils        # brctl for bridge networking
    libguestfs          # virt-customize, virt-sysprep, virt-clone
    virtiofsd           # virtio-fs shared filesystem
  ];

  # Add jaide to libvirtd group so virsh works without sudo
  users.users.jaide.extraGroups = [ "libvirtd" ];

  # Nested virtualisation (for VMs-in-VMs if needed)
  boot.extraModprobeConfig = lib.mkIf (config.hardware.cpu.amd.updateMicrocode or false) ''
    options kvm-amd nested=1
  '';
}