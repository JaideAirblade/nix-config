# LUKS encryption devices + FIDO2/YubiKey boot unlock.
#
# The swap LUKS device was in the original configuration.nix (not
# hardware-configuration.nix) and must be in initrd config or boot
# fails waiting for the swap partition to decrypt.
#
# FIDO2 / YubiKey boot unlock:
#   systemd in initrd is already enabled (via thunderbolt.nix),
#   so we use systemd-cryptenroll for FIDO2 LUKS unlock.
#
# ENROLLMENT (run once per key per device, imperatively):
#   1. Insert YubiKey
#   2. Root device:
#        sudo systemd-cryptenroll --fido2-device=auto \
#          --fido2-with-client-pin=false \
#          --fido2-with-user-presence=true \
#          --fido2-with-user-verification=false \
#          /dev/disk/by-uuid/96ad6bc7-92ad-4168-881c-903aacb34ca5
#   3. Swap device:
#        sudo systemd-cryptenroll --fido2-device=auto \
#          --fido2-with-client-pin=false \
#          --fido2-with-user-presence=true \
#          --fido2-with-user-verification=false \
#          /dev/disk/by-uuid/2c438202-735c-4692-97b8-d441d81190d5
#   4. Repeat for each backup YubiKey (same command, different key inserted)
#
#   After enrolling, at boot the initrd will wait for you to touch
#   the YubiKey. If no key is present, it falls back to password
#   prompt after the grace period.
{ ... }:

{
  # Swap LUKS device
  boot.initrd.luks.devices."luks-2c438202-735c-4692-97b8-d441d81190d5".device =
    "/dev/disk/by-uuid/2c438202-735c-4692-97b8-d441d81190d5";

  # Enable FIDO2 support in the systemd initrd
  boot.initrd.systemd.fido2.enable = true;

  # FIDO2 grace period: seconds to wait for a key touch before
  # falling back to password prompt. 10s is the default but we set
  # it explicitly for clarity.
  boot.initrd.luks.devices."luks-96ad6bc7-92ad-4168-881c-903aacb34ca5".fido2.gracePeriod = 10;
  boot.initrd.luks.devices."luks-2c438202-735c-4692-97b8-d441d81190d5".fido2.gracePeriod = 10;
}