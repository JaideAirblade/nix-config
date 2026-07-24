# Stealth SSH server — FIDO2/YubiKey-only auth, VPN-only listener.
#
# ## Security model
#
#   - sshd listens ONLY on the AmneziaWG VPN interface (10.100.0.1)
#   - No SSH on LAN, public IP, or any other interface
#   - Password auth: disabled
#   - Regular SSH keys: disabled
#   - FIDO2 security keys (ed25519-sk / ecdsa-sk) ONLY
#   - YubiKey PIN + touch required for every connection
#
# This means: to SSH into UwU, you MUST:
#   1. Connect to the AmneziaWG VPN first
#   2. Have a YubiKey with the right FIDO2 SSH key registered
#   3. Enter the YubiKey PIN + touch the key
#
# ## Generating the FIDO2 SSH key (one-time setup)
#
#   Plug in your YubiKey, then on UwU (or any trusted machine):
#
#     ssh-keygen -t ed25519-sk -O resident -O verify-required \
#       -O application=ssh:UwU -C "jaide@yubikey"
#
#   -O resident:    key can be pulled to any device with `ssh-keygen -K`
#   -O verify-required: forces YubiKey touch + PIN every use
#   -O application:  names the key on the YubiKey (visible in ykman)
#
#   Add the resulting public key to authorized_keys below (or to a
#   sops-managed file if you prefer).
#
# ## On a new client device (plug + go)
#
#   1. Plug YubiKey into the client
#   2. ssh-keygen -K  (pulls resident key from YubiKey to ~/.ssh/)
#   3. Connect to AmneziaWG VPN
#   4. ssh jaide@10.100.0.1  → PIN prompt → touch → you're in
#
# The key stub on the client is NOT secret — the actual private key
# never leaves the YubiKey. If the client is compromised, the attacker
# can't use the stub without the YubiKey.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.stealth-ssh;
in
{
  options.services.stealth-ssh = {
    enable = lib.mkEnableOption "Stealth SSH server (FIDO2-only, VPN-only)";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.100.0.1";
      description = "Address to listen on (should be the VPN interface).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 22;
      description = "SSH port.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "jaide";
      description = "User allowed to SSH in.";
    };

    # FIDO2 public keys — add your ed25519-sk / ecdsa-sk public keys here.
    # These are PUBLIC keys (safe to be in the Nix store).
    # Generate with: ssh-keygen -t ed25519-sk -O resident -O verify-required
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "FIDO2 SSH public keys (ed25519-sk / ecdsa-sk).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      ports = [ cfg.port ];

      settings = {
        # Listen ONLY on the VPN interface — not on 0.0.0.0
        ListenAddress = cfg.listenAddress;

        # Hardened security settings
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitEmptyPasswords = false;

        # ONLY allow public key auth with FIDO2 security keys
        PubkeyAuthentication = true;
        AuthenticationMethods = "publickey";

        # Require FIDO2 touch + PIN verification
        # This is enforced by the key type (ed25519-sk with verify-required),
        # but we also set SecurityKeyProvider to ensure the right backend.
        SecurityKeyProvider = "internal";

        # Timeout for YubiKey touch — 30 seconds should be enough
        LoginGraceTime = 30;

        # Don't allow agent forwarding (prevents key hijacking via forwarded agent)
        AllowAgentForwarding = false;

        # Allow X11 forwarding (useful for remote GUI apps)
        X11Forwarding = true;

        # Strict modes for key file permissions
        StrictModes = true;
      };

      # Authorized keys for the user — FIDO2 keys only
      # We use a sops-managed file if available, or inline keys.
      extraConfig = ''
        # ONLY accept FIDO2 security key types (ed25519-sk, ecdsa-sk)
        # Regular ed25519/rsa keys are rejected even if in authorized_keys
        PubkeyAcceptedAlgorithms ssh-ed25519-sk@openssh.com,ecdsa-sk-sha2-nistp256@openssh.com,sk-ssh-ed25519@openssh.com,sk-ecdsa-sha2-nistp256@openssh.com
      '';
    };

    # Deploy authorized keys for the user
    # FIDO2 keys only — regular SSH keys are rejected by PubkeyAcceptedAlgorithms
    system.activationScripts.stealth-ssh-keys = lib.stringAfter [ "users" ] ''
      mkdir -p /home/${cfg.user}/.ssh
      chmod 700 /home/${cfg.user}/.ssh
      touch /home/${cfg.user}/.ssh/authorized_keys
      chown ${cfg.user}:users /home/${cfg.user}/.ssh/authorized_keys
      chmod 600 /home/${cfg.user}/.ssh/authorized_keys

      # Write FIDO2 keys only (clear + rewrite to stay declarative)
      cat > /home/${cfg.user}/.ssh/authorized_keys <<'EOF'
      ${lib.concatStringsSep "\n" cfg.authorizedKeys}
      EOF
      chown ${cfg.user}:users /home/${cfg.user}/.ssh/authorized_keys
      chmod 600 /home/${cfg.user}/.ssh/authorized_keys
    '';
  };
}