# GNOME Keyring — provides org.freedesktop.secrets for apps that want a
# secret store but aren't 1Password (Firefox saved logins, NetworkManager
# Wi-Fi passwords, git credential helpers, various GTK apps).
#
# 1Password manages its own vault and SSH/git-signing keys; it does NOT
# expose the org.freedesktop.secrets DBus interface that the rest of the
# desktop expects, so those apps fall back to storing secrets in plaintext
# or prompting every launch. GNOME Keyring fills that gap.
#
# Auto-unlock: the login display manager is the login PAM service here.
# The display manager varies by host:
#   - UwU: SDDM (from 2026-08-11, switching from greetd to host the
#     iNiR ii-pixel SDDM theme). SDDM runs `services.xserver.displayManager.sddm`
#     and nixpkgs wires gnome-keyring via `services.xserver.displayManager.sddm.enableGnomeKeyring`.
#   - TSBW-W01800 etc.: greetd (DankGreeter). The nixpkgs module exposes
#     `security.pam.services.greetd.enableGnomeKeyring` for that.
# We enable the SDDM-unlock path globally because the switch is recent
# and the option is a no-op on hosts that don't use SDDM. For greetd
# hosts, set `security.pam.services.greetd.enableGnomeKeyring = true`
# in the host's desktop file.
#
# SSH agent: enabling gnome-keyring also starts gcr-ssh-agent, a socket-
# activated systemd user unit that listens at $XDG_RUNTIME_DIR/gcr/ssh.
# The socket unit sets SSH_AUTH_SOCK in the *systemd user manager*
# environment, but that does NOT propagate to login shells (bash, etc.)
# which source /etc/set-environment instead. Without exporting it here,
# git SSH signing and ssh push fail with "Couldn't get agent socket"
# in any terminal that isn't launched by the user systemd manager.
_: {
  nixos.modules.common = _: {
    services.gnome.gnome-keyring.enable = true;

    # Unlock the keyring at login via SDDM's PAM stack. No-op on hosts
    # that don't use SDDM. Host-specific overrides (e.g. UwU) may also
    # toggle this. Greeter hosts should set the greetd equivalent in
    # their desktop module.
    security.pam.services.sddm.enableGnomeKeyring = true;

    # Unlock the keyring at login via greetd's PAM stack for hosts that
    # still use greetd (TSBW-W01800, etc.). Host files may override this
    # to false if they use a different greeter.
    security.pam.services.greetd.enableGnomeKeyring = true;

    # Export SSH_AUTH_SOCK to all login shells so git signing / ssh
    # push work in terminals. The GCR agent socket path is stable.
    environment.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/gcr/ssh";
  };
}
