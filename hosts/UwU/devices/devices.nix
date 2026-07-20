# Device access — udev rules + user groups for HID devices.
#
# Two problems this module solves:
#
# 1. 1Password can't save/use passkeys on a YubiKey.
#    The YubiKey's FIDO2 interface is a HID device (/dev/hidraw*). On NixOS the
#    default udev rules don't grant non-root users access to it, so 1Password
#    (running as your user) can't talk to the key. The fix is libfido2's udev
#    rules, which set the right group + mode on FIDO2 HID raw devices.
#
# 2. Scyrox keyboard/mouse can't be configured via the web configurator
#    (scyrox.net, uses WebHID — Chromium-only). Chromium's WebHID API needs
#    read/write access to the /dev/hidraw* device, which requires udev rules
#    granting the user's group access. We match the exact vendor/product IDs
#    detected on this machine:
#      3554:f5f7 — SCYROX 8K Dongle (wireless mouse receiver)
#      19f5:fef1 — Scyrox Xpunk 63 Keyboard
#
# The conventional group for HID device access is `plugdev`. We create it,
# add jaide to it, and the udev rules assign the matching devices to that
# group with mode 0660 (group read/write).
{ pkgs, ... }:

{
  # libfido2 ships the upstream udev rules for FIDO2/security-key HID devices
  # (YubiKey, SoloKeys, etc.). This is the standard NixOS fix for "1Password
  # can't see my YubiKey" and similar FIDO2 failures.
  services.udev.packages = [ pkgs.libfido2 ];

  # Conventional group for user-accessible HID / plug-in devices.
  users.groups.plugdev = { };

  users.users."jaide".extraGroups = [ "plugdev" ];

  # Scyrox-specific udev rules for WebHID access from Chromium-based browsers.
  # Without these, Chromium's WebHID API can't open the /dev/hidraw* device and
  # the Scyrox web configurator (scyrox.net) can't connect.
  #
  # We match by vendor ID only (ATTRS{idVendor}) so all current and future
  # Scyrox products work, not just the specific product IDs detected today.
  # The HIDRAW device class is what WebHID opens, so we tag those.
  services.udev.extraRules = ''
    # Scyrox 8K wireless dongle (vendor 3554) — mouse
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3554", GROUP="plugdev", MODE="0660", TAG+="uaccess"

    # Scyrox Xpunk keyboard (vendor 19f5)
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="19f5", GROUP="plugdev", MODE="0660", TAG+="uaccess"
  '';
}