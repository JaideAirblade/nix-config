# Dashboard hub: Homepage Dashboard + Grafana + Netdata on UwU-Server.
#
# All three bind to 0.0.0.0 but the firewall restricts access to the
# Tailscale interface only -- same pattern as Hermes WebUI on port 8080.
#
# Ports:
#   3002  - Homepage Dashboard (the hub)
#   3030  - Grafana (metrics dashboards)
#   19999 - Netdata (real-time perf monitoring)
#
# Homepage Dashboard is configured declaratively with links to all
# services running on UwU-Server, plus live widgets where supported.
_:
{
  nixos.hosts."UwU-Server" =
    { lib, ... }:

    let
      tsIP = "100.102.183.94";
    in
    {
      # --- Homepage Dashboard ------------------------------------------------
      services.homepage-dashboard = {
        enable = true;
        listenPort = 3002;
        openFirewall = false;
        settings = {
          title = "UwU-Server";
          description = "Server dashboard";
          background = "https://images.unsplash.com/photo-1558494949-efc1e4c4d4c4?w=1920";
        };
        # Service links -- each entry shows up as a card on the dashboard.
        services = [
          {
            name = "AdGuard Home";
            description = "DNS ad/tracker blocking";
            group = "Network";
            url = "http://${tsIP}:3000";
            icon = "adguard-home.png";
          }
          {
            name = "Hermes WebUI";
            description = "Hermes Agent chat interface";
            group = "AI";
            url = "http://${tsIP}:8080";
            icon = "hermes.png";
          }
          {
            name = "Hermes Gateway";
            description = "Messaging gateway (Telegram/Discord/etc)";
            group = "AI";
            url = "http://${tsIP}:8642";
          }
          {
            name = "Hermes Bridge Dashboard";
            description = "Mobile bridge dashboard";
            group = "AI";
            url = "http://${tsIP}:9119";
          }
          {
            name = "Grafana";
            description = "Metrics & dashboards";
            group = "Monitoring";
            url = "http://${tsIP}:3030";
            icon = "grafana.png";
          }
          {
            name = "Netdata";
            description = "Real-time performance monitoring";
            group = "Monitoring";
            url = "http://${tsIP}:19999";
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
        widgets = [
          {
            name = "System Resources";
            type = "glances";
            group = "Monitoring";
            url = "http://${tsIP}:19999";
          }
        ];
      };

      # --- Grafana -----------------------------------------------------------
      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_addr = "0.0.0.0";
            http_port = 3030;
            domain = tsIP;
          };
          security = {
            # Required since NixOS 26.05 -- no default secret key.
            secret_key = "XJ9QtUvgMkxMHTWS+BE3oTl0892utrfWZ3MRAovrUdw=";
          };
          # Disable signup -- tailnet-only access, single user.
          "auth.anonymous" = {
            enabled = true;
            org_role = "Admin";
          };
        };
      };

      # --- Netdata -----------------------------------------------------------
      services.netdata = {
        enable = true;
        config = {
          global = {
            "bind to" = "0.0.0.0:19999";
            "memory mode" = "ram";
            "history" = 86400;
          };
          web = {
            "web files owner" = "root";
            "web files group" = "root";
          };
        };
      };

      # --- Firewall: open all three on tailnet ------------------------------
      networking.firewall.interfaces.tailscale0.allowedTCPPorts =
        lib.mkAfter [ 3002 3030 19999 ];
    }
  ;
}