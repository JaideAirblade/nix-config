# 1Password — password manager (GUI + CLI).
#
# Uses the NixOS modules (programs._1password / programs._1password-gui)
# rather than bare environment.systemPackages so that:
#   - browser native-messaging hosts are auto-wired for Firefox/Chrome/Brave
#     (the extension unlocks when the desktop app is unlocked), and
#   - polkit policy is installed so system-authentication unlock (fingerprint
#     / login password) works.
#
# Prerequisites already satisfied elsewhere in this config:
#   - nixpkgs.config.allowUnfree = true  (modules/nix/nix.nix)
#   - security.polkit.enable = true      (modules/wm/dms/dms.nix — DMS ships
#     its own polkit agent, which 1Password's system-auth prompt talks to)
#   - programs.firefox.enable = true     (modules/packages/packages.nix —
#     browser extension unlocking is auto-configured for Firefox)
#
# polkitPolicyOwners lists jaide so the 1Password polkit rules grant the
# user the right to use system-auth unlock. SSH-key management and git
# commit signing via 1Password are per-user concerns and are intentionally
# NOT configured here — the user owns ~/.ssh/config and ~/.gitconfig.
{ ... }:

{
  programs._1password.enable = true;

  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "jaide" ];
  };
}