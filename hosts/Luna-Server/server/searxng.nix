# SearXNG — self-hosted, privacy-respecting metasearch engine.
#
# Runs on Luna-Server behind nginx at search.jaidechan.moe.
# Exposed only on the Netbird IP (100.77.228.137) like all other services
# here — not a public instance.
#
# Why SearXNG here, separate from groktocrawl's slopsearx:
#   * groktocrawl's `slopsearx` Docker container is API-only (no UI) and is
#     scoped to the agent's research loop.
#   * This SearXNG instance is the human-facing one — full UI, all engines,
#     rate limiting, real search preferences.
#   * Both speak the SearXNG JSON API contract, so clients don't care.
#
# Why `configureUwsgi = true` and `configureNginx = false`:
#   * uWSGI mode is what the upstream module recommends for any non-trivial
#     instance (built-in HTTP server logs every query by default — see
#     `nixos/modules/services/networking/searx.nix` warning at line ~230).
#   * We configure nginx ourselves in dashboard.nix to keep all virtual
#     hosts in one place; the upstream `configureNginx` path would try to
#     add a second competing vhost.
#
# Secret: SEARXNG_SECRET is the only secret. It's referenced from the
# settings YAML via `$SEARXNG_SECRET` — the module's `searx-init.service`
# runs envsubst against the staged environment file at boot to substitute
# it before uWSGI loads settings.yml. The plain key never touches the
# Nix store.
#
# Engines: disabled everything that needs an API key without supplying one,
# kept what works key-less out of the box. To enable a paid engine, add its
# key to the appropriate secret and uncomment the relevant line in `.engines`.
{
  inputs, lib, ... }:
{
  nixos.hosts."Luna-Server" =
    { config, pkgs, ... }:

    let
      domain = "jaidechan.moe";
      searxHome = "search.${domain}";
    in
    {
      # --- SearXNG core --------------------------------------------------
      services.searx = {
        enable = true;
        # package defaults to pkgs.searxng; we don't override it.

        # Run via uwsgi — required for any non-trivial instance. nginx is
        # configured by us (below); disable the module's nginx path.
        configureUwsgi = true;
        configureNginx = false;

        # Local redis (served by nixpkgs as a unix socket) for rate limiting
        # and bot detection. Without this, `server.limiter = true` is a no-op.
        redisCreateLocally = true;

        # uwsgi vassal config. The module wires this into `services.uwsgi`
        # for us. We just need to listen on a unix socket (the default).
        uwsgiConfig = {
          socket = "/run/searx/uwsgi.sock";
          chmod-socket = "660";
          # Disable uwsgi's request logging — SearXNG has its own logger
          # and the upstream warning about built-in HTTP query logging is
          # exactly the privacy failure this avoids.
          disable-logging = true;
        };

        # Secret injection. The `searx-secret-init.service` oneshot
        # (defined below) writes a `SEARXNG_SECRET=<value>` line to this
        # EnvironmentFile at every boot; systemd loads it into the
        # searx-init service's environment; envsubst then substitutes
        # `$SEARXNG_SECRET` in the settings template at init time.
        environmentFile = "/run/secrets/rendered/searx-env";

        settings = {
          # Use nixpkgs' default settings.yml as the base; we override the
          # bits we care about.
          use_default_settings = true;

          general = {
            debug = false;
            instance_name = "Jaide's SearXNG";
            donation_url = false;
            contact_url = false;
            privacypolicy_url = false;
            enable_metrics = true;
          };

          ui = {
            static_use_hash = true;
            default_locale = "en";
            query_in_title = true;
            infinite_scroll = true;
            center_alignment = true;
            default_theme = "simple";
            theme_args.simple_style = "auto";
            search_on_category_select = true;
            hotkeys = "vim";
          };

          search = {
            # 0 = off, 1 = moderate, 2 = strict. Strict since this is a
            # personal instance and accidental NSFW results are annoying.
            safe_search = 1;
            autocomplete_min = 4;
            autocomplete = "google";
            ban_time_on_fail = 60;
            max_ban_time_on_fail = 86400;
            # Output formats SearXNG will accept. The NixOS freeform
            # settings merge REPLACES the default `formats` list with
            # `None` when you only specify some keys — so without this
            # explicit declaration, /search?format=json returns 403
            # ("output_format not in settings['search']['formats']").
            # Keep all five: html is what humans use, json is what
            # agents use, csv/rss/jsonlines are useful for scripting.
            formats = [ "html" "json" "csv" "rss" "jsonlines" ];
          };

          server = {
            # Bound to loopback — nginx fronts it via the Netbird IP.
            bind_address = "127.0.0.1";
            port = 8888;
            # base_url uses https because the vhost has forceSSL.
            base_url = "https://${searxHome}/";
            # The literal `$SEARXNG_SECRET` here is replaced by envsubst at
            # searx-init.service time, against the staged env file.
            secret_key = "$SEARXNG_SECRET";
            # Use POST method — keeps query strings out of nginx access logs
            # and out of browser history.
            method = "POST";
            # limiter=true activates rate limiting (needs the local redis).
            # NOTE: SearXNG's default limiter is aggressive and will ban
            # your own Netbird IP after a few quick requests during
            # debugging. With only ~1 user (you) hitting it, the limiter
            # adds nothing. Disable for now; re-enable if you ever expose
            # this externally.
            limiter = false;
            # Not a public instance. Anyone reaching it is on the mesh.
            public_instance = false;
            # Disable the image proxy — we don't need it, and it adds an
            # attack surface (SSRF via image URL fetching).
            image_proxy = false;
          };

          # --- Engines ---
          # IMPORTANT: SearXNG's settings.yml schema requires every
          # engine entry to have an `engine: <type>` field. When we set
          # only `disabled: true` here, the NixOS freeform merge
          # *replaces* the default entry (which has `engine: curlie` etc.)
          # with just `{disabled: true, name: curlie}`, which then fails
          # schema validation ("engine field is missing").
          #
          # So: only list engines we're ENABLING or weighting. Engines we
          # want OFF stay off via SearXNG's defaults (most key-less
          # defaults are already enabled; most API-key engines are
          # already disabled).
          engines = lib.mapAttrsToList (name: value: { inherit name; } // value) {
            # --- General web ---
            "duckduckgo"  = { disabled = true; };   # often rate-limits; unreliable
            "brave"       = { disabled = true; };   # needs API key
            "bing"        = { disabled = true; };   # needs API key
            "google"      = { disabled = true; };   # needs API key
            "qwant"       = { disabled = true; };   # often 403

            # --- Definitions / reference ---
            "wikipedia"      = { disabled = false; };
            "ddg definitions" = { disabled = false; weight = 2; };
            "wikibooks"      = { disabled = false; };
            "wikidata"       = { disabled = false; };
            "wikinews"       = { disabled = false; };
            "wikispecies"    = { disabled = false; weight = 0.5; };
            "wikiversity"    = { disabled = false; weight = 0.5; };
            "wikivoyage"     = { disabled = false; weight = 0.5; };

            # --- News ---
            "google news" = { disabled = true; };
            "brave.news"  = { disabled = true; };

            # --- Videos ---
            # Most video engines need instances we don't know about;
            # keep the defaults (mostly disabled).
            "vimeo"          = { disabled = true; };
            "dailymotion"    = { disabled = true; };

            # --- Images ---
            "google images"     = { disabled = true; };
            "bing images"       = { disabled = true; };
            "brave.images"      = { disabled = true; };
            "duckduckgo images" = { disabled = true; };
            "qwant images"      = { disabled = true; };
            "pinterest"         = { disabled = true; };
          };

          outgoing = {
            request_timeout = 5.0;
            max_request_timeout = 15.0;
            pool_connections = 100;
            pool_maxsize = 15;
            enable_http2 = true;
          };

          # Plugins worth keeping — small footprint, real utility.
          enabled_plugins = [
            "Basic Calculator"
            "Hash plugin"
            "Tor check plugin"
            "Open Access DOI rewrite"
            "Hostnames plugin"
            "Unit converter plugin"
            "Tracker URL remover"
            "Ahmia filter"           # filters known-bad onion results
            "Self Info"              # shows instance info / engine status
            "URL alt"                # dead-link alternatives
          ];

          # Don't auto-enable any plugin that needs network calls at boot.
          disabled_plugins = [
            "Searcharchiver"        # external archive.org — adds noise
          ];
        };
      };

      # --- Secret: SEARXNG_SECRET ---------------------------------------
      # This is a Flask SECRET_KEY for the local SearXNG instance. It is
      # generated once at first activation and persisted to /var/lib, so it
      # survives reboots and rebuilds (without it, every reboot resets user
      # sessions). It is intentionally NOT routed through sops because:
      #
      #   1. No third-party API key is involved — engines that need keys are
      #      explicitly disabled below.
      #   2. The value never leaves the host (only the local uwsgi process
      #      reads it via EnvironmentFile=).
      #   3. Avoiding sops here means the rebuild does not depend on a
      #      committed+encrypted secret in nixos-secrets, which is fragile.
      #
      # The searx NixOS module expects `environmentFile` at exactly this
      # path; the `searx-secret-init.service` oneshot below writes the
      # same `SEARXNG_SECRET=<value>` format that sops.templates would
      # have produced.
      systemd.services.searx-secret-init = {
        description = "Generate and stage SEARXNG_SECRET";
        wantedBy = [ "multi-user.target" ];
        before = [ "searx-init.service" ];
        # searx-init.service depends on (Requires=) this via the unit's
        # after/before graph below.
        requiredBy = [ "searx-init.service" ];
        unitConfig = {
          # Don't keep state; regenerate cleanly on every boot from the
          # persisted file (or generate once if missing).
          DefaultDependencies = false;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Run as root so we can write /var/lib and /run/secrets/*; the
          # resulting env file is 0440 root:searx — searx-init runs as
          # user searx and reads it via EnvironmentFile=.
          User = "root";
        };
        script = ''
          set -euo pipefail

          PERSIST_DIR=/var/lib/searxng
          PERSIST_FILE="$PERSIST_DIR/secret"
          ENV_FILE=/run/secrets/rendered/searx-env
          LIMITER_FILE=/run/searx/limiter.toml

          mkdir -p "$PERSIST_DIR"
          chmod 0750 "$PERSIST_DIR"

          if [ ! -s "$PERSIST_FILE" ]; then
            ${pkgs.python3}/bin/python3 -c \
              'import secrets; open("'"$PERSIST_FILE"'","w").write(secrets.token_urlsafe(48))'
            chmod 0640 "$PERSIST_FILE"
          fi

          SECRET=$(cat "$PERSIST_FILE")
          install -d -m 0755 -o root -g searx /run/secrets/rendered
          umask 0137
          printf 'SEARXNG_SECRET=%s\n' "$SECRET" > "$ENV_FILE"
          chown root:searx "$ENV_FILE"

          # Write an empty botdetection config so SearXNG doesn't reject
          # requests for "missing X-Forwarded-For nor X-Real-IP header"
          # when the upstream is uwsgi. uwsgi_param HTTP_X_FORWARDED_FOR
          # sets a WSGI environ var but SearXNG's botdetection middleware
          # reads request.headers (HTTP headers); the conversion isn't
          # guaranteed for arbitrary uwsgi params, and the loopback-
          # trusted-proxy check fails for unix-socket requests because
          # REMOTE_ADDR is empty. With this limiter.toml present, bot
          # detection is effectively no-op for any request that gets
          # through the limiter (and we set limiter=false in settings.yml
          # anyway, so this is belt-and-suspenders).
          #
          # The NixOS searx module only writes limiter.toml when
          # limiterSettings is non-empty, and the package's bundled TOML
          # enables botdetection by default. We override here.
          #
          # /run/searx is normally created by searx-init.service's
          # RuntimeDirectory=searx — but this unit runs Before=searx-init,
          # so the directory does not exist yet. Create it ourselves with
          # the same owner/mode the module would use (root:searx, 0750),
          # otherwise the cat below fails with "No such file or directory"
          # and the whole searx-init → uwsgi chain dependency-fails.
          install -d -m 0750 -o root -g searx /run/searx
          cat > "$LIMITER_FILE" <<'TOML'
          # Generated by searx-secret-init.service. See the NixOS module.
          # Empty botdetection table = no automated blocking. limiter is
          # also false in settings.yml.
          TOML
          chmod 0440 "$LIMITER_FILE"
          chown root:searx "$LIMITER_FILE"
        '';
      };
      # Make the existing searx-init.service wait on our generator.
      # sops-nix used to wire this transitively via `requiredBy`, but now
      # we have to spell it out.
      systemd.services.searx-init = {
        requires = [ "searx-secret-init.service" ];
        after = [ "searx-secret-init.service" ];
      };

      # --- nginx reverse proxy -----------------------------------------
      # SearXNG via uwsgi. We follow the same pattern as paperless/gitea:
      # useACMEHost reuses the *.jaidechan.moe wildcard cert that
      # dashboard.nix obtains via lego/Porkbun DNS-01.
      services.nginx.virtualHosts."${searxHome}" = {
        useACMEHost = domain;
        forceSSL = true;

        locations."/" = {
          # uwsgi_pass to the unix socket the vassal creates.
          # recommendedUwsgiSettings inserts `include uwsgi_params;` and
          # sets uwsgi-specific timeouts — exactly what we want.
          uwsgiPass = "unix:/run/searx/uwsgi.sock";
          recommendedUwsgiSettings = true;
          # POST means form-encoded queries — no query strings in URLs.
          # 4k is plenty for a query string; limit prevents abuse.
          #
          # Forward the client's real IP so SearXNG's botdetection
          # middleware can find it. uwsgi_param sets WSGI environ vars,
          # which Werkzeug exposes as `request.headers.get('X-Real-IP')`
          # and `request.headers.get('X-Forwarded-For')` — that's what
          # SearXNG reads. Without these, SearXNG logs
          # "X-Forwarded-For nor X-Real-IP header is set!" and returns
          # 403 on the JSON API (limiter=false in settings.yml, but
          # botdetection is separate). The upstream searx module adds
          # these via its `configureNginx=true` path; since we manage
          # nginx ourselves, we duplicate them here.
          extraConfig = ''
            client_max_body_size 4k;
            uwsgi_param HTTP_HOST $host;
            uwsgi_param HTTP_X_REAL_IP $remote_addr;
            uwsgi_param HTTP_X_FORWARDED_FOR $proxy_add_x_forwarded_for;
            uwsgi_param HTTP_X_FORWARDED_PROTO $scheme;
            uwsgi_param HTTP_X_FORWARDED_HOST $host;
          '';
        };

        # SearXNG serves its own static assets from /static.
        locations."/static/" = {
          alias = "${config.services.searx.package}/share/static/";
          extraConfig = ''
            # 1-day cache — static assets are content-hashed by SearXNG.
            expires 1d;
            add_header Cache-Control "public, immutable";
          '';
        };
      };

      # --- Glance: add SearXNG to bookmarks ----------------------------
      services.glance.settings.pages = lib.mkAfter [
        {
          name = "Search";
          columns = [
            {
              size = "full";
              widgets = [
                {
                  type = "bookmarks";
                  groups = [
                    {
                      title = "Search";
                      links = [
                        { title = "SearXNG"; url = "https://${searxHome}"; icon = "si:searxng"; }
                        { title = "NixOS Packages"; url = "https://search.nixos.org/packages"; icon = "si:nixos"; }
                        { title = "NixOS Options"; url = "https://search.nixos.org/options"; icon = "si:nixos"; }
                      ];
                    }
                  ];
                }
              ];
            }
          ];
        }
      ];

      # --- Systemd hardening ------------------------------------------
      # The nixpkgs module already hardens the searx service. We add one
      # extra: deny network access except to whitelisted engines via
      # firewall (we don't bother — engines are public, and the searx-init
      # service needs network to fetch favicons). Skip this.

      # --- Firewall -----------------------------------------------------
      # Don't open the firewall. SearXNG binds to 127.0.0.1; only nginx
      # (which listens on the Netbird IP only, per dashboard.nix) can
      # reach it. No `openFirewall = true` here.

      # --- nginx can talk to uwsgi --------------------------------------
      # The NixOS searx module normally adds `searx` to nginx's
      # supplementary groups via `systemd.services.nginx.serviceConfig` —
      # but only when `services.searx.configureNginx = true`. Since we
      # manage nginx in dashboard.nix, we have to do this ourselves,
      # otherwise nginx can't read /run/searx/uwsgi.sock (mode 660,
      # owner searx:searx) and we get a 502 Bad Gateway.
      users.users.nginx.extraGroups = [ "searx" ];

      # --- Optional: telemetry for monitoring --------------------------
      # The `enable_metrics = true` setting in general above exposes
      # Prometheus metrics on `/metrics` (same vhost). Grafana dashboard
      # could be added later — for now this is enough.
    }
  ;
}
