# TSBW-W01800 host-specific boot overrides.
#
# The shared modules/boot/boot.nix sets up systemd-boot + zram + fstrim +
# gc with mkDefault. This host overrides:
#   - zramSwap: disabled (this host has a real LUKS swap partition)
#   - initrd systemd: enabled (required for FIDO2 LUKS unlock + Thunderbolt
#     authorization in initrd)
{ lib, ... }:

{
  # Real LUKS swap partition — no zram needed.
  zramSwap.enable = lib.mkForce false;

  # systemd in initrd — required for:
  #   - systemd-cryptenroll FIDO2 LUKS unlock (see hardware/luks.nix)
  #   - Thunderbolt device authorization before amdgpu loads
  #     (see hardware/thunderbolt.nix)
  boot.initrd.systemd.enable = true;
}