# User accounts. Per-user dotfiles are NOT managed here (we dropped
# home-manager on purpose — programs that write their own config stay
# writable). This only declares the account itself and its groups.
#
# Defaults are written with lib.mkDefault so a host can override the
# description or add host-specific groups (e.g. UwU adds input/uinput
# via the macrotool/devices modules). Both hosts add `wireshark` for
# packet capture without sudo. Hosts set extraGroups via lib.mkForce
# or append via the module-system merge.
#
# ─────────────────────────────────────────────────────────────────
# systemd-userdbd — propagate user/group changes to running sessions
# ─────────────────────────────────────────────────────────────────
# Without `services.userdbd.enable`, the `users.users.<name>.extraGroups`
# change only takes effect for NEW sessions: a user who is logged in
# must log out and back in (or start a fresh shell with a different
# cred-cache) to refresh the supplementary-group set the kernel hands
# to child processes. systemd-userdbd runs the systemd-userdbd.socket
# + service pair that watches `/etc/userdb/` (synthesised from Nix
# declarative users.users) and tells the running user@<uid>.service
# instance to refresh its creds.
#
# Tangible benefit: modules that add system users to a group (e.g.
# the netbird-mesh role adding `jaide` to `netbird-mesh` so the
# hardened daemon socket is reachable) work across logins without
# requiring a manual `loginctl terminate-user jaide` every time the
# role changes.
#
# NixOS 26.05 does NOT enable this by default (the option is
# `services.userdbd.enable = false` upstream). The SSH support flag
# (`enableSSHSupport`) requires `security.enableWrappers` and is
# deliberately left off; we are not using OpenSSH userdb integration.
_:
{
  nixos.modules.common =
    { lib, ... }:

    {
      # Real, shared `jaide` group — declared here so every host gets a
      # consistent gid. The supplementary-group grant (Luna in `jaide`)
      # is layered on top by the automationAccounts role module (in
      # modules/users/private-accounts.nix) so that work-only / lab
      # hosts (print server, etc.) which don't pull automationAccounts
      # don't receive cross-account access they don't need.
      users.groups."jaide" = { };

      users.users."jaide" = {
        isNormalUser = true;
        description = lib.mkDefault "Jaide";
        homeMode = "0750"; # group can read — required for Luna to operate in this home
        extraGroups = lib.mkDefault [ "networkmanager" "wheel" ];
      };

      services.userdbd.enable = true;
      # NixOS-standard sandbox build users (nixbld1..32, UID 30001-30032)
      # and `nobody` (UID 65534) trigger the userdbd high-UID warning
      # because the userdbd module considers any system user with UID>=1000
      # an "unusual" high-system-user. We have these by design. Acknowledge
      # and silence the warning so every dry-build doesn't print it.
      services.userdbd.silenceHighSystemUsers = true;
    }
  ;
}
