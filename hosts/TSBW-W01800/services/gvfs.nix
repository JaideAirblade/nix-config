# Virtual filesystem services for GNOME/GTK apps
{pkgs, ...}: {
  # GVfs — enables SMB/CIFS, MTP, AFP, etc. browsing in Nautilus
  # services.gvfs.enable sets GIO_EXTRA_MODULES to include the gvfs dbus
  # module so gio/Nautilus can talk to gvfsd for SMB browsing.
  services.gvfs.enable = true;
  services.gvfs.package = pkgs.gnome.gvfs;

  # Avahi — mDNS/DNS-SD service discovery
  # Required by gvfsd-dnssd + gvfsd-network so Nautilus's "Other Locations"
  # / network:// tab can discover SMB shares and other network services.
  services.avahi = {
    enable = true;
    nssmdns4 = true;  # resolve .local hosts via mDNS
    publish.enable = true;
    publish.userServices = true;  # advertise this machine on the network
  };

  # Tracker3 / TinySPARQL + LocalSearch — file indexer required by Nautilus
  # Without these, Nautilus warns "Unable to create connection for session-wide
  # Tracker indexer" and the network tab fails to initialize.
  environment.systemPackages = with pkgs; [
    tinysparql
    localsearch
  ];
}