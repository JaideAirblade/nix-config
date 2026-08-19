# Paperless-ngx: document scanning, indexing, and archive.
#
# Runs on Luna-Server behind nginx at paperless.jaidechan.moe.
# Uses built-in Tesseract OCR (German + English) for document text extraction.
# Data is stored in /var/lib/paperless on the root pool.
#
# The admin password is set via a sops secret. First-time setup creates
# the database and document index automatically.
#
# Paperless needs a secret key for Django session signing. We generate
# one and store it in sops.
{
  inputs, lib, ... }:
{
  nixos.hosts."Luna-Server" =
    { config, ... }:

    let
      domain = "jaidechan.moe";
    in
    {
      # --- Paperless-ngx --------------------------------------------------
      services.paperless = {
        enable = true;

        # Bind to loopback -- nginx proxies to it.
        address = "127.0.0.1";
        port = 28981;

        # Data directories on the root pool.
        dataDir = "/var/lib/paperless";
        mediaDir = "/var/lib/paperless/media";
        consumptionDir = "/var/lib/paperless/consume";

        # Domain for nginx configuration (we manage nginx ourselves).
        domain = "paperless.${domain}";

        # Don't let paperless configure nginx -- we do it in dashboard.nix.
        configureNginx = false;

        # Admin password file (sops secret).
        passwordFile = config.sops.secrets.paperless_admin_password.path;

        # Extra configuration.
        settings = {
          # OCR languages: German + English (Tesseract).
          PAPERLESS_OCR_LANGUAGE = "deu+eng";
          # Date format for display.
          PAPERLESS_DATE_ORDER = "DMY";
          # Number of consumer workers (parallel document processing).
          PAPERLESS_CONSUMER_POLLING = "5";
          PAPERLESS_CONSUMER_POLLING_RETRY_COUNT = 3;
          # Timezone.
          PAPERLESS_TIME_ZONE = "Europe/Berlin";
          # Enable barcode recognition for document splitting.
          PAPERLESS_CONSUMER_ENABLE_BARCODES = true;
          # Trash retention (days) -- keep deleted docs for 30 days.
          PAPERLESS_TRASH_DIR_TIMEOUT = 30;
          # Number of days to keep documents in the trash.
          PAPERLESS_FILENAME_DATE_ORDER = "DMY";
        };
      };

      # --- Sops secret for paperless admin password -----------------------
      sops.secrets.paperless_admin_password = {
        sopsFile = "${inputs.nixos-secrets}/secrets/Luna-Server/paperless.yaml";
        key = "admin_password";
        owner = "paperless";
        mode = "0400";
      };

      # --- Nginx reverse proxy for paperless ------------------------------
      services.nginx.virtualHosts."paperless.${domain}" = {
        useACMEHost = domain;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:28981";
          proxyWebsockets = true;
          # Paperless uploads can be large (PDFs, scans).
          extraConfig = ''
            client_max_body_size 100m;
            proxy_read_timeout 120s;
            proxy_send_timeout 120s;
          '';
        };
      };

      # Open port 28981 on loopback only (nginx proxies).
      # No firewall change needed -- it's loopback.

      # --- Glance: add paperless to monitor and bookmarks -----------------
      services.glance.settings.pages = lib.mkAfter [
        {
          name = "Paperless";
          columns = [
            {
              size = "full";
              widgets = [
                {
                  type = "monitor";
                  title = "Document Management";
                  sites = [
                    { title = "Paperless-ngx"; url = "https://paperless.${domain}"; icon = "si:paperless-ngx"; alt-status-codes = [ 302 ]; }
                  ];
                }
              ];
            }
          ];
        }
      ];
    }
  ;
}