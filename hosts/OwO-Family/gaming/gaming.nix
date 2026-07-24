# Gaming stack for OwO-Family.
# Same as UwU's gaming.nix but without 32-bit graphics (the 750 Ti legacy
# driver doesn't have 32-bit libs in the same way). Steam + Proton should
# still work — the 750 Ti is old but capable of older games.
{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    # Proton-GE as extra compatibility tool
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
  };

  # Wine for non-Steam games
  environment.systemPackages = with pkgs; [
    wineWowPackages.waylandFull
    winetricks
    steam-run
    # Heroic Games Launcher (GOG/Epic/sideload)
    heroic
    # Game mode + HUD
    gamemode
    mangohud
    vkbasalt
    # gamescope (micro-compositor for games)
    gamescope
  ];

  hardware.steam-hardware.enable = true;
}