# System-level NixOS configuration.
#
# Per the ryan4yin/nixos-and-flakes-book guide:
#   - This file is imported as a module by flake.nix.
#   - System-wide concerns only (bootloader, networking, locale, audio,
#     printing, the display manager / desktop environment, the user
#     account, firewall, system packages).
#   - User-level concerns (per-user packages, git config, shell config,
#     dotfiles) live in home.nix and are applied by home-manager.
#
# The current desktop environment (Budgie) is TEMPORARY — when swapping
# to a different DE/WM, replace the block marked "Desktop environment"
# below. Everything else is DE-independent.

{ config, pkgs, inputs, ... }:

{
  imports = [
    # Hardware scan output — auto-generated, do not edit by hand.
    ./hardware-configuration.nix
  ];

  # --- Bootloader -----------------------------------------------------------
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- Networking -----------------------------------------------------------
  networking.hostName = "Uwu"; # Define your hostname.
  networking.networkmanager.enable = true;

  # --- Time / locale --------------------------------------------------------
  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  # --- Desktop environment (TEMPORARY — replace to swap DE/WM) -------------
  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.desktopManager.budgie.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # --- Printing -------------------------------------------------------------
  services.printing.enable = true;

  # --- Sound (PipeWire) ----------------------------------------------------
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # jack.enable = true;
  };

  # --- User account ---------------------------------------------------------
  # User-level packages/dotfiles are managed by home-manager via home.nix;
  # this only declares the account itself and its system groups.
  users.users."jaide" = {
    isNormalUser = true;
    description = "Jaide";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # --- Programs (system-wide) ----------------------------------------------
  programs.firefox.enable = true;

  # --- Nix settings ---------------------------------------------------------
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # --- System packages -----------------------------------------------------
  # Only things every user / root should have. Per-user tools go in home.nix.
  environment.systemPackages = with pkgs; [
    vim # editor of last resort (also needed before home-manager is active)
    wget
    git # flakes clone deps via git
  ];

  environment.variables.EDITOR = "vim";

  # --- Disk / GC hygiene (from the guide's "Reducing Disk Usage") ---------
  boot.loader.systemd-boot.configurationLimit = 10;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = true;

  # --- zram swap -----------------------------------------------------------
  # Compressed RAM swap. Good on systems with enough RAM that disk swap is
  # rarely needed but you want a safety net without wearing the SSD.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # --- State version -------------------------------------------------------
  # Leave this at the release the system was first installed with.
  system.stateVersion = "26.05";
}