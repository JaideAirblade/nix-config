# Nix / nixpkgs settings: flakes, unfree, editor.
_:
{
  nixos.modules.common =
    { lib, ... }:

    {
      # mkDefault so a host can override (e.g. a minimal server that wants
      # unfree disabled) without needing mkForce.
      nixpkgs.config.allowUnfree = lib.mkDefault true;

      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      # We're fully on Flakes — no nix-channel. Disabling removes the channel
      # tools/config so nothing accidentally drifts the system off the flake.lock.
      nix.channel.enable = false;

      # Tarball + narinfo cache TTLs — "no more than once an hour on stuff
      # we already checked" (per user, 2026-08-20).
      #
      # Background: `nix flake update` was hitting GitHub's anonymous API
      # rate limit (60 req/h/IP) on the per-input "what's the latest
      # commit?" call (api.github.com/repos/.../commits/HEAD). The limit
      # hits long before the actual tarball download; the tarball itself
      # is cached by /nix/store and via the nix binary's tarball cache.
      # Bumping `tarball-ttl` and the narinfo caches means builds within
      # the TTL don't re-fetch from cache.nixos.org — fewer total
      # requests, fewer chances to hit the limit on the next input query.
      #
      #   tarball-ttl                 1h  ->  7d   (flake source tarballs)
      #   narinfo-cache-positive-ttl  30d  ->  30d  (already generous)
      #   narinfo-cache-negative-ttl   1h  ->  24h  (negative cache longer)
      #   narinfo-cache-meta-ttl      7d  ->  7d   (already generous)
      nix.settings = {
        tarball-ttl = 604800;             # 7d
        narinfo-cache-negative-ttl = 86400; # 24h
      };

      # GitHub Personal Access Token for `nix flake update`. Without a
      # token, nix falls back to GitHub's anonymous API and hits 60 req/h
      # per IP — easily exceeded by a 30-input flake. With a token, the
      # limit is 5000/h. The token comes from sops (see
      # modules/secrets/secrets.nix — sops.secrets.github_token); the
      # resolved value lands at /run/secrets/github_token at activation.
      # We then have sops write a fragment file /etc/nix/access-tokens.conf
      # containing the actual access-tokens line, and `include` it
      # from /etc/nix/nix.conf via nix.extraOptions. The fragment file
      # is mode 0440 root:nixbld so non-root nix commands (e.g. jaide
      # running nix flake update) can read it.
      nix.extraOptions = ''
        include /etc/nix/access-tokens.conf
      '';

      # Avoid pulling every package's optional HTML documentation output into
      # the system closure. In the pinned nixpkgs revision, Python 3.12's docs
      # also fail to build with the Python 3.14 Sphinx/docutils toolchain.
      # Man pages, Info pages, and the NixOS manual remain enabled.
      documentation.doc.enable = false;

      environment.variables.EDITOR = "vim";
    }
  ;
}
