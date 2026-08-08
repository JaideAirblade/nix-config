# Gitea: self-hosted Git service.
#
# Runs on UwU-Server behind nginx at git.jaidechan.moe.
# SSH git access via the host's SSH server (port 22, already open on tailscale0).
# SQLite database (sufficient for personal use).
# Registration disabled -- single user (jaide/luna).
#
# Repos stored in /var/lib/gitea/repositories.
{
  inputs, lib, ... }:
{
  nixos.hosts."UwU-Server" =
    { config, ... }:

    let
      domain = "jaidechan.moe";
    in
    {
      services.gitea = {
        enable = true;
        appName = "Jaide's Git";

        stateDir = "/var/lib/gitea";
        repositoryRoot = "/var/lib/gitea/repositories";

        database = {
          type = "sqlite3";
        };

        settings = {
          server = {
            HTTP_ADDR = "127.0.0.1";
            HTTP_PORT = 3001;
            DOMAIN = "git.${domain}";
            ROOT_URL = "https://git.${domain}/";
            # SSH is handled by the host's openssh, not gitea's built-in.
            DISABLE_SSH = false;
            SSH_DOMAIN = domain;
            SSH_PORT = 22;
            START_SSH_SERVER = false;
          };
          service = {
            DISABLE_REGISTRATION = true;
            REQUIRE_SIGNIN_VIEW = true;
          };
          security = {
            INSTALLATION_PASSWORD = config.sops.secrets.gitea_internal_token.path;
          };
          other = {
            SHOW_FOOTER_VERSION = false;
            SHOW_FOOTER_TEMPLATE_LOAD_TIME = false;
          };
        };
      };

      # --- Sops secret for gitea internal token --------------------------
      sops.secrets.gitea_internal_token = {
        sopsFile = "${inputs.nixos-secrets}/secrets/UwU-Server/gitea.yaml";
        key = "internal_token";
        owner = "gitea";
        mode = "0400";
      };

      # --- Nginx reverse proxy ------------------------------------------
      services.nginx.virtualHosts."git.${domain}" = {
        useACMEHost = domain;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3001";
          proxyWebsockets = true;
        };
        # Git LFS support -- large file storage.
        locations."/lfs/" = {
          proxyPass = "http://127.0.0.1:3001/lfs/";
          extraConfig = ''
            client_max_body_size 500m;
          '';
        };
      };

      # --- Glance: add gitea to bookmarks --------------------------------
      services.glance.settings.pages = lib.mkAfter [
        {
          name = "Git";
          columns = [
            {
              size = "full";
              widgets = [
                {
                  type = "monitor";
                  title = "Git Services";
                  sites = [
                    { title = "Gitea"; url = "https://git.${domain}"; icon = "si:gitea"; alt-status-codes = [ 302 ]; }
                  ];
                }
                {
                  type = "bookmarks";
                  groups = [
                    {
                      title = "Repositories";
                      links = [
                        { title = "nix-config"; url = "https://git.${domain}/JaideAirblade/nix-config"; icon = "si:nixos"; }
                        { title = "nixos-secrets"; url = "https://git.${domain}/JaideAirblade/nixos-secrets"; icon = "si:nixos"; }
                      ];
                    }
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