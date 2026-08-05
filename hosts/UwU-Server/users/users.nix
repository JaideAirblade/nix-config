# UwU-Server host-specific user overrides.
{ inputs, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, ... }:

    {
      users.users."jaide" = {
        extraGroups = [ "networkmanager" "wheel" ];
        # The authorized SSH key is the only bootstrap credential. Set a login
        # password with `passwd` over that authenticated session if remote sudo is
        # needed; never put a plaintext bootstrap password in the Nix store.
      };

      # Distinct central-agent fleet identity. The encrypted private key is
      # readable only by this host's SOPS identity; targets receive only the
      # public half through automationAccounts.
      sops.secrets.luna_server_ssh_private_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/UwU-Server/luna-agent.yaml";
        key = "luna_ssh_private_key";
      };
      sops.templates.luna_server_ssh_identity = {
        content = "${config.sops.placeholder.luna_server_ssh_private_key}\n";
        owner = "luna";
        group = "luna";
        mode = "0600";
      };

      # Normal-user home creation is owned by users.users.luna. tmpfiles only
      # installs the default outgoing SSH identity symlink after SOPS renders
      # it in /run; it does not create or relocate Luna's home.
      systemd.tmpfiles.rules = [
        "d /home/luna/.ssh 0700 luna luna -"
        "L+ /home/luna/.ssh/id_ed25519 - - - - ${config.sops.templates.luna_server_ssh_identity.path}"
      ];
    }
  ;
}
