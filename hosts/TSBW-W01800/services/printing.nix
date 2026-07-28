# CUPS printing — manual printer config only, no auto-discovery
_:
{
  nixos.hosts."TSBW-W01800" =
    { pkgs, ... }: {
      services.printing = {
        enable = true;
        browsed.enable = false; # Disable cups-browsed — no automatic network printer discovery
      };

      environment.systemPackages = with pkgs; [
        cups # provides lpadmin, lpinfo, lpstat — manage printers manually
      ];
    }
  ;
}
