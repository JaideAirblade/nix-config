# OfficeCLI — AI-friendly CLI for .docx, .xlsx, .pptx
# https://github.com/iOfficeAI/OfficeCLI
# Single self-contained .NET binary with embedded runtime.
# autoPatchelfHook fixes the interpreter + rpath for NixOS; ICU is
# linked so .NET's globalization layer finds libicu* at runtime.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, glibc
, libgcc
, icu
,
}:

stdenv.mkDerivation rec {
  pname = "officecli";
  version = "1.0.143";

  src = fetchurl {
    url = "https://github.com/iOfficeAI/OfficeCLI/releases/download/v${version}/officecli-linux-x64";
    hash = "sha256-ainFmKeJtXySwD5WCQfT8TGkvQoGh4Wx0ziob8MaWKc=";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    glibc
    libgcc
    icu
  ];

  installPhase = ''
    install -Dm755 $src $out/bin/officecli
  '';

  meta = {
    description = "World's first Office suite designed for AI agents — create, read, and edit Word, Excel, PowerPoint from the CLI";
    homepage = "https://github.com/iOfficeAI/OfficeCLI";
    changelog = "https://github.com/iOfficeAI/OfficeCLI/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "officecli";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}