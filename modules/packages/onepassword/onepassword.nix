# 1Password — password manager (GUI + CLI).
#
# Uses the NixOS modules (programs._1password / programs._1password-gui)
# rather than bare environment.systemPackages so that:
#   - browser native-messaging hosts are auto-wired for Firefox/Chrome/Brave
#     (the extension unlocks when the desktop app is unlocked), and
#   - polkit policy is installed so system-authentication unlock (fingerprint
#     / login password) works.
#
# Prerequisites already satisfied elsewhere in this config:
#   - nixpkgs.config.allowUnfree = true  (modules/nix/nix.nix)
#   - security.polkit.enable = true      (modules/wm/dms/dms.nix — DMS ships
#     its own polkit agent, which 1Password's system-auth prompt talks to)
#   - programs.firefox.enable = true     (modules/packages/packages.nix —
#     browser extension unlocking is auto-configured for Firefox)
#
# polkitPolicyOwners lists jaide so the 1Password polkit rules grant the
# user the right to use system-auth unlock. SSH-key management and git
# commit signing via 1Password are per-user concerns and are intentionally
# NOT configured here — the user owns ~/.ssh/config and ~/.gitconfig.
#
# --- Helium browser integration ---
#
# Two things are needed for the 1Password extension to work in Helium:
#
# 1. Native-messaging manifest:
#    The 1Password desktop app writes native-messaging manifests at runtime
#    into ~/.config/<browser>/NativeMessagingHosts/ for a hardcoded list of
#    known browsers (chromium, google-chrome, Brave, vivaldi, …).  Helium
#    (helium-bin) is a Chromium-based browser that uses the non-standard
#    config directory name "net.imput.helium", which 1Password does not know
#    about — so it never creates the manifest there and the extension cannot
#    connect.  We declare the manifest in the nix store and symlink it into
#    Helium's NativeMessagingHosts directory via systemd.user.tmpfiles.rules
#    (the same pattern used for the NymVPN desktop entry in
#    hosts/UwU/packages/packages.nix).
#
# 2. Browser allowlist:
#    1Password's BrowserSupport binary verifies the calling browser's
#    executable path (/proc/$PPID/exe) against a hardcoded list of known
#    browsers and rejects anything not on it ("UnknownBrowser" error).
#    It reads a custom allowlist from /etc/1password/custom_allowed_browsers
#    (one glob pattern per line, owned by root:root with 0755 perms — the
#    binary refuses the file otherwise).  We add a glob that matches the
#    version-specific nix store path so it survives Helium updates.
#
# Both items are harmless on hosts without Helium.
_:
{
  nixos.modules.common =
    { pkgs, ... }:
    let
      # Native-messaging host manifest for the 1Password browser extension.
      # The path points to the setgid wrapper created by programs._1password-gui
      # (security.wrappers."1Password-BrowserSupport" → /run/wrappers/bin/…).
      # allowed_origins lists every official 1Password Chrome extension ID
      # (stable, beta, dev, nightly, …) so any channel can connect.
      onepasswordManifest = pkgs.writeText
        "com.1password.1password.json"
        (builtins.toJSON {
          name = "com.1password.1password";
          description = "1Password BrowserSupport";
          path = "/run/wrappers/bin/1Password-BrowserSupport";
          type = "stdio";
          allowed_origins = [
            "chrome-extension://hjlinigoblmkhjejkmbegnoaljkphmgo/"
            "chrome-extension://bkpbhnjcbehoklfkljkkbbmipaphipgl/"
            "chrome-extension://gejiddohjgogedgjnonbofjigllpkmbf/"
            "chrome-extension://khgocmkkpikpnmmkgmdnfckapcdkgfaf/"
            "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
            "chrome-extension://dppgmdbiimibapkepcbdbmkaabgiofem/"
          ];
        });
    in
    {
      programs._1password.enable = true;

      programs._1password-gui = {
        enable = true;
        polkitPolicyOwners = [ "jaide" ];
      };

      # Symlink the 1Password native-messaging manifest into Helium's config
      # directory so the browser extension can reach the BrowserSupport wrapper.
      systemd.user.tmpfiles.rules = [
        "d %h/.config/net.imput.helium/NativeMessagingHosts 0700 - - -"
        "L+ %h/.config/net.imput.helium/NativeMessagingHosts/com.1password.1password.json - - - - ${onepasswordManifest}"
      ];

      # 1Password's BrowserSupport binary rejects any browser not on its
      # hardcoded allowlist.  It reads additional browser names from this file
      # (one per line, matched against the binary basename of /proc/$PPID/exe)
      # and accepts browsers matching any of them.  The binary requires a
      # regular file owned by root:root with mode 0755 — it refuses symlinks
      # and files writable by non-root.  We use environment.etc with
      # mode="0755" (not the default "symlink") so NixOS copies the file into
      # /etc rather than symlinking to the nix store.  The basename "helium"
      # is stable across package updates, unlike the version-specific nix
      # store path.
      # See: https://wiki.nixos.org/wiki/1Password#Unlocking_browser_extensions
      environment.etc."1password/custom_allowed_browsers" = {
        text = ''
          helium
        '';
        mode = "0755";
      };
    }
  ;
}
