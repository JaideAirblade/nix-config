# Steam — gaming platform with Proton support
{pkgs, ...}: {
  programs.steam = {
    enable = true;
    # Use Millennium-wrapped Steam (injects Millennium's .so for theme/skin
    # loading). The overlay from inputs.millennium provides pkgs.millennium-steam.
    package = pkgs.millennium-steam;
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