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
{ pkgs, inputs, lib, ... }:

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

    # ── Secrets ──────────────────────────────────────────────────────

    # Test secret — verifies the full pipeline works end to end.
    secrets.test_secret = { };

    # GitHub SSH key — used for git push + signing.
    # Written to /run/secrets/ssh_key at activation, then symlinked
    # to ~/.ssh/id_ed25519 by the activation script below.
    secrets.ssh_key = {
      owner = "jaide";
      group = "users";
      mode = "0600";
    };
  };

  # ── Deploy SSH key from sops to ~/.ssh/ ──────────────────────────────
  # sops-nix writes secrets to /run/secrets/ (owned by root, tmpfs).
  # We symlink the SSH private key into jaide's ~/.ssh/ so git can use it.
  # The public key and ssh config are NOT secret — they go in the regular
  # NixOS config below.
  system.activationScripts.deploy-ssh-key = lib.stringAfter [ "setupSecrets" "users" ] ''
    if [ -f /run/secrets/ssh_key ]; then
      mkdir -p /home/jaide/.ssh
      chmod 700 /home/jaide/.ssh
      ln -sfn /run/secrets/ssh_key /home/jaide/.ssh/id_ed25519
      chown -h jaide:users /home/jaide/.ssh/id_ed25519
    fi
  '';

  # ── SSH config + known_hosts (not secret, in regular config) ───────
  # Declarative SSH config for GitHub. The private key comes from sops.
  environment.etc."ssh/ssh_known_hosts".text = ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
    github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
    github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
  '';

  # ── Git config: SSH for GitHub + signing ────────────────────────────
  # Switch from HTTPS (gh credential helper) to SSH for GitHub.
  # The private key comes from sops (deployed to ~/.ssh/id_ed25519 above).
  # Signing is done with the same SSH key.
  programs.git.config = {
    gpg.format = "ssh";
    commit.gpgsign = true;
    user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKozofCo3TsmA85edEMGsysfAkLf1/wWL3cv+DR0Ck04";
    # Use SSH instead of HTTPS for GitHub
    url."git@github.com:".insteadOf = "https://github.com/";
  };

  # ── CLI tools for managing secrets ──────────────────────────────────
  environment.systemPackages = [
    pkgs.sops                 # SOPS CLI — encrypt/edit/decrypt secrets
    pkgs.age                  # age CLI — key generation, manual encrypt/decrypt
    pkgs.age-plugin-yubikey  # YubiKey-backed age identities
    pkgs.yubikey-manager     # ykman CLI — PIV/OTP/FIDO management
  ];
}