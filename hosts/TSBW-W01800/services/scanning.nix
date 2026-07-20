# Scanner support — SANE backends + ipp-usb for network/AirScan printers
{...}: {
  hardware.sane = {
    enable = true;
    extraBackends = [];  # Add vendor-specific backends here if needed (e.g. hplip)
  };

  # ipp-usb: makes AirPrint/WSD printers+scanners accessible over USB
  services.ipp-usb.enable = true;
}