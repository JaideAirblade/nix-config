# Office programs shared across the personal/work hosts.
#
# OnlyOffice Desktop Editors is a word/spreadsheet/presentation editor
# with native .docx/.xlsx/.pptx support (so Word/Excel/PowerPoint
# round-trip cleanly).
#
# Imported via `config.nixos.modules.office` in each host's default.nix,
# like `fileManager`. Skipping LaptopAP: it never imports any of the
# shared role modules (it builds its own ISO installer).
#
# The theming and the package itself live in
# `modules/theming/onlyoffice-dms-theme.nix`, which uses
# `pkgs.onlyoffice-desktopeditors.overrideAttrs` to:
#   1. Replace the fhsenv-profile wrapper symlink with a pure-passthrough
#      bash script that just `exec`s the upstream bwrap launcher.
#   2. Drop a sample `theme-dms.json` into the package's resources.
#
# This module's job is purely to mark which hosts want the office
# suite (and therefore pull in OnlyOffice).
_:
{
  nixos.modules.office = { ... }: { };
}
