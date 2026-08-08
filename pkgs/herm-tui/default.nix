# herm — The Hermes TUI built with OpenTUI
# https://github.com/liftaris/herm
#
# A modern TUI client for Hermes Agent. It's a pre-built bundle (8MB index.js)
# that runs under Bun. The npm tarball ships everything pre-bundled — React,
# tree-sitter WASM grammars, parser worker — all inlined. The only runtime
# dependency is Bun itself (>=1.3.0) and the platform-native @opentui/core
# package which provides the native terminal rendering engine.
#
# The launcher (bin/herm.cjs) is a Node shim that finds bun in PATH and execs
# index.js under it. We patch the shebang to use our bun directly.
{ lib
, stdenv
, fetchurl
, makeWrapper
, bun
, nodejs
}:

let
  # Platform-specific opentui native package.
  opentuiPlatform = {
    "x86_64-linux" = "core-linux-x64";
    "aarch64-linux" = "core-linux-arm64";
    "x86_64-darwin" = "core-darwin-x64";
    "aarch64-darwin" = "core-darwin-arm64";
  }.${stdenv.hostPlatform.system} or (throw "unsupported platform: ${stdenv.hostPlatform.system}");

  opentuiNative = fetchurl {
    url = "https://registry.npmjs.org/@opentui/${opentuiPlatform}/-/${opentuiPlatform}-0.2.2.tgz";
    hash = "sha256-cD5V0eRr8hiYYHV0gnhDXIWhPYYUMGW9GJfSqz6CK6k=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "herm-tui";
  version = "1.10.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/herm-tui/-/herm-tui-${finalAttrs.version}.tgz";
    hash = "sha256-N/iXg5RQwVCdtD+c+nZYxGDHgk9UWq66YG89c+AK3mY=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Don't let Nix strip/patch the pre-built JS bundle
  dontStrip = true;
  dontPatchELF = true;
  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    mkdir -p $out/lib/herm
    tar xzf $src -C $out/lib/herm --strip-components=1

    # Extract opentui native into node_modules so herm can find it
    mkdir -p $out/lib/herm/node_modules/@opentui/${opentuiPlatform}
    tar xzf ${opentuiNative} -C $out/lib/herm/node_modules/@opentui/${opentuiPlatform} --strip-components=1
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    # Patch the launcher to find bun deterministically
    substituteInPlace $out/lib/herm/bin/herm.cjs \
      --replace '?? "bun"' '?? "${lib.getExe bun}"'

    # Create the bin symlink with a wrapper that sets HOME for HERMES_HOME
    mkdir -p $out/bin
    makeWrapper ${lib.getExe nodejs} $out/bin/herm \
      --prefix PATH : ${lib.makeBinPath [ bun ]} \
      --add-flags $out/lib/herm/bin/herm.cjs

    runHook postInstall
  '';

  meta = with lib; {
    description = "A modern TUI for Hermes Agent — chat, sessions, skills, cron, kanban";
    homepage = "https://github.com/liftaris/herm";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    mainProgram = "herm";
  };
})
