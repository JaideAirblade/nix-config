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