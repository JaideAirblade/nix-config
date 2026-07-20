# fwupd — firmware updates via the LVFS (Linux Vendor Firmware Service).
#
# Motherboards, GPUs (including the RTX 3080), docks, and many peripherals
# ship firmware updates through LVFS. Without fwupd running, none of those
# updates land. `fwupdmgr get-updates` / `fwupdmgr update` are the user-facing
# commands; a system service keeps the LVFS metadata fresh automatically.
{ ... }:

{
  services.fwupd.enable = true;
}