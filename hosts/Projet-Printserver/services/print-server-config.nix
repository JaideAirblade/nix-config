# Print server configuration — printers, ACLs, and AD domain settings.
#
# This is the file you edit to add/remove printers and change who can
# print to them. Each printer is a key in the printServer.printers
# attrset. The allowedGroups list specifies which AD groups can print
# to that printer.
#
# ── To add a printer ───────────────────────────────────────────────
#   1. Add an entry to printServer.printers below.
#   2. Create the AD group on the DC:
#        New-ADGroup -Name "Print-<Name>" -GroupScope Global
#   3. Add users to the group:
#        Add-ADGroupMember -Identity "Print-<Name>" -Members "jsmith"
#   4. Deploy: just deploy Projet-Printserver
#
# ── To change a printer's ACL ──────────────────────────────────────
#   1. Edit the allowedGroups list for that printer.
#   2. Deploy: just deploy Projet-Printserver
#   The CUPS Location block is regenerated from the new list on deploy.
#
# ── To remove a printer ────────────────────────────────────────────
#   1. Delete the entry from printServer.printers.
#   2. Deploy: just deploy Projet-Printserver
#   3. Manually remove from CUPS (the sync script doesn't delete):
#        lpadmin -x <name>
#
# ── Mock printers for lab testing ──────────────────────────────────
# The two printers below use the CUPS "pdf" backend — they write PDF
# files to /var/spool/cups-pdf instead of sending to a real printer.
# This lets you test the full flow (ACL → spool → output) without a
# physical printer. Replace with real deviceUri values for production.
_:
{
  nixos.hosts."Projet-Printserver" =
    _:

    {
      printServer = {
        enable = true;

        # AD domain settings — must match the lab DC.
        realm = "LAB.LOCAL";
        domain = "lab.local";
        domainController = "192.168.100.10";
        netbiosName = "PRINTSERVER";

        printers = {
          # ── Mock null printer: Floor 1 ──────────────────────────
          # Uses file:/dev/null — accepts jobs and discards them.
          # This lets you test the full ACL flow without a real printer.
          # Only members of the "Print-Floor1" AD group can print.
          "PDF-Floor1" = {
            deviceUri = "file:/dev/null";
            model = "everywhere";
            location = "Floor 1 — Test Printer";
            description = "Null printer (Floor 1, restricted)";
            allowedGroups = [ "Print-Floor1" ];
          };

          # ── Mock null printer: Floor 2 ──────────────────────────
          # Only members of the "Print-Floor2" AD group can print.
          "PDF-Floor2" = {
            deviceUri = "file:/dev/null";
            model = "everywhere";
            location = "Floor 2 — Test Printer";
            description = "Null printer (Floor 2, restricted)";
            allowedGroups = [ "Print-Floor2" ];
          };

          # ── Open printer: all authenticated AD users ──────────
          # No group restriction — any AD user can print.
          "PDF-Open" = {
            deviceUri = "file:/dev/null";
            model = "everywhere";
            location = "Reception — Open Access";
            description = "Null printer (open to all AD users)";
            allowedGroups = [ ];
          };
        };
      };
    }
  ;
}
