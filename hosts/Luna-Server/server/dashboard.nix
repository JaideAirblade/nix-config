# Dashboard hub: nginx reverse proxy + Glance + Grafana + Netdata.
#
# All services are behind nginx on jaidechan.moe with SSL via Let's Encrypt
# (DNS-01 challenge via Porkbun API). The nginx reverse proxy routes by
# subdomain:
#
#   jaidechan.moe          -> Glance dashboard (port 3002)
#   adguard.jaidechan.moe  -> AdGuard Home web UI (port 3000)
#   grafana.jaidechan.moe  -> Grafana (port 3030)
#   netdata.jaidechan.moe  -> Netdata (port 19999)
#   hermes.jaidechan.moe   -> Hermes WebUI (port 8080)
#   gateway.jaidechan.moe  -> Hermes Gateway (port 8642)
#   bridge.jaidechan.moe   -> Hermes Bridge Dashboard (port 9119)
#
# SSL: Let's Encrypt wildcard cert for *.jaidechan.moe via lego DNS-01
# with Porkbun DNS provider. The Porkbun API keys are in sops secrets.
# The cert auto-renews before expiry.
#
# Access: nginx listens on the Netbird IP only (100.77.228.137:443).
# All services bind to 127.0.0.1 (loopback) -- only nginx exposes them.
{
  inputs, lib, ... }:
{
  nixos.hosts."Luna-Server" =
    { config, lib, ... }:

    let
      nbIP = "100.77.228.137";
      domain = "jaidechan.moe";
    in
    {
      # --- Sops secrets for Porkbun API ------------------------------------
      sops.secrets.porkbun_api_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/Luna-Server/porkbun.yaml";
        key = "porkbun_api_key";
      };
      sops.secrets.porkbun_secret_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/Luna-Server/porkbun.yaml";
        key = "porkbun_secret_key";
      };

      sops.templates.porkbun-env = {
        content = ''
          PORKBUN_API_KEY=${config.sops.placeholder.porkbun_api_key}
          PORKBUN_SECRET_API_KEY=${config.sops.placeholder.porkbun_secret_key}
        '';
        owner = "acme";
        mode = "0400";
        restartUnits = [ "acme-${domain}.service" ];
      };

      # --- ACME: Let's Encrypt wildcard cert via DNS-01 (Porkbun) ----------
      security.acme = {
        acceptTerms = true;
        defaults.email = "jaide@jaidechan.moe";
        certs.${domain} = {
          domain = "*.${domain}";
          extraDomainNames = [ domain ];
          dnsProvider = "porkbun";
          environmentFile = config.sops.templates.porkbun-env.path;
          dnsPropagationCheck = true;
          dnsResolver = "1.1.1.1:53";
          webroot = null;
          group = "nginx";
          # When lego renews the wildcard cert, restart the services
          # that hold the cert in memory. nginx reloads cleanly; AdGuard
          # needs a full restart (DoT opens the cert file at startup,
          # there's no SIGHUP-style reload for it). try-reload-or-restart
          # is a no-op for adguardhome (no ExecReload) and falls through
          # to a restart — perfect.
          reloadServices = [ "nginx.service" "adguardhome.service" ];
          # Cert/key files readable by the `nginx` group (0640). The
          # acme module writes them 0400 acme:nginx on renewal; the
          # AdGuard service runs as the fixed `adguardhome` user with
          # `nginx` as a supplementary group (see direct-link.nix) and
          # needs to read these for the DoT listener on :853. 0640 =
          # owner rw, group r, world nothing — tightest mode that
          # lets both nginx and AdGuard do their jobs.
          postRun = "chmod 0640 /var/lib/acme/${domain}/fullchain.pem /var/lib/acme/${domain}/key.pem";
        };
      };

      # --- Nginx reverse proxy --------------------------------------------
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        defaultListenAddresses = [ nbIP ];

        virtualHosts.${domain} = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3002";
          };
        };

        virtualHosts."adguard.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3000";
          };
        };

        virtualHosts."grafana.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3030";
            proxyWebsockets = true;
          };
        };

        virtualHosts."netdata.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:19999";
            proxyWebsockets = true;
          };
        };

        virtualHosts."hermes.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:8080";
            proxyWebsockets = true;
          };
        };

        virtualHosts."gateway.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:8642";
            proxyWebsockets = true;
          };
        };

        virtualHosts."bridge.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:9119";
            proxyWebsockets = true;
          };
        };
      };

      networking.firewall.interfaces.wt0.allowedTCPPorts =
        lib.mkAfter [ 443 ];

      # --- Glance dashboard (replaces Homepage Dashboard) -------------------
      # Glance is a lightweight, customizable dashboard with widgets for
      # server stats, DNS stats (AdGuard Home), monitor (service uptime),
      # bookmarks, clock, calendar, RSS, weather, and more.
      services.glance = {
        enable = true;
        openFirewall = false;
        settings = {
          server = {
            host = "127.0.0.1";
            port = 3002;
            proxied = true;
          };
          theme = {
            background-color = "240 8 9";
            primary-color = "43 50 70";
            contrast-multiplier = 1.1;
          };
          branding = {
            app-name = "Luna-Server";
            hide-footer = true;
          };
          pages = [
            {
              name = "Home";
              columns = [
                {
                  size = "small";
                  widgets = [
                    {
                      type = "clock";
                      hour-format = "24h";
                      timezones = [
                        { timezone = "Europe/Berlin"; label = "Local"; }
                      ];
                    }
                    {
                      type = "server-stats";
                      servers = [
                        { type = "local"; name = "Luna-Server"; }
                      ];
                    }
                  ];
                }
                {
                  size = "full";
                  widgets = [
                    {
                      type = "monitor";
                      title = "Services";
                      sites = [
                        { title = "AdGuard Home"; url = "https://adguard.${domain}"; icon = "si:adguard"; }
                        { title = "Hermes WebUI"; url = "https://hermes.${domain}"; icon = "si:openai"; alt-status-codes = [ 501 ]; }
                        { title = "Hermes Gateway"; url = "https://gateway.${domain}"; alt-status-codes = [ 404 ]; }
                        { title = "Hermes Bridge"; url = "https://bridge.${domain}"; alt-status-codes = [ 302 ]; }
                        { title = "Grafana"; url = "https://grafana.${domain}"; icon = "si:grafana"; }
                        { title = "Netdata"; url = "https://netdata.${domain}"; icon = "si:netdata"; alt-status-codes = [ 400 404 ]; }
                        { title = "Paperless-ngx"; url = "https://paperless.${domain}"; icon = "si:paperless-ngx"; alt-status-codes = [ 302 ]; }
                        { title = "Gitea"; url = "https://git.${domain}"; icon = "si:gitea"; alt-status-codes = [ 302 ]; }
                      ];
                    }
                  ];
                }
                {
                  size = "small";
                  widgets = [
                    {
                      type = "bookmarks";
                      groups = [
                        {
                          title = "Admin";
                          links = [
                            { title = "Netbird"; url = "https://app.netbird.io"; icon = "si:netbird"; }
                            { title = "GitHub"; url = "https://github.com/JaideAirblade"; icon = "si:github"; }
                            { title = "NixOS Search"; url = "https://search.nixos.org/packages"; icon = "si:nixos"; }
                          ];
                        }
                        {
                          title = "AI";
                          links = [
                            { title = "llama-server"; url = "http://${nbIP}:9001"; }
                            { title = "Embeddings"; url = "http://${nbIP}:9002"; }
                          ];
                        }
                        {
                          title = "Services";
                          links = [
                            { title = "Paperless-ngx"; url = "https://paperless.${domain}"; icon = "si:paperless-ngx"; }
                            { title = "Gitea"; url = "https://git.${domain}"; icon = "si:gitea"; }
                          ];
                        }
                      ];
                    }
                    {
                      type = "calendar";
                      first-day-of-week = "monday";
                    }
                  ];
                }
              ];
            }
          ];
        };
      };

      # --- Grafana (binds to loopback, nginx proxies) ----------------------
      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_addr = "127.0.0.1";
            http_port = 3030;
            domain = "grafana.${domain}";
          };
          security = {
            secret_key = "XJ9QtUvgMkxMHTWS+BE3oTl0892utrfWZ3MRAovrUdw=";
          };
          "auth.anonymous" = {
            enabled = true;
            org_role = "Admin";
          };
        };
      };

      # --- Netdata (binds to loopback, nginx proxies) ----------------------
      services.netdata = {
        enable = true;
        config = {
          global = {
            "bind to" = "127.0.0.1:19999";
            "memory mode" = "ram";
            "history" = 86400;
          };
          web = {
            "web files owner" = "root";
            "web files group" = "root";
          };
        };
      };
    }
  ;
}