# Steam — gaming platform with Proton support
{pkgs, ...}: {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;          # Steam Remote Play
    dedicatedServer.openFirewall = true;     # Source dedicated servers
    localNetworkGameTransfers.openFirewall = true;  # Local game transfers

    # Proton-GE as extra compatibility tool
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  # Steam hardware support (controllers, HTC Vive)
  hardware.steam-hardware.enable = true;
}