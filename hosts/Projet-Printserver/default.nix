# Projet-Printserver — NixOS print server VM for the AD test lab.
#
# This host runs as a VM in the ad-lab network (192.168.100.0/24) and
# provides centralized print services with AD-integrated authentication.
# It joins the lab.local domain and enforces per-printer ACLs based on
# AD group membership.
#
# ── Roles ──────────────────────────────────────────────────────────
#   common       — base system (locale, users, shell, packages)
#   printServer  — CUPS + Samba + SSSD + realmd + krb5 (this module)
#
# ── AD join (one-time, after first boot) ───────────────────────────
#   1. Boot the VM:  just lab-create-printserver
#   2. SSH in:       ssh root@192.168.100.20
#   3. Join domain:  realm join lab.local -U Administrator
#   4. Verify:       id administrator && getent passwd administrator
#   5. Put the exact SSSD user name reported above in
#      hosts/Projet-Printserver/users/users.nix under
#      users.groups.lpadmin.members
#   6. Deploy:       just deploy Projet-Printserver
#
# After the join, AD users can print to \\PRINTSERVER\<printer> and the
# ACLs defined in print-server-config.nix are enforced.
#
# ── Adding a new printer ───────────────────────────────────────────
#   1. Edit hosts/Projet-Printserver/services/print-server-config.nix
#   2. Add a printer entry to the printServer.printers attrset
#   3. Create an AD group for the printer (on the DC):
#        New-ADGroup -Name "Print-<PrinterName>" -GroupScope Global
#   4. Deploy: just deploy Projet-Printserver
#   5. The print-server-sync oneshot creates/updates the printer in CUPS
{ config, inputs, ... }:
{
  flake.nixosConfigurations."Projet-Printserver" = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";

    modules = [
      config.nixos.modules.common
      config.nixos.modules.remoteMesh
      config.nixos.modules.printServer
      config.nixos.hosts."Projet-Printserver"

      # Generated lower-level module exception.
      ./hardware-configuration.nix

      { nixpkgs.overlays = [ inputs.self.overlays.additions ]; }

      {
        services.privateMesh = {
          nodeRole = "printserver";
          exposeSshOnLan = true;
        };
      }

      # State version — matches the NixOS release this host was created on.
      { system.stateVersion = "26.05"; }
    ];
  };
}
