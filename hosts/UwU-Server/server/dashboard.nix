# Dashboard hub: nginx reverse proxy + Homepage Dashboard + Grafana + Netdata.
#
# All services are behind nginx on jaidechan.moe with SSL via Let's Encrypt
# (DNS-01 challenge via Porkbun API). The nginx reverse proxy routes by
# subdomain:
#
#   jaidechan.moe          -> Homepage Dashboard (port 3002)
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
# Access: nginx listens on the Tailscale IP only (100.102.183.94:443).
# All services bind to 127.0.0.1 (loopback) -- only nginx exposes them.
{
  inputs, lib, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, lib, ... }:

    let
      tsIP = "100.102.183.94";
      domain = "jaidechan.moe";
    in
    {
      # --- Sops secrets for Porkbun API ------------------------------------
      sops.secrets.porkbun_api_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/UwU-Server/porkbun.yaml";
        key = "porkbun_api_key";
      };
      sops.secrets.porkbun_secret_key = {
        sopsFile = "${inputs.nixos-secrets}/secrets/UwU-Server/porkbun.yaml";
        key = "porkbun_secret_key";
      };

      # Render the environment file for lego's Porkbun DNS provider.
      # Lego expects PORKBUN_API_KEY and PORKBUN_SECRET_API_KEY in the env.
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
          # Also include the bare domain.
          extraDomainNames = [ domain ];
          dnsProvider = "porkbun";
          # Lego reads Porkbun credentials from this environment file.
          environmentFile = config.sops.templates.porkbun-env.path;
          # Wait for DNS propagation before requesting the cert.
          dnsPropagationCheck = true;
          dnsResolver = "1.1.1.1:53";
          # Disable webroot -- using DNS-01 challenge instead.
          webroot = null;
          # Allow nginx to read the cert files.
          group = "nginx";
        };
      };

      # --- Nginx reverse proxy --------------------------------------------
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        # Only listen on the Tailscale IP -- not 0.0.0.0, not the LAN.
        defaultListenAddresses = [ tsIP ];

        # Main domain -> Homepage Dashboard
        virtualHosts.${domain} = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3002";
          };
        };

        # AdGuard Home web UI
        virtualHosts."adguard.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3000";
          };
        };

        # Grafana
        virtualHosts."grafana.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:3030";
            # Grafana needs WebSocket support for live dashboards.
            proxyWebsockets = true;
          };
        };

        # Netdata
        virtualHosts."netdata.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:19999";
            proxyWebsockets = true;
          };
        };

        # Hermes WebUI
        virtualHosts."hermes.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:8080";
            proxyWebsockets = true;
          };
        };

        # Hermes Gateway (OpenAI-compatible API)
        virtualHosts."gateway.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:8642";
            proxyWebsockets = true;
          };
        };

        # Hermes Bridge Dashboard
        virtualHosts."bridge.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:9119";
          };
        };
      };

      # Open port 443 on the tailnet interface for nginx.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts =
        lib.mkAfter [ 443 ];

      # --- Homepage Dashboard (binds to loopback, nginx proxies) ----------
      services.homepage-dashboard = {
        enable = true;
        listenPort = 3002;
        openFirewall = false;
        allowedHosts = domain;
        settings = {
          title = "UwU-Server";
          description = "Server dashboard";
        };
        services = [
          {
            name = "AdGuard Home";
            description = "DNS ad/tracker blocking";
            group = "Network";
            url = "https://adguard.${domain}";
            icon = "adguard-home.png";
          }
          {
            name = "Hermes WebUI";
            description = "Hermes Agent chat interface";
            group = "AI";
            url = "https://hermes.${domain}";
            icon = "hermes.png";
          }
          {
            name = "Hermes Gateway";
            description = "Messaging gateway (Telegram/Discord/etc)";
            group = "AI";
            url = "https://gateway.${domain}";
          }
          {
            name = "Hermes Bridge Dashboard";
            description = "Mobile bridge dashboard";
            group = "AI";
            url = "https://bridge.${domain}";
          }
          {
            name = "Grafana";
            description = "Metrics & dashboards";
            group = "Monitoring";
            url = "https://grafana.${domain}";
            icon = "grafana.png";
          }
          {
            name = "Netdata";
            description = "Real-time performance monitoring";
            group = "Monitoring";
            url = "https://netdata.${domain}";
            icon = "netdata.png";
          }
          {
            name = "llama-server (Nemotron)";
            description = "Local LLM inference";
            group = "AI";
            url = "http://${tsIP}:9001";
          }
          {
            name = "Embedding server";
            description = "Text embeddings";
            group = "AI";
            url = "http://${tsIP}:9002";
          }
        ];
        bookmarks = [
          {
            name = "GitHub";
            url = "https://github.com/JaideAirblade";
            icon = "github.png";
          }
          {
            name = "Tailscale Admin";
            url = "https://login.tailscale.com/admin/machines";
            icon = "tailscale.png";
          }
          {
            name = "NixOS Search";
            url = "https://search.nixos.org/packages";
            icon = "nixos.png";
          }
        ];
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