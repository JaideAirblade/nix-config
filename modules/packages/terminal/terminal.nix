# Terminal emulators.
#
# Both are GPU-accelerated. User config (ghostty: ~/.config/ghostty/config,
# kitty: ~/.config/kitty/kitty.conf) is NOT managed by Nix — we deliberately
# avoid home-manager so programs that rewrite their own config stay writable.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ghostty  # primary terminal
    kitty    # fallback terminal
  ];
}