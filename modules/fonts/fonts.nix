# System fonts: broad language coverage + nerd glyphs for terminals.
#
# NixOS's default font set (DejaVu, freefont, liberation, corefonts) covers
# Latin well but leaves big gaps for CJK, emoji, and the powerline/dev-icon
# glyphs that Starship and Ghostty rely on. We layer Noto on top for
# near-universal script coverage and a Nerd Font for terminal glyphs, then
# set fontconfig fall-back order so apps actually reach the installed
# fonts (without defaultFonts, an app that picks a Latin-only font shows
# tofu boxes for CJK even with Noto installed).
{ pkgs, ... }:

{
  # Keep NixOS's baseline set (DejaVu, freefont, liberation, corefonts).
  fonts.enableDefaultPackages = true;

  fonts.packages = with pkgs; [
    # Noto — Google's universal-fonts project. The base package covers
    # Latin/Cyrillic/Greek/Arabic/Hebrew/Devanagari/Thai/etc.; the CJK
    # packages add Chinese, Japanese, and Korean; color-emoji gives the
    # colour emoji glyphs that otherwise render as monochrome boxes.
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji

    # Nerd Font — powerline separators + dev-icon glyphs for Starship,
    # Ghostty, and any other terminal that expects Nerd Font codepoints.
    # Add more families here if you want a different default; the
    # monospace defaultFonts entry below points at JetBrains Mono.
    nerd-fonts.jetbrains-mono
  ];

  # Fall-back order fontconfig walks when a chosen font lacks a glyph.
  # The CJK entry uses "SC" (Simplified Chinese); fontconfig still
  # resolves Japanese/Korean glyphs through the same Noto CJK file.
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Noto Sans" "Noto Sans CJK SC" ];
    serif     = [ "Noto Serif" "Noto Serif CJK SC" ];
    monospace = [ "JetBrainsMono Nerd Font" "Noto Sans Mono CJK SC" ];
    emoji     = [ "Noto Color Emoji" ];
  };
}