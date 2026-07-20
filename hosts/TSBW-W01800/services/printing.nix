# CUPS printing — manual printer config only, no auto-discovery
{pkgs, ...}: {
  services.printing = {
    enable = true;
    browsed.enable = false;  # Disable cups-browsed — no automatic network printer discovery
  };

  environment.systemPackages = with pkgs; [
    cups             # provides lpadmin, lpinfo, lpstat — manage printers manually
  ];
}