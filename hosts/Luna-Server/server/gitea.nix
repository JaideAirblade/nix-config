# Gitea: self-hosted Git service.
#
# Runs on Luna-Server behind nginx at git.jaidechan.moe.
# SSH git access via the host's SSH server (port 22, already open on wt0).
# SQLite database (sufficient for personal use).
# Registration disabled -- single user (jaide/luna).
#
# Repos stored at /var/lib/gitea/repositories.
{
  inputs, lib, ... }:
{
  nixos.hosts."Luna-Server" =
    { config, ... }:

    let
      domain = "jaidechan.moe";
    in
    {
      services.gitea = {
        enable = true;
        appName = "Jaide's Git";
        user = "git";

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

      # Create the `git` system user so SSH clones as git@host work.
      users.users.git = {
        isSystemUser = true;
        group = "git";
        home = "/var/lib/gitea";
        useDefaultShell = true;
      };
      users.groups.git = {};

      # --- Sops secret for gitea internal token --------------------------
      sops.secrets.gitea_internal_token = {
        sopsFile = "${inputs.nixos-secrets}/secrets/Luna-Server/gitea.yaml";
        key = "internal_token";
        owner = "git";
        mode = "0400";
      };

      # --- Nginx reverse proxy ------------------------------------------
      services.nginx.virtualHosts."git.${domain}" = {
        useACMEHost = domain;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3001";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 500m;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
          '';
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