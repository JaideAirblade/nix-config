# Placeholder for a machine that is not exported or provisionable yet.
# Before adding OwO-Family to flake outputs, generate/review this module from a
# trusted live environment, add a verified by-id Disko layout, and follow the
# guarded positional workflow documented in README.md. The provisioning script
# intentionally never overwrites a reviewed hardware module.
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Placeholder — will be replaced by nixos-generate-config on the target
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "sd_mod" ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # fileSystems are managed by disko (disk-layout.nix)
  # hardware-configuration.nix will add initrd kernel modules after
  # nixos-anywhere generates it on the target.

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
