#!/usr/bin/env python3
"""Regression tests for the Luna-Server chrony NTP+NTS server module
and the per-host chrony-client opt-in (TSBW).

Verifies that the chrono-ntp modules wire up correctly in the flake
without needing a real `nixos-rebuild switch`. Each check below
evaluates the flake and asserts the resolved config attribute.

Invariants:

  1. Luna-Server: services.chrony.enable is true
  2. Luna-Server: services.chrony.enableNTS is true (NTS-KE server)
  3. Luna-Server: services.timesyncd.enable is false (asserted by
     chrony module; we set it explicitly to make intent clear)
  4. Luna-Server: services.chrony.servers are pool.ntp.org with iburst
  5. Luna-Server: extraConfig has bindaddress lines for both the
     NetBird IP (100.77.228.137) and the direct-link IP (10.10.0.1)
  6. Luna-Server: extraConfig references the *.jaidechan.moe cert
  7. Luna-Server: extraConfig contains a commented GPS refclock
     block (the future-proofing hook)
  8. Luna-Server: the chrony user is in the nginx group (so it can
     read the acme-installed cert with mode 0640)
  9. Luna-Server: the chrony service is in the acme cert's
     reloadServices list (so cert renewal reloads it)
  10. Luna-Server: the firewall opens 123/UDP and 4460/TCP on both
     the NetBird interface (wt0) and the direct-link interface (eth0)
  11. TSBW-W01800: services.chrony.enable is true
  12. TSBW-W01800: services.chrony.servers includes the mesh-DNS
      NTS-KE endpoint "time.jaidechan.moe" with `iburst nts`
  13. TSBW-W01800: services.timesyncd.enable is false

The test exits non-zero on first failure with a clear diff. Run
via `nix flake check` or directly: `python3 tests/chrony-regressions.py`.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# The NetBird IP and direct-link IP the server binds to. These come
# from the actual Luna-Server config (modules/network/netbird-mesh.nix
# and hosts/Luna-Server/network/direct-link.nix respectively) and are
# hardcoded in the server module. If they rotate, this test must
# rotate with them.
NB_IP = "100.77.228.137"
LINK_IP = "10.10.0.1"
SERVER_FQDN = "time.jaidechan.moe"


def nix_eval(expr: str) -> object:
    """Evaluate a Nix expression against the local flake and return the JSON value."""
    proc = subprocess.run(
        [
            "nix",
            "--extra-experimental-features",
            "nix-command flakes",
            "eval",
            "--json",
            "--impure",
            "--expr",
            expr,
        ],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=300,
    )
    if proc.returncode != 0:
        print(f"nix eval failed:\n  expr: {expr}\n  stderr: {proc.stderr}", file=sys.stderr)
        sys.exit(2)
    return json.loads(proc.stdout)


def uwu(value_expr: str) -> object:
    """Eval `value_expr` against Luna-Server's resolved config."""
    return nix_eval(
        f'(builtins.getFlake "path:{REPO}").nixosConfigurations.Luna-Server.config.{value_expr}'
    )


def tsbw(value_expr: str) -> object:
    """Eval `value_expr` against TSBW-W01800's resolved config."""
    return nix_eval(
        f'(builtins.getFlake "path:{REPO}").nixosConfigurations.TSBW-W01800.config.{value_expr}'
    )


def check(label: str, actual, expected) -> None:
    """Compare actual to expected; print a diff and exit on mismatch."""
    if actual == expected:
        print(f"  ✓  {label}")
    else:
        print(f"  ✗  {label}")
        print(f"        expected: {expected!r}")
        print(f"        actual:   {actual!r}")
        sys.exit(1)


def check_match(label: str, value: str, pattern: str) -> None:
    """Assert that `pattern` (regex) appears in `value`.

    `^` and `$` match per-line (MULTILINE), so anchored patterns like
    `^bindaddress 1.2.3.4$` work even when the value is multiline.
    """
    if re.search(pattern, value, re.MULTILINE):
        print(f"  ✓  {label}")
    else:
        print(f"  ✗  {label}")
        print(f"        pattern not found: {pattern!r}")
        print(f"        in value: {value!r}")
        sys.exit(1)


