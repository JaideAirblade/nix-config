# OfficeCLI — AI-friendly CLI for .docx, .xlsx, .pptx
# https://github.com/iOfficeAI/OfficeCLI
# Single self-contained .NET binary with embedded runtime.
#
# NixOS gotchas:
#   1. .NET single-file apps append ~23 MB of bundle data after the
#      ELF segment table. `strip` truncates the file to the ELF's
#      stated size → "Arithmetic overflow while reading bundle."
#      Fix: dontStrip + dontPatchELF.
#   2. .NET loads ICU and OpenSSL via dlopen at runtime — they are NOT
#      in the ELF NEEDED list, so autoPatchelfHook won't add them to
#      the rpath. Fix: wrapper sets LD_LIBRARY_PATH for both.
#   3. .NET's single-file host reads the bundle via mmap from the
#      executable's own file. /nix/store is mounted read-only, and
#      the mmap fails silently, corrupting the managed runtime
#      (manifests as "Names and aliases cannot be null" from
#      System.CommandLine). Copying the same binary to a writable
#      filesystem (tmpfs, writable btrfs) makes it work.
#      Fix: wrapper copies the binary to ~/.cache/officecli/ on first
#      run and executes the copy instead of the read-only store path.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, glibc
, libgcc
, icu
, openssl
,
}:

stdenv.mkDerivation rec {
  pname = "officecli";
  version = "1.0.144";

  src = fetchurl {
    url = "https://github.com/iOfficeAI/OfficeCLI/releases/download/v${version}/officecli-linux-x64";
    hash = "sha256-Mu96IaVKTKbJgGv16fPTK/sSkQFzKcVQRMsqrHGCLrg=";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # See header comment #1 — strip truncates the .NET bundle.
  dontStrip = true;
  dontPatchELF = true;

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  buildInputs = [
    glibc
    libgcc
    icu
    openssl
  ];

  installPhase = ''
    install -Dm755 $src $out/bin/officecli-unwrapped
  '';

  # autoPatchelfHook fixes interpreter + rpath for NEEDED libs (glibc,
  # libgcc). ICU and OpenSSL are dlopen'd by .NET at runtime, not in
  # the NEEDED list, so we pass them via LD_LIBRARY_PATH.
  #
  # The read-only /nix/store prevents .NET's single-file host from
  # mmapping the bundle correctly. The wrapper copies the binary to
  # a writable cache dir and runs it from there.
  postFixup = ''
    makeWrapper $out/bin/officecli-unwrapped $out/bin/officecli \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ icu openssl ]} \
      --run 'REAL="${placeholder "out"}/bin/officecli-unwrapped"' \
      --run 'HASH=$(sha256sum "$REAL" | cut -d" " -f1)' \
      --run 'CACHED="${"\${XDG_CACHE_HOME:-$HOME/.cache}"}/officecli/$HASH/officecli"' \
      --run 'if [ ! -f "$CACHED" ]; then mkdir -p "$(dirname "$CACHED")" && cp "$REAL" "$CACHED" && chmod +x "$CACHED"; fi' \
      --run 'exec -a officecli "$CACHED" "$@"'
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