# USBGuard — USB device authorization whitelist.
#
# Blocks unknown USB devices (BadUSB, rubber ducky, etc.) plugged in AFTER
# boot. Devices already connected when the daemon starts are trusted
# (presentDevicePolicy=allow), so your keyboard, mouse, YubiKeys, dock, etc.
# always work — no lockout risk.
#
# New devices plugged in after boot are evaluated against the declarative
# rules below (insertedDevicePolicy=apply-policy). Devices not matching any
# rule are blocked (implicitPolicyTarget=block).
#
# ## Adding a new device
#
#   1. Plug in the device.
#   2. Run:  usb-accept   (wrapper script — shows blocked devices, lets you pick)
#   3. The script prints the generated rule. Copy it into the `rules` option
#      below, rebuild, and you're done.
#
# Alternatively, for a quick session-only allow (no rebuild):
#
#   usbguard list-devices       # find the blocked device ID
#   usbguard allow-device <id>  # allowed until reboot
#
# ## How it works
#
# The rules are managed declaratively via services.usbguard.rules — they're
# immutable at runtime (can't be changed via IPC) and version-controlled in
# this file. presentDevicePolicy=allow ensures boot-connected devices work
# even if they're not in the rules list (belt-and-suspenders).
{ config, pkgs, ... }:

