# UwU host-specific user overrides.
#
# Adds UwU-only groups (wireshark for packet capture without sudo, plus
# the shared module's defaults: networkmanager, wheel). The macrotool
# and devices modules append input/uinput/plugdev via their own
# users.users."jaide".extraGroups entries, which merge with this list.
#
# NOTE: Do NOT use lib.mkForce on extraGroups — it would override the
# merge and drop the input/uinput groups added by macrotool.nix, breaking
# evdev input capture and uinput injection.
{ inputs, ... }:
{
  nixos.hosts."UwU" =
    { config, lib, ... }:

    {
      users.users."jaide" = {
        description = lib.mkForce "Jaide";
        extraGroups = [ "networkmanager" "wheel" "wireshark" "_lldpd" ];
      };

      # The Luna controller key exists only on UwU. Target devices receive
      # only its public key through the privateAccounts role.
      sops.secrets.luna_ssh_private_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/UwU/luna-agent.yaml";
        owner = "jaide";
        group = "users";
        mode = "0600";
      };
      environment.sessionVariables.LUNA_SSH_IDENTITY =
        config.sops.secrets.luna_ssh_private_key.path;
    }
  ;
}
