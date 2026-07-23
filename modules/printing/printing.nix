# Printing (CUPS) — socket-activated, no always-running daemon.
#
# CUPS starts on-demand when a print job is submitted (via the cups.socket
# unit). This saves memory + attack surface — the print server isn't
# listening until you actually print.
#
# cups-browsed is disabled (no automatic network printer discovery —
# a privacy concern: it probes the local network for shared printers).
# Printers are configured manually via lpadmin or the CUPS web UI at
# http://localhost:631 (only available while CUPS is running).
#
# To print: just print normally — the socket activates CUPS automatically.
# To manage printers:   lpadmin -p <name> -E -v <uri> -m <model>
# Or visit:            http://localhost:631  (after socket activation)
{ pkgs, ... }:

{
  services.printing = {
    enable = true;
    browsed.enable = false;  # No cups-browsed — no network printer auto-discovery
    startWhenNeeded = true;  # Socket activation — CUPS starts on-demand
  };

  environment.systemPackages = with pkgs; [
    cups  # provides lpadmin, lpinfo, lpstat — manage printers manually
  ];
}