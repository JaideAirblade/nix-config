# GNOME Keyring — provides org.freedesktop.secrets for apps that want a
# secret store but aren't 1Password (Firefox saved logins, NetworkManager
# Wi-Fi passwords, git credential helpers, various GTK apps).
#
# 1Password manages its own vault and SSH/git-signing keys; it does NOT
# expose the org.freedesktop.secrets DBus interface that the rest of the
# desktop expects, so those apps fall back to storing secrets in plaintext
# or prompting every launch. GNOME Keyring fills that gap.
#
# Auto-unlock: greetd (run by DankGreeter) is the login PAM service here,
# so we enable the gnome-keyring PAM module on greetd. On a correct login
# the keyring unlocks with the login password — no separate prompt.
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

    # Unlock the keyring at login via greetd's PAM stack.
    security.pam.services.greetd.enableGnomeKeyring = true;

    # Export SSH_AUTH_SOCK to all login shells so git signing / ssh
    # push work in terminals. The GCR agent socket path is stable.
    environment.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/gcr/ssh";
  };
}
