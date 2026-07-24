{ lib, stdenv, makeWrapper, bash, iproute2, iputils, ethtool, lldpd
, networkmanager, nftables, bind, systemd, curl, mtr, traceroute
, bridge-utils, util-linux, wirelesstools, coreutils, gnused, gawk
, procps, conntrack-tools, getent, iw, aircrack-ng, tcpdump, libcap, gnugrep }:

stdenv.mkDerivation {
  pname = "net-report";
  version = "2.1.0";

  src = ./.;

  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src/net-report.sh $out/bin/net-report

    # Wrap with all tools the script references, so they're on PATH even in
    # environments where the system profile doesn't have them.
    wrapProgram $out/bin/net-report \
      --prefix PATH : ${lib.makeBinPath [
        bash iproute2 iputils ethtool lldpd networkmanager nftables
        bind systemd curl mtr traceroute bridge-utils util-linux
        wirelesstools coreutils gnused gawk procps conntrack-tools getent
        iw aircrack-ng tcpdump libcap gnugrep
      ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Comprehensive network status report tool (LLDP, conntrack, firewall analysis, WiFi deauth scan, discovery, routes, DNS, sockets, VPN, traceroute)";
    mainProgram = "net-report";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}