# Import-only entry for TSBW-W01800 desktop config.
{ ... }:

{
  imports = [
    ./plasma.nix    # base xserver/XWayland + keymap
    ./niri.nix      # niri compositor
    ./mango.nix     # mango compositor session target
    ./dms.nix       # DMS overrides (compositor, DankCalendar)
  ];
}