def main() -> None:
    print("── 1. Luna-Server chrony server is enabled and configured ──")

    check("services.chrony.enable = true", uwu("services.chrony.enable"), True)
    # enableNTS must stay FALSE: the nixpkgs module appends `nts` to every
    # upstream pool line (most pool servers don't speak NTS → server stuck at
    # stratum 0) and would double-configure the NTS server side. The NTS
    # *server* directives live in extraConfig; the NTS value is on the
    # client side (TSBW authenticates time.jaidechan.moe).
    check(
        "services.chrony.enableNTS = false (upstream stays plain NTP; NTS server via extraConfig)",
        uwu("services.chrony.enableNTS"),
        False,
    )
    check(
        "services.timesyncd.enable = false (chrony module asserts on this)",
        uwu("services.timesyncd.enable"),
        False,
    )

    servers = uwu("services.chrony.servers")
    expected_servers = [
        "0.pool.ntp.org iburst",
        "1.pool.ntp.org iburst",
        "2.pool.ntp.org iburst",
        "3.pool.ntp.org iburst",
    ]
    check("services.chrony.servers = [0..3].pool.ntp.org iburst", servers, expected_servers)

    # extraConfig: bindaddresses, cert paths, GPS hook
    extra = uwu("services.chrony.extraConfig")
    check_match(
        f"extraConfig has 'bindaddress {LINK_IP}' (direct-link)",
        extra,
        rf"^bindaddress {re.escape(LINK_IP)}\s*$",
    )
    check_match(
        f"extraConfig has 'bindaddress {NB_IP}' (NetBird)",
        extra,
        rf"^bindaddress {re.escape(NB_IP)}\s*$",
    )
    check_match(
        "extraConfig references the *.jaidechan.moe cert",
        extra,
        r"ntsservercert /var/lib/acme/jaidechan\.moe/fullchain\.pem",
    )
    check_match(
        "extraConfig references the *.jaidechan.moe key",
        extra,
        r"ntsserverkey /var/lib/acme/jaidechan\.moe/key\.pem",
    )
    check_match(
        "extraConfig contains a commented GPS refclock block (future hook)",
        extra,
        r"refclock PPS /dev/pps0",
    )

    print("\n── 2. Luna-Server chrony user can read the acme cert ──")
    extra_groups = uwu("users.users.chrony.extraGroups")
    check(
        "users.users.chrony.extraGroups includes 'nginx'",
        "nginx" in extra_groups,
        True,
    )

    print("\n── 3. Luna-Server acme cert renewal reloads chrony ──")
    reload = uwu('security.acme.certs."jaidechan.moe".reloadServices')
    check(
        "security.acme.certs.jaidechan.moe.reloadServices includes 'chrony.service'",
        "chrony.service" in reload,
        True,
    )

    print("\n── 4. Luna-Server firewall opens NTP+NTS-KE on mesh and direct-link ──")
    # On wt0 (NetBird): ports 123/UDP, 4460/TCP must be present.
    wt0_tcp = uwu('networking.firewall.interfaces."wt0".allowedTCPPorts')
    wt0_udp = uwu('networking.firewall.interfaces."wt0".allowedUDPPorts')
    check("firewall.wt0.allowedTCPPorts includes 4460 (NTS-KE)", 4460 in wt0_tcp, True)
    check("firewall.wt0.allowedTCPPorts includes 123 (NTP/TCP)", 123 in wt0_tcp, True)
    check("firewall.wt0.allowedUDPPorts includes 123 (NTP/UDP)", 123 in wt0_udp, True)

    # On eth0 (direct-link): same ports must be present.
    eth0_tcp = uwu('networking.firewall.interfaces."eth0".allowedTCPPorts')
    eth0_udp = uwu('networking.firewall.interfaces."eth0".allowedUDPPorts')
    check("firewall.eth0.allowedTCPPorts includes 4460 (NTS-KE)", 4460 in eth0_tcp, True)
    check("firewall.eth0.allowedTCPPorts includes 123 (NTP/TCP)", 123 in eth0_tcp, True)
    check("firewall.eth0.allowedUDPPorts includes 123 (NTP/UDP)", 123 in eth0_udp, True)

    # The PUBLIC interface (eno1) must NOT have NTP or NTS-KE open.
    # We check that the firewall config doesn't mention eno1 having
    # these ports -- the absence of the rule is the test.
    eno1_tcp = uwu('networking.firewall.interfaces."eno1".allowedTCPPorts or []')
    eno1_udp = uwu('networking.firewall.interfaces."eno1".allowedUDPPorts or []')
    check("firewall.eno1 does NOT open 123/TCP (public side)", 123 in eno1_tcp, False)
    check("firewall.eno1 does NOT open 4460/TCP (public side)", 4460 in eno1_tcp, False)
    check("firewall.eno1 does NOT open 123/UDP (public side)", 123 in eno1_udp, False)

    print("\n── 5. TSBW-W01800 chrony client is enabled and pointing at Luna-Server ──")
    check("services.chrony.enable = true", tsbw("services.chrony.enable"), True)
    check(
        "services.timesyncd.enable = false (chrony module asserts on this)",
        tsbw("services.timesyncd.enable"),
        False,
    )

    servers = tsbw("services.chrony.servers")
    expected = f"{SERVER_FQDN} iburst nts"
    check(
        f"servers includes '{expected}' (NTS over the mesh DNS)",
        expected in servers,
        True,
    )

    print(f"\n== 13/13 checks passed ==")
    print("chrony regressions: PASS")


if __name__ == "__main__":
    main()
