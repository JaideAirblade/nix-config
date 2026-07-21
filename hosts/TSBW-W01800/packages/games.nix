# Gaming packages — Steam, Wine, Proton tooling, and enhancements
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # --- Wine & compatibility ---
    wineWow64Packages.stable  # Wine (32-bit + 64-bit) for running Windows apps
    winetricks                # Helper script to install Wine DLLs and fonts
    wineWow64Packages.fonts    # Microsoft replacement fonts from Wine

    # --- Proton management ---
    protonplus      # Wine & Proton compatibility tools manager (GNOME/GTK)

    # --- Game enhancements ---
    mangohud        # Vulkan/OpenGL overlay — FPS, CPU/GPU stats, frame timing
    gamescope       # Steam micro-compositor — window manager for games
    gamemode        # Daemon to optimize CPU/governor performance for games

    # --- Native Electron for Electron-based Steam games (FeeBay, etc.) ---
    electron        # Run Windows Electron games natively on Linux via app.asar
  ];
}