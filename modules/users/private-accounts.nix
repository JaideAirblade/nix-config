# Account and authentication policy for the fleet's automation identity
# (Luna). Two role modules are exposed from this file:
#
#   automationAccounts — Luna's account + SSH keys + sudo rules. Imported
#     on every host where Luna operates (UwU, UwU-Server, TSBW-W01800,
#     OwO-Family, ...). Grants Luna the `jaide` supplementary group so
#     she can read /home/jaide and operate the nix-config repo on those
#     hosts. Does NOT touch pam_u2f or the sops password hash wiring.
#
#   privateAccounts — automationAccounts + SOPS unwrapped password hash
#     for the Jaide account + pam_u2f *option* wiring (enable = false
#     by default; hosts enable it via their security/yubikey.nix).
#     Imported only on Jaide's personal devices (UwU, UwU-Server)
#     because TSBW intentionally keeps its own yubikey.nix as the
#     authority on pam_u2f there.
#
# As of 2026-08-12 Luna is in the `jaide` supplementary group on every
# host that pulls automationAccounts. The /home/jaide homeMode is set
# to 0750 (in modules/users/users.nix) so the group can read; sensitive
# material in Jaide's home (ssh keys, sops age keys, gpg) should still
# be explicitly permissioned (0600) so group read is harmless if those
# files exist.
{ inputs, ... }:
let
  automationAccounts =
    { pkgs, ... }:
    let
      migrateLunaHome = pkgs.writeShellApplication {
        name = "migrate-luna-home";
        runtimeInputs = [ pkgs.coreutils pkgs.gnutar pkgs.rsync ];
        text = ''
          set -euo pipefail
          legacy=/var/lib/luna
          target=/home/luna
          backup=/var/backups/luna-home-before-standard-home.tar

          if [[ ! -d "$legacy" ]]; then
            printf 'no legacy Luna home to migrate\n'
            exit 0
          fi
          [[ ! -L "$legacy" && -d "$target" && ! -L "$target" ]] || {
            printf 'refusing unsafe Luna home migration: source or target is invalid\n' >&2
            exit 1
          }

          install -d -m 0700 /var/backups
          if [[ ! -e "$backup" ]]; then
            tar --acls --xattrs -cpf "$backup.tmp" -C /var/lib luna
            test -s "$backup.tmp"
            mv -- "$backup.tmp" "$backup"
          fi
          test -s "$backup"
          chmod 0600 "$backup"

          rsync -aHAX --numeric-ids "$legacy/" "$target/"
          chown -R luna:luna "$target"
          chmod 0700 "$target"
          pending=$(rsync -aHAXnc --numeric-ids --itemize-changes "$legacy/" "$target/")
          [[ -z "$pending" ]] || {
            printf 'Luna home verification failed:\n%s\n' "$pending" >&2
            exit 1
          }
          printf 'Luna home copied and verified; legacy Luna home retained for rollback: %s\n' "$legacy"
        '';
      };
    in
    {
      # Root stays unavailable for direct login. Luna elevates through the
      # account-scoped sudo rule so every remote action remains attributable.
      users.users.root.hashedPassword = "!";

      # Locked SSH-only automation identity. `restrict` blocks forwarding and
      # PTY allocation, but intentionally does not force a command: together
      # with Luna's account-scoped NOPASSWD ALL rule, this key is a deliberate
      # root-equivalent fleet credential for general automation.
      users.groups.luna = { };
      users.users."luna" = {
        isNormalUser = true;
        home = "/home/luna";
        createHome = true;
        homeMode = "0700";
        autoSubUidGidRange = false;
        description = "Luna automation agent";
        group = "luna";
        # `jaide` grants Luna read on /home/jaide (group-readable
        # homeMode is set in modules/users/users.nix). Kept in
        # automationAccounts (not privateAccounts) so it applies on
        # every host that pulls Luna's automation identity — including
        # TSBW-W01800, which intentionally does NOT pull
        # privateAccounts (that module disables pam_u2f, which TSBW
        # enables in its security/yubikey.nix).
        extraGroups = [ "wheel" "networkmanager" "jaide" ];
        shell = pkgs.bashInteractive;
        hashedPassword = "!";
        openssh.authorizedKeys.keys = [
          "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGumwUfMQeD3XItqgrKe9RBzj6w6FqtjnD8QKImskVoQ luna-agent@UwU"
          "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINU3saHF0DsvE0PkmQgU7sBlrfjol4R0BxaLRjZSPuRv luna-agent@UwU-Server"
        ];
      };

      security.sudo = {
        wheelNeedsPassword = true;
        extraRules = [
          {
            users = [ "luna" ];
            commands = [
              {
                command = "ALL";
                options = [ "NOPASSWD" ];
              }
            ];
          }
        ];
      };

      environment.systemPackages = [ migrateLunaHome ];

      # Declarative SSH config for Luna's fleet access. Every host
      # that imports `automationAccounts` gets this — covers GitHub,
      # the four netbird-mesh peers, and the per-host mesh DNS
      # workaround for hosts that can't route to the magic-DNS
      # suffix (none today, but the structure is here for parity
      # with the Tailscale-era layout documented in
      # skills/network/cross-host-ssh-setup/references/
      # declarative-user-ssh-config.md).
      #
      # The config renders to /etc/luna/ssh_config. Luna's
      # ~/.ssh/config is a systemd tmpfiles symlink into that path
      # (managed per-host by each host's users/users.nix), so the
      # rebuild-time file is the runtime config.
      environment.etc."luna/ssh_config".text = ''
        # GitHub — route through ssh.github.com:443 (port 22 often blocked).
        Host github.com
          HostName ssh.github.com
          Port 443
          User git
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new

        # Netbird mesh peers. The Host block carries the literal mesh
        # IP as HostName so the alias works without depending on the
        # netbird daemon's DNS resolver being reachable from the
        # calling host. HostKeyAlias keeps the known_hosts entry
        # under the human-readable hostname (so `ssh -o
        # HostKeyAlias=uwu` and `ssh -o HostKeyAlias=uwu-server` are
        # both happy when the IP changes on re-enrollment).
        Host uwu-server uwu-server.netbird.cloud
          HostName 100.77.228.137
          User luna
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          HostKeyAlias uwu-server

        Host uwu uwu.netbird.cloud
          HostName 100.77.119.175
          User luna
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          HostKeyAlias uwu

        Host tsbw tsbw-w01800 tsbw-w01800.netbird.cloud
          HostName 100.77.44.152
          User luna
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          HostKeyAlias tsbw-w01800

        # uwu-phone runs the Android netbird client only — no sshd.
        # The Host block is here so `ssh uwu-phone` errors with a
        # clear "Connection refused" rather than "Name or service
        # not known" when the netbird DNS forward is unreachable.
        Host uwu-phone uwu-phone.netbird.cloud
          HostName 100.77.152.164
          User luna
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          HostKeyAlias uwu-phone
      '';
    };