{
  services.usbguard = {
    enable = false; # disabled for now — re-enable with `true` when ready
    IPCAllowedUsers = [ "jaide" ];

    # Declarative rules — version-controlled, immutable at runtime.
    # Generated from `usbguard generate-policy` on UwU (2026-07-23).
    # Controllers (1d6b:*) are USB host controllers — always allow.
    # Peripherals are matched by vendor:product ID + name for readability.
    rules = ''
      # ── USB Host Controllers (always allow) ──────────────────────────
      allow id 1d6b:0002 serial "0000:02:00.0" name "xHCI Host Controller" hash "4+i1fOQzh6/CdbdfiwrmdTYf8TLnLkUDuN34mexLwrg=" parent-hash "VWFGb1mvEnmw1lIrXHKYSzgP8x/QIoOY2NUuEU5jiAo=" with-interface 09:00:00 with-connect-type ""
      allow id 1d6b:0003 serial "0000:02:00.0" name "xHCI Host Controller" hash "dmR8EZq+bulAtCjc2bVI0LYev+vk92bQ/cq9b3PJMtg=" parent-hash "VWFGb1mvEnmw1lIrXHKYSzgP8x/QIoOY2NUuEU5jiAo=" with-interface 09:00:00 with-connect-type ""
      allow id 1d6b:0002 serial "0000:0d:00.3" name "xHCI Host Controller" hash "kfg9rWbHDmu9sziJKn54hYXgOUymiXkU/EU39jdg/GA=" parent-hash "cdghNvZ/xovKSKWI21Ni/PhRXov1mGuQqJRwQMfktac=" with-interface 09:00:00 with-connect-type ""
      allow id 1d6b:0003 serial "0000:0d:00.3" name "xHCI Host Controller" hash "y9bmScaW3CtCiisIhZ3sBE9wkgylXCaUF98Xp3dtFXI=" parent-hash "cdghNvZ/xovKSKWI21Ni/PhRXov1mGuQqJRwQMfktac=" with-interface 09:00:00 with-connect-type ""

      # ── Peripherals ──────────────────────────────────────────────────
      # SCYROX V8 (keyboard, wired mode)
      allow id 3554:f5f6 serial "" name "SCYROX V8" hash "qU1Zj/XI/8CNJtZwsza5TVZ3HKXk2D7PXIFfOFV8mi8=" parent-hash "4+i1fOQzh6/CdbdfiwrmdTYf8TLnLkUDuN34mexLwrg=" via-port "1-1" with-interface { 03:01:01 03:00:00 03:01:02 } with-connect-type "hotplug"
      # SCYROX 8K Dongle (mouse, wireless 2.4GHz)
      allow id 3554:f5f7 serial "" name "SCYROX 8K Dongle" hash "i8dgxyBdVSrVstnI2qXNA1VidBxrPtMSRkz772qUJSI=" parent-hash "4+i1fOQzh6/CdbdfiwrmdTYf8TLnLkUDuN34mexLwrg=" via-port "1-2" with-interface { 03:01:01 03:00:00 03:01:02 } with-connect-type "hotplug"
      # AURA LED Controller (motherboard RGB, internal USB)
      allow id 0b05:1939 serial "9876543210" name "AURA LED Controller" hash "bH4kgl30cMWVjIo4N479G9ljRuABTa4e8eQjkEoJYwI=" parent-hash "4+i1fOQzh6/CdbdfiwrmdTYf8TLnLkUDuN34mexLwrg=" with-interface { ff:ff:ff 03:00:00 } with-connect-type "hardwired"
      # fifine Chat (USB microphone)
      allow id 3142:0c88 serial "20190808" name "fifine Chat" hash "cL3L9gMW2bIy2UVOZDMRWOkyQMxKZCpOpjKs95u5WZ4=" parent-hash "kfg9rWbHDmu9sziJKn54hYXgOUymiXkU/EU39jdg/GA=" via-port "3-1" with-interface { 01:01:00 01:02:00 01:02:00 01:02:00 01:01:00 01:02:00 01:02:00 01:02:00 03:00:00 03:00:00 01:01:00 01:02:00 01:02:00 01:02:00 } with-connect-type "hotplug"
      # FREQCHIP-HID (USB device, appears alongside fifine mic)
      allow id 3142:0038 serial "1F4CE70C05A6" name "FREQCHIP-HID" hash "k+0wTZrdRpG2MwY8YoTmdYqtuq3msroY1hIH0AOYD8A=" parent-hash "kfg9rWbHDmu9sziJKn54hYXgOUymiXkU/EU39jdg/GA=" via-port "3-2" with-interface 03:00:00 with-connect-type "hotplug"
      # Xpunk 63 Keyboard (secondary/wired keyboard)
      allow id 19f5:fef1 serial "474840815241" name "Xpunk 63 Keyboard" hash "/eWFqZPG1E3QpLbTzODhUfKqt1EOEmV/1C0bsWfG9hA=" parent-hash "kfg9rWbHDmu9sziJKn54hYXgOUymiXkU/EU39jdg/GA=" via-port "3-3" with-interface { 03:01:01 03:00:00 03:01:01 } with-connect-type "hotplug"
      # Bluetooth adapter (0489:e10d — Foxconn/Broadcom BT, internal USB)
      allow id 0489:e10d serial "" name "" hash "PmlV/iHfj5xpTD0gx8bauwSPEDfVsG+1FRpCXvs9k/Y=" parent-hash "4+i1fOQzh6/CdbdfiwrmdTYf8TLnLkUDuN34mexLwrg=" via-port "1-10" with-interface { e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 e0:01:01 } with-connect-type "hotplug"
    '';

    # Devices already connected at boot → allow (prevents lockout)
    presentDevicePolicy = "allow";
    # Controllers already connected at boot → keep their state
    presentControllerPolicy = "keep";
    # New devices plugged in after boot → evaluate against rules
    insertedDevicePolicy = "apply-policy";
    # Devices that don't match any rule → block
    implicitPolicyTarget = "block";
  };

  # usb-accept — convenience script to list blocked devices and generate
  # a rule for easy copy-paste into the declarative rules above.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "usb-accept" ''
      #!/bin/sh
      # usb-accept — list blocked USB devices and generate a rule to allow them.
      #
      # Usage:
      #   usb-accept              # list blocked devices, pick one to allow
      #   usb-accept <id>         # allow a specific device ID (session-only)
      #   usb-accept --rule <id>  # print the permanent rule for pasting into security.nix
      #
      # To make it permanent: copy the printed rule into services.usbguard.rules
      # in modules/security/security.nix, then rebuild.

      show_blocked() {
        blocked=$(usbguard list-devices --blocked 2>/dev/null)
        if [ -z "$blocked" ]; then
          echo "No blocked USB devices. Everything is allowed."
          return 1
        fi
        echo "Blocked USB devices:"
        echo "$blocked"
        echo ""
        return 0
      }

      if [ "$1" = "--rule" ] && [ -n "$2" ]; then
        id="$2"
        # Get the full device rule from usbguard
        rule=$(usbguard list-devices --no-header 2>/dev/null | grep "^$id: " | sed "s/^$id: //")
        if [ -z "$rule" ]; then
          echo "Device $id not found. Run 'usbguard list-devices' to see all devices."
          exit 1
        fi
        echo "# Add this line to services.usbguard.rules in modules/security/security.nix:"
        echo "allow $rule"
        echo ""
        echo "# Then rebuild: just deploy"
        exit 0
      fi

      if [ -n "$1" ]; then
        # Allow a specific device for this session
        usbguard allow-device "$1" 2>/dev/null
        echo "Device $1 allowed for this session (until reboot)."
        echo "To make it permanent, run: usb-accept --rule $1"
        exit 0
      fi

      # No args — show blocked devices and prompt
      if ! show_blocked; then
        exit 0
      fi

      printf "Enter device ID to allow (session-only): "
      read id
      if [ -z "$id" ]; then
        echo "No ID entered. Exiting."
        exit 0
      fi
      usbguard allow-device "$id" 2>/dev/null
      echo ""
      echo "Device $id allowed for this session (until reboot)."
      echo "To make it permanent, run: usb-accept --rule $id"
    '')
  ];
}