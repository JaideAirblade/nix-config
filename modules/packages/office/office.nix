# Office programs shared across the personal/work hosts.
#
# Currently just OnlyOffice Desktop Editors — a word/spreadsheet/presentation
# editor with native .docx/.xlsx/.pptx support (so Word/Excel/PowerPoint
# round-trip cleanly).
#
# Imported via `config.nixos.modules.office` in each host's default.nix,
# like `fileManager`. Skipping LaptopAP: it never imports any of the
# shared role modules (it builds its own ISO installer).
#
# The package was renamed from `onlyoffice-bin` to `onlyoffice-desktopeditors`
# in nixpkgs on 2025-10-27 — if you're updating older examples, the new
# name is the only one that resolves.
#
# The DMS-themed override (modules/theming/onlyoffice-dms-theme.nix)
# wraps this package's fhsenv-profile wrapper so the bwrap launcher
# mounts a writable, patched `index.html` over the read-only store
# copy. On hosts that import both `office` and the theming module, the
# closure ends up with two slightly-different store paths and OnlyOffice
# is installed twice (~400 MiB each). This is acceptable for the three
# office-using hosts; deduping cleanly across modules would require
# either a passthrough attr on the package or merging the two modules,
# both of which add complexity not justified by a one-time install cost.
_:
{
  nixos.modules.office =
    { pkgs, ... }:

    {
      environment.systemPackages = with pkgs; [
        # OnlyOffice Desktop Editors — word/spreadsheet/presentation editor
        # (docx/xlsx/pptx native). ~400 MiB unpacked; pulled by every host
        # that imports this module.
        onlyoffice-desktopeditors
      ];
    }
  ;
}