# TSBW-W01800 host-specific boot overrides.
#
# The shared modules/boot/boot.nix sets up systemd-boot + zram + fstrim +
# gc with mkDefault. This host overrides:
#   - zramSwap: re-enabled (see below) with high priority over LUKS swap
#   - initrd systemd: enabled (required for FIDO2 LUKS unlock + Thunderbolt
#     authorization in initrd)
{ lib, ... }:

{
  # zram swap + LUKS disk swap together. zram is high-priority (fast,
  # in-RAM, no NVMe wakeups) so the system uses it first for any swap
  # activity — important on battery since NVMe wakeups cost power. The
  # LUKS swap partition is low-priority overflow for extreme memory
  # pressure. With 26GB RAM + swappiness=10, swap is rarely used anyway.
  zramSwap = {
    enable = lib.mkForce true;
    algorithm = lib.mkForce "zstd";
    priority = lib.mkDefault 100;  # higher than disk swap (default -1)
  };

  # systemd in initrd — required for:
  #   - systemd-cryptenroll FIDO2 LUKS unlock (see hardware/luks.nix)
  #   - Thunderbolt device authorization before amdgpu loads
  #     (see hardware/thunderbolt.nix)
  boot.initrd.systemd.enable = true;
}