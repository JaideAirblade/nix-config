{ lib
, stdenvNoCC
, fetchurl
, autoPatchelfHook
, dbus
, glibc
, libgcc
, libmnl
, libnftnl
}:

stdenvNoCC.mkDerivation rec {
  pname = "nym-vpnd";
  version = "2026.11.3";

  src = fetchurl {
    url = "https://github.com/nymtech/nym-vpn-client/releases/download/nym-vpn-v${version}/nym-vpn-core-v${version}_linux_x86_64.tar.gz";
    hash = "sha256-MtnZZxzOWETflhdKYdJ8++kTgIjE4XuqeDTCTZw+7wQ=";
  };

  sourceRoot = "nym-vpn-core-v${version}_linux_x86_64";

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    dbus
    glibc
    libgcc
    libmnl
    libnftnl
  ];

  installPhase = ''
    install -Dm755 nym-vpnd "$out/bin/nym-vpnd"
    install -Dm755 nym-exclude "$out/bin/nym-exclude"
    install -Dm755 nym-socks5-proxy "$out/bin/nym-socks5-proxy"
  '';

  meta = {
    description = "NymVPN daemon and supporting core tools";
    homepage = "https://github.com/nymtech/nym-vpn-client";
    changelog = "https://github.com/nymtech/nym-vpn-client/releases/tag/nym-vpn-v${version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "nym-vpnd";
    platforms = [ "x86_64-linux" ];
  };
}