in
{
  nixos.modules.automationAccounts = automationAccounts;

  nixos.modules.privateAccounts =
    { config, pkgs, ... }:
    {
      imports = [ automationAccounts ];

      # Decrypt before the users activation stage. This keeps the password hash
      # out of both Git and the world-readable Nix store.
      sops.secrets.jaide_password_hash = {
        sopsFile = "${inputs.nixos-secrets}/secrets/private/accounts.yaml";
        neededForUsers = true;
      };

      # Enforce the SOPS hash on existing accounts as well as new installs.
      # Password rotation is declarative through set-private-password-hash.sh.
      users.mutableUsers = false;
      users.users.jaide.hashedPasswordFile =
        config.sops.secrets.jaide_password_hash.path;

      # A hardware key is an alternative for graphical/TTY login, not a second
      # factor and not a way to bypass Jaide's sudo password.
      security.pam.u2f = {
        enable = false;
        control = "sufficient";
        settings = {
          cue = true;
          origin = "pam://${config.networking.hostName}";
          appid = "pam://${config.networking.hostName}";
        };
      };
      security.pam.services = {
        greetd.u2f.enable = true;
        login.u2f.enable = true;
        sudo.u2f.enable = false;
      };

      environment.systemPackages = [ pkgs.pam_u2f ];
    }
  ;
}
