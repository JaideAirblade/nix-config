# Base display server config (XWayland support + keymap)
# KDE Plasma and SDDM removed — using niri/mango + DankGreeter (greetd)
_:
{
  nixos.hosts."TSBW-W01800" =
    _: {
      services.xserver = {
        enable = true;
        xkb = {
          layout = "us,de";
          variant = ",";
        };
      };

      # Keep GTK icon cache updated so tray apps (Remmina, etc.) resolve icons
      gtk.iconCache.enable = true;
    }
  ;
}
