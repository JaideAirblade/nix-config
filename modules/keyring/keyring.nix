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
{ ... }:

{
  services.gnome.gnome-keyring.enable = true;

  # Unlock the keyring at login via greetd's PAM stack.
  security.pam.services.greetd.enableGnomeKeyring = true;
}