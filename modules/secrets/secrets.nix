# Declarative secrets management via sops-nix + age.
#
# ## Architecture
#
# Two layers of keys:
#
# 1. HOST KEY (per-machine, on disk)
#    - A plain age key at /var/lib/sops-nix/key.txt
#    - Generated automatically on first activation (age.generateKey = true)
#    - Used by the SYSTEM to decrypt secrets at activation time
#    - The public key goes in .sops.yaml (in nixos-secrets repo) so secrets
#      are encrypted to each host
#
# 2. USER KEY (YubiKey-backed, via age-plugin-yubikey)
#    - An age identity stored on the YubiKey's PIV applet
#    - Used by YOU to encrypt/edit secrets from your workstation
#    - The private key NEVER touches disk — it lives on the YubiKey
#    - The public key goes in .sops.yaml (in nixos-secrets repo) as a recipient
#
# ## Secret storage
#
# Encrypted secrets live in a SEPARATE PRIVATE repo:
#   github.com/JaideAirblade/nixos-secrets (PRIVATE)
# This is defense-in-depth: even though age encryption protects the secrets,
# keeping them out of the public config repo means an attacker who harvests
# the public repo gets nothing. The nixos-secrets repo is pulled as a flake
# input (git+ssh:// with a deploy key).
#
# ## Setup (first time)
#
#   1. Generate a YubiKey-backed age identity (once per key):
#        age-plugin-yubikey -g
#      (touch the YubiKey when prompted; note the public key it prints,
#       e.g. age1yubikey1q...)
#      Repeat for each of your 3 YubiKeys if you want redundancy.
#      Add the public keys to nixos-secrets/.sops.yaml under keys:
#
#   2. Deploy this config to the host:
#        just deploy   (or sudo nixos-rebuild switch --flake .#hostname)
#      On first activation, sops-nix auto-generates the host age key at
#      /var/lib/sops-nix/key.txt.
#
#   3. Get the host's public age key:
#        sudo age-keygen -y /var/lib/sops-nix/key.txt
#      (prints age1...)
#      Add it to nixos-secrets/.sops.yaml under keys: as &host_<hostname>
#
#   4. Create your first secret:
#        cd ~/nixos-secrets   (clone the secrets repo if you haven't)
#        sops secrets/UwU/secrets.yaml
#      (SOPS opens your $EDITOR with the YAML; add keys like `my_secret: value`,
#       save & quit — it re-encrypts automatically)
#      Push the encrypted file to the secrets repo.
#
#   5. Reference it in a NixOS module:
#        sops.secrets.my_secret = { };
#      (the secret appears at /run/secrets/my_secret)
#
# ## Adding a new host
#
#   1. Deploy this module to the new host (auto-generates host key).
#   2. Get its public key: sudo age-keygen -y /var/lib/sops-nix/key.txt
#   3. Add it to nixos-secrets/.sops.yaml as &host_<hostname>.
#   4. Re-encrypt secrets: cd ~/nixos-secrets && sops updatekeys secrets/<host>/secrets.yaml
#
# ## age-plugin-yubikey setup
#
#   age-plugin-yubikey stores age identities in the YubiKey's PIV applet
#   (slot 2 by default, which is the same slot used by PIV smart-card logon).
#   It requires pcscd (smart card daemon) to communicate with the YubiKey.
#
#   To list existing YubiKey age identities:
#     age-plugin-yubikey -l
#
#   To use a YubiKey identity with sops, the plugin is auto-discovered if
#   age-plugin-yubikey is in PATH and the identity is in the YubiKey.
{ pkgs, inputs, ... }:

{
  # Import the sops-nix NixOS module
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  # ── Smart card daemon (pcscd) ───────────────────────────────────────
  # Required for age-plugin-yubikey to talk to the YubiKey's PIV applet.
  # Also needed by yubikey-manager (ykman) for PIV operations.
  services.pcscd.enable = true;

  # ── sops-nix configuration ──────────────────────────────────────────
  sops = {
    # Use age (not GPG) for encryption
    age = {
      # The host's age key — auto-generated on first activation
      keyFile = "/var/lib/sops-nix/key.txt";
      # Generate the key automatically if it doesn't exist yet
      generateKey = true;
      # Include age-plugin-yubikey in the age plugin path so the system
      # can use YubiKey identities for decryption if needed
      plugins = [ pkgs.age-plugin-yubikey ];
    };

    # Default secrets file — points to the nixos-secrets flake input.
    # The root secrets.yaml is for shared secrets. Per-host secrets
    # live in secrets/<hostname>/secrets.yaml (override per-secret with
    # sops.secrets.<name>.sopsFile).
    defaultSopsFile = "${inputs.nixos-secrets}/secrets.yaml";

    # Default format
    defaultSopsFormat = "yaml";

    # Test secret — verifies the full pipeline works end to end.
    # Available at /run/secrets/test_secret after rebuild.
    secrets.test_secret = { };
  };

  # ── CLI tools for managing secrets ──────────────────────────────────
  environment.systemPackages = [
    pkgs.sops                 # SOPS CLI — encrypt/edit/decrypt secrets
    pkgs.age                  # age CLI — key generation, manual encrypt/decrypt
    pkgs.age-plugin-yubikey  # YubiKey-backed age identities
    pkgs.yubikey-manager     # ykman CLI — PIV/OTP/FIDO management
  ];
}