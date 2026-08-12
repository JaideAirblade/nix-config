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
# The package itself is installed by modules/theming/onlyoffice-dms-theme.nix
# (which uses `lib.mkForce` so this module's listing doesn't get clobbered).
# This module's job is purely to mark which hosts want the office suite
# (and therefore pull in OnlyOffice).
_:
{
  nixos.modules.office = { ... }: { };
}