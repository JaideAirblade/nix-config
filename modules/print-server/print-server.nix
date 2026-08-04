# Print server role — CUPS + Samba + AD integration with declarative ACLs.
#
# This module provides a reusable `nixos.modules.printServer` role that turns
# any NixOS host into an Active Directory-integrated print server with:
#
#   1. Declarative printer definitions — printers are defined in a Nix attrset,
#      not manually via lpadmin. A systemd oneshot syncs them into CUPS on
#      every deploy.
#   2. Per-printer ACLs — each printer specifies which AD groups are allowed
#      to print. CUPS `<Location /printers/NAME>` blocks enforce this at the
#      spooler level.
#   3. Samba print sharing — Windows clients can connect via
#      \\printserver\printer. Samba uses AD authentication (security = ads)
#      via SSSD/winbind.
#   4. AD integration — SSSD + realmd + krb5 join the machine to the domain
#      so AD users and groups are resolvable for authentication.
#
# The role is opt-in: a host must select `config.nixos.modules.printServer`
# in its entry point and provide the `printServer` config attrset.
#
# ── Printer attrset shape ──────────────────────────────────────────
#
#   printServer = {
#     enable = true;
#     realm = "LAB.LOCAL";
#     domain = "lab.local";
#     domainController = "192.168.100.10";
#     netbiosName = "PRINTSERVER";
#     printers = {
#       "HP-LaserJet-1" = {
#         deviceUri = "ipp://192.168.1.50/ipp/print";
#         model = "drv:///sample.drv/generic.ppd";
#         allowedGroups = [ "Print-HP-LaserJet-1" ];
#         location = "Room 101";
#         description = "HP LaserJet Pro M404dn";
#       };
#     };
#   };
#
# ── ACL enforcement ────────────────────────────────────────────────
#
# CUPS `<Location /printers/NAME>` blocks control who can submit jobs to
# each printer. The `Require user @GROUP` directive restricts access to
# members of a CUPS group. We map AD groups to CUPS groups via SSSD's
# group resolution — when a user authenticates, SSSD resolves their AD
# group memberships, and CUPS checks them against the Require directive.
#
# For the ACL to work, the AD user must be able to authenticate to CUPS.
# This means:
#   - SSSD must be running and resolving AD users (id <user> works)
#   - CUPS must use PAM authentication (it does by default on NixOS)
#   - The AD groups in `allowedGroups` must exist in AD and be resolvable
#     via `getent group <name>`
#
# ── Samba print sharing ────────────────────────────────────────────
#
# Samba shares each printer via `\\printserver\printer`. Windows clients
# download the driver from the print$ share (if populated) or use a local
# driver. Authentication is via AD (security = ads) through SSSD/winbind.
#
# ── AD join ────────────────────────────────────────────────────────
#
# The actual domain join (`realm join`) is a one-time imperative step that
# requires a domain admin credential. This module sets up all the
# prerequisites (krb5, sssd, realmd, samba) so that `realm join` works.
# The join creates /etc/krb5.keytab and updates AD's computer account.
#
# See the host entry (hosts/Projet-Printserver/) for the join instructions.
_:
{
  nixos.modules.printServer =
    { config, lib, pkgs, ... }:

    let
      cfg = config.printServer;

      # Generate CUPS printer entries for printers.conf.
      # We write directly to /var/lib/cups/printers.conf instead of using
      # lpadmin, because CUPS's IPP auth (polkit/PAM) rejects lpadmin
      # even when running as root via a systemd service on NixOS.
      # Writing the file directly is how NixOS's own cupsd.nix handles
      # config — CUPS reads printers.conf on startup.
      printerToConf = name: printer: ''
        <Printer ${name}>
        UUID
        Info ${lib.optionalString (printer.description != null) printer.description}
        Location ${lib.optionalString (printer.location != null) printer.location}
        MakeModel everywhere
        DeviceURI ${printer.deviceUri}
        State Idle
        StateTime 0
        Type 8425476
        Accepting Yes
        Shared Yes
        JobSheets none none
        QuotaPeriod 0
        PageLimit 0
        KLimit 0
        OpPolicy default
        ErrorPolicy retry-job
        </Printer>
      '';

      # All printer entries concatenated into printers.conf content.
      printersConf = lib.concatStringsSep "\n" (
        lib.mapAttrsToList printerToConf cfg.printers
      );

      # Generate CUPS <Location> blocks for ACL enforcement.
      # Each printer gets a Location block that requires membership in at
      # least one of the allowedGroups. If allowedGroups is empty, all
      # authenticated users can print (Require valid-user).
      printerToLocationBlock = name: printer: ''
        <Location /printers/${name}>
          Order allow,deny
          ${if printer.allowedGroups == [ ] then
            "Require valid-user"
          else
            "Require user ${lib.concatMapStringsSep " " (g: "@${g}") printer.allowedGroups}"}
        </Location>
      '';

      # All Location blocks concatenated into cupsd.conf extraConf.
      locationBlocks = lib.concatStringsSep "\n" (
        lib.mapAttrsToList printerToLocationBlock cfg.printers
      );
    in
    {
      # ── Role options ────────────────────────────────────────────
      # Top-level options so any host importing the role gets them.
      # The host entry point selects the role via
      # config.nixos.modules.printServer, which merges these into the
      # system config.

      options.printServer = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable the AD-integrated print server role.";
        };

        realm = lib.mkOption {
          type = lib.types.str;
          description = "Kerberos realm (uppercase domain name, e.g. LAB.LOCAL).";
          example = "LAB.LOCAL";
        };

        domain = lib.mkOption {
          type = lib.types.str;
          description = "AD domain name (lowercase, e.g. lab.local).";
          example = "lab.local";
        };

        domainController = lib.mkOption {
          type = lib.types.str;
          description = "Hostname or IP of the AD domain controller.";
          example = "192.168.100.10";
        };

        netbiosName = lib.mkOption {
          type = lib.types.str;
          description = "NetBIOS name of the print server (max 15 chars, uppercase).";
          example = "PRINTSERVER";
        };

        printers = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                deviceUri = lib.mkOption {
                  type = lib.types.str;
                  description = "CUPS device URI (e.g. ipp://192.168.1.50/ipp/print).";
                  example = "ipp://192.168.1.50/ipp/print";
                };

                model = lib.mkOption {
                  type = lib.types.str;
                  default = "drv:///sample.drv/generic.ppd";
                  description = "CUPS model/driver name or PPD file path.";
                };

                ppdFile = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  description = "Path to a PPD file (overrides model if set).";
                };

                location = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Physical location of the printer.";
                };

                description = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Human-readable description of the printer.";
                };

                allowedGroups = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = ''
                    AD groups allowed to print to this printer.
                    Empty list = all authenticated AD users.
                    The groups must exist in AD and be resolvable via SSSD.
                  '';
                  example = [ "Print-Admins" "Print-Floor1" ];
                };
              };
            }
          );
          default = { };
          description = "Declarative printer definitions.";
        };
      };

      config = lib.mkIf cfg.enable {
        # ── Kerberos ──────────────────────────────────────────────
        # krb5.conf tells Kerberos clients where the KDC and admin servers
        # are. SSSD uses this to get TGTs for AD authentication.
        security.krb5 = {
          enable = true;
          settings = {
            libdefaults = {
              default_realm = cfg.realm;
              dns_lookup_realm = false;
              dns_lookup_kdc = false;
              rdns = false;
            };
            realms."${cfg.realm}" = {
              kdc = [ cfg.domainController ];
              admin_server = cfg.domainController;
            };
            domain_realm = {
              ".${cfg.domain}" = cfg.realm;
              "${cfg.domain}" = cfg.realm;
            };
          };
        };

        # ── SSSD — AD user/group resolution ──────────────────────
        # SSSD is the bridge between AD and Linux. It resolves AD users
        # and groups via NSS (so `id <ad-user>` works) and provides PAM
        # authentication (so AD users can log in with their AD password).
        #
        # The config below uses the "ad" id_provider, which pulls user/group
        # info directly from AD via LDAP. The "ad" auth_provider uses
        # Kerberos for password verification.
        #
        # use_fully_qualified_names = false: short names (jsmith) resolve
        # without the domain suffix. This is needed for CUPS ACLs — the
        # `Require user @GROUP` directive matches short group names.
        services.sssd = {
          enable = true;
          settings = {
            sssd = {
              services = "nss, pam";
              domains = cfg.realm;
              config_file_version = 2;
            };
            nss = {
              filter_groups = "root";
              filter_users = "root";
            };
            pam = { };
            "domain/${cfg.realm}" = {
              id_provider = "ad";
              auth_provider = "ad";
              access_provider = "ad";
              chpass_provider = "ad";
              ad_domain = cfg.domain;
              ad_server = cfg.domainController;
              ad_hostname = cfg.netbiosName;
              use_fully_qualified_names = false;
              fallback_homedir = "/home/%u";
              ldap_id_mapping = true;
              default_shell = "/bin/sh";
            };
          };
        };

        # ── realmd — manages the domain join ─────────────────────
        # realmd provides `realm join` and `realm leave` commands. It
        # configures SSSD, krb5, and Samba automatically during the join.
        # The actual join is a one-time imperative step (needs a domain
        # admin password). See the host entry for instructions.
        services.realmd.enable = true;

        # ── Samba — print sharing for Windows clients ───────────
        # Samba shares printers via \\printserver\printer. Security mode
        # "ads" means Samba authenticates against AD via Kerberos/SSSD.
        #
        # [printers] — shares all CUPS printers automatically
        # [print$] — driver download share for Windows clients
        # load printers = yes — Samba reads the CUPS printer list
        # printing = cups — Samba uses CUPS as the print backend
        services.samba = {
          enable = true;
          openFirewall = true;
          smbd.enable = true;
          nmbd.enable = true;
          winbindd.enable = true;
          settings = {
            global = {
              security = "ads";
              realm = cfg.realm;
              workgroup = lib.toUpper (lib.head (lib.splitString "." cfg.domain));
              "server role" = "member server";
              "server string" = "NixOS Print Server (${cfg.netbiosName})";
              "netbios name" = cfg.netbiosName;
              "load printers" = "yes";
              "printcap name" = "cups";
              "cups options" = "raw";
              "idmap config * : backend" = "tdb";
              "idmap config * : range" = "10000-99999";
              "map acl inherit" = "yes";
              "vfs objects" = "acl_xattr";
            };
            printers = {
              path = "/var/spool/samba";
              comment = "All Printers";
              printable = "yes";
              "create mask" = "0700";
              "use client driver" = "yes";
              browseable = "yes";
            };
            "print$" = {
              path = "/var/lib/samba/printers";
              comment = "Printer Drivers";
              writeable = "yes";
              "guest ok" = "no";
            };
          };
        };

        # ── CUPS — the print spooler ────────────────────────────
        # CUPS receives print jobs, applies ACLs, and sends them to the
        # printer. We disable socket activation (startWhenNeeded) because
        # a print server should always be listening for jobs.
        #
        # extraConf injects the <Location> blocks for per-printer ACLs.
        # The WebInterface is enabled for management at
        # http://printserver:631/admin (auth required).
        services.printing = {
          enable = true;
          browsed.enable = false;
          # mkForce: the common printing module sets startWhenNeeded = true
          # (socket activation). A print server must always be listening.
          startWhenNeeded = lib.mkForce false;
          defaultShared = true;
          webInterface = true;
          listenAddresses = [
            "0.0.0.0:631"
            "[::]:631"
          ];
          extraConf = ''
            # ── Per-printer ACLs (generated from printServer.printers) ─
            # Each Location block restricts who can submit jobs to that
            # printer. CUPS checks group membership via PAM → SSSD → AD.
            ${locationBlocks}

            # Allow admin management only from the lpadmin group.
            # AD users in the "Domain Admins" group should be added to the
            # local lpadmin group after domain join:
            #   usermod -aG lpadmin <ad-admin-user>
            <Location /admin>
              Order allow,deny
              Require user @lpadmin
            </Location>
          '';
        };

        # ── Firewall ─────────────────────────────────────────────
        # CUPS (631/tcp). Samba opens its own ports via openFirewall above.
        networking.firewall.allowedTCPPorts = [ 631 ];

        # ── Printer sync oneshot ──────────────────────────────────
        # This systemd service writes the declarative printer definitions
        # directly to /var/lib/cups/printers.conf, then restarts CUPS so
        # it picks up the new printers. We can't use lpadmin because
        # CUPS's IPP auth (polkit/PAM) rejects it even as root via the
        # unix socket on NixOS.
        #
        # The script is idempotent: it overwrites printers.conf with the
        # current config on every run. Printers that exist in CUPS but
        # not in the config are removed (printers.conf is overwritten).
        systemd.services.print-server-sync = {
          description = "Sync declarative printer definitions into CUPS";
          before = [ "cups.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";
          };
          script = ''
            echo "Writing printer definitions to /var/lib/cups/printers.conf..."
            mkdir -p /var/lib/cups
            cat > /var/lib/cups/printers.conf <<'CUPS_PRINTERS_CONF'
            # This file is automatically generated by the print-server-sync
            # service. Do not edit manually — changes will be overwritten.
            ${printersConf}
            CUPS_PRINTERS_CONF
            chown cups:lp /var/lib/cups/printers.conf 2>/dev/null || true
            chmod 600 /var/lib/cups/printers.conf
            echo "Printer sync complete."
          '';
        };

        # ── Samba spool directory ─────────────────────────────────
        # Samba needs a writable spool directory for print jobs.
        systemd.tmpfiles.rules = [
          "d /var/spool/samba 1777 root root -"
          "d /var/lib/samba/printers 0755 root root -"
        ];

        # ── Packages ──────────────────────────────────────────────
        environment.systemPackages = with pkgs; [
          cups # lpadmin, lpstat, lpinfo
          samba # smbclient, rpcclient for testing
          krb5 # kinit, klist, kdestroy
          realmd # realm join/leave
          adcli # adcli info, used by realmd
          sssd # sssctl for debugging
        ];
      };
    }
  ;
}
