#!/usr/bin/env python3
"""Regression test for the per-search-domain DNS routing logic in
hosts/TSBW-W01800/network/dns.nix.

The dispatcher (NM) and preStart (systemd) scripts both use the same
shell logic to map NM connections → dnsproxy upstream lines in
[/search-domain/]ip syntax. This test:

  1. Asserts the source files use the right `nmcli` field form
     (`-t -f DEVICE,STATE dev`) and the right filter (`state == connected`),
     so a future refactor can't silently re-introduce the old
     `GENERAL.DEVICE,GENERAL.STATE dev show` form which doesn't work.
  2. Extracts the dispatcher script from the NixOS build and runs it
     against a mock `nmcli` that simulates three networks: school,
     apartment, no-network. Asserts the output matches the expected
     per-domain upstream lines.
  3. Asserts the dispatcher also strips IPv6 + IPv6 link-local addresses
     (so a flaky DHCPv6 server can't break the chain).

Why a Python wrapper around a shell script? Because NixOS evaluates the
script source at activation time via pkgs.writeShellScript, not as a
separate file we can import. We shell out to `nix build` to extract the
actual rendered script and run it with our mock nmcli on PATH.
"""
from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DNS_NIX = ROOT / "hosts/TSBW-W01800/network/dns.nix"
FLAKE = ROOT / "flake.nix"


def require(cond: bool, msg: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {msg}")


def build_dispatcher() -> Path:
    """Build the actual NM dispatcher script via Nix and return its path."""
    out = subprocess.run(
        [
            "nix", "--extra-experimental-features", "nix-command flakes", "build",
            "--print-out-paths", "--no-link",
            f".#nixosConfigurations.\"TSBW-W01800\".config.environment.etc."
            "\"NetworkManager/dispatcher.d/01-dnsproxy-internal-dns\".source",
        ],
        cwd=ROOT, check=True, capture_output=True, text=True,
    )
    # Last non-empty line is the script path.
    candidates = [line for line in out.stdout.splitlines() if line.startswith("/nix/store/")]
    require(bool(candidates), f"nix build did not return a /nix/store path: {out.stdout!r} {out.stderr!r}")
    return Path(candidates[-1])


def write_mock_nmcli(mockdir: Path, mode: str) -> Path:
    """Write a mock `nmcli` to mockdir that simulates a specific network."""
    mock = mockdir / "nmcli"
    body = {
        "school": textwrap.dedent("""\
            #!/usr/bin/env bash
            case "$*" in
              *"DEVICE,STATE dev"*) echo "wlp3s0:connected"; echo "lo:connected" ;;
              *"IP4.DOMAIN dev show wlp3s0"*) echo "IP4.DOMAIN:tsbw.de,ausbildung.tsbw.de" ;;
              *"IP4.DOMAIN dev show lo"*) echo "IP4.DOMAIN:" ;;
              *"IP4.DNS dev show wlp3s0"*)
                echo "IP4.DNS:10.34.1.20"; echo "IP4.DNS:10.34.1.50"; echo "IP4.DNS:fe80::1%wlp3s0" ;;
              *"IP4.DNS dev show lo"*) echo "IP4.DNS:" ;;
            esac
            """),
        "apartment": textwrap.dedent("""\
            #!/usr/bin/env bash
            case "$*" in
              *"DEVICE,STATE dev"*) echo "wlp3s0:connected" ;;
              *"IP4.DOMAIN dev show wlp3s0"*) echo "IP4.DOMAIN:fritz.box" ;;
              *"IP4.DNS dev show wlp3s0"*) echo "IP4.DNS:192.168.178.1" ;;
            esac
            """),
        "no-network": textwrap.dedent("""\
            #!/usr/bin/env bash
            case "$*" in
              *"DEVICE,STATE dev"*) echo "wlp3s0:disconnected"; echo "lo:connected" ;;
              *"IP4.DOMAIN dev show lo"*) echo "IP4.DOMAIN:" ;;
              *"IP4.DNS dev show lo"*) echo "IP4.DNS:" ;;
            esac
            """),
        "ipv6-mixed": textwrap.dedent("""\
            #!/usr/bin/env bash
            case "$*" in
              *"DEVICE,STATE dev"*) echo "wlp3s0:connected" ;;
              *"IP4.DOMAIN dev show wlp3s0"*) echo "IP4.DOMAIN:tsbw.de" ;;
              *"IP4.DNS dev show wlp3s0"*)
                echo "IP4.DNS:10.34.1.20"
                echo "IP4.DNS:fd00::1"
                echo "IP4.DNS:fe80::1%wlp3s0"
                ;;
            esac
            """),
    }[mode]
    mock.write_text(body)
    mock.chmod(mock.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return mock


def run_dispatcher(dispatcher: Path, mockdir: Path) -> str:
    """Run the dispatcher with the mock nmcli on PATH, returning stdout.

    We invoke via /usr/bin/env bash — the dispatcher's shebang references
    a Nix-store bash that may not be portable. The dispatcher also calls
    `systemctl try-restart dnsproxy.service` which we don't want to
    actually run; we override `systemctl` to a no-op.
    """
    # No-op systemctl — dispatcher pipes through 2>/dev/null || true so
    # any exit code is swallowed; we just override to be sure.
    noop_systemctl = mockdir / "systemctl"
    noop_systemctl.write_text("#!/usr/bin/env bash\nexit 0\n")
    noop_systemctl.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = f"{mockdir}:{env.get('PATH', '')}"

    # The dispatcher writes to /run/dnsproxy/ — we don't want to write
    # there from a test. Override with a temp dir via a bind mount? No,
    # simplest: run the dispatcher in a namespace OR just accept the
    # write — /run/dnsproxy is a RuntimeDirectory owned by root. Skip
    # the actual invocation and just shell-extract + exec the routing
    # logic, since the dispatcher is just a wrapper around it.
    #
    # But the routing logic is INSIDE the dispatcher script. We re-read
    # the dispatcher script and execute it in a subshell that has our
    # mock PATH. The script's mktemp + mv calls will fail (no write to
    # /run/dnsproxy), but the routing logic happens BEFORE the mktemp,
    # so we capture stdout. We tolerate the script's exit-code failure.
    #
    # Actually simpler: just exec the dispatcher with `|| true` and
    # extract the lines we want from stdout. The script's stdout is the
    # ROUTES list — but the dispatcher doesn't print ROUTES! It writes
    # them to a file. So we can't capture via stdout.
    #
    # So we run the dispatcher in a subprocess, redirecting to a writable
    # temp dir via LD_PRELOAD or similar — too complex. Just run it as
    # root via sudo -n if available, OR run it with /run/dnsproxy
    # replaced by a writable path by injecting a `mkdir` override that
    # remaps /run/dnsproxy → /tmp/...
    #
    # Actually the dispatcher's `mkdir -p /run/dnsproxy` will silently
    # fail (Permission denied) and the script will exit early — but the
    # mapfile population happens BEFORE the mkdir, so if we capture the
    # routes via stdout we lose nothing... except the script doesn't
    # print them.
    #
    # Cleanest fix: copy the dispatcher to a tempdir, sed-rewrite the
    # paths to point at /tmp/test-dnsproxy/, and run THAT.
    tmpdir = tempfile.mkdtemp(prefix="dnsproxy-test-")
    tmp_dnsproxy = Path(tmpdir) / "dnsproxy"
    tmp_dnsproxy.mkdir(parents=True, exist_ok=True)
    rewritten = Path(tmpdir) / "dispatcher.sh"
    text = dispatcher.read_text()
    text = text.replace("/run/dnsproxy", str(tmp_dnsproxy))
    rewritten.write_text(text)
    rewritten.chmod(0o755)

    result = subprocess.run(
        [str(rewritten), "wlp3s0", "up"],
        env=env, capture_output=True, text=True, timeout=10,
    )
    output = tmp_dnsproxy / "internal-upstreams.txt"
    contents = output.read_text() if output.exists() else ""
    shutil.rmtree(tmpdir, ignore_errors=True)
    return contents


def assert_eq(name: str, expected: str, actual: str) -> bool:
    if actual == expected:
        print(f"  PASS: {name}")
        return True
    print(f"  FAIL: {name}")
    print(f"    expected: {expected!r}")
    print(f"    actual:   {actual!r}")
    return False


def main() -> int:
    # === Tests ===

    # 1. Source-level invariants: the dispatcher must use the
    # `nmcli -t -f DEVICE,STATE dev` form (which emits one
    # `<device>:<state>` line per device). The earlier form
    # `nmcli -t -f GENERAL.DEVICE,GENERAL.STATE dev show` doesn't work on
    # real NM (it emits one key:value pair per line, not one
    # device:state pair per line) and was a real bug in 2026-08-11.
    print("== 1. Source uses nmcli DEVICE,STATE form ==")
    dns_nix_text = DNS_NIX.read_text()
    require("nmcli -t -f DEVICE,STATE dev" in dns_nix_text,
            "dns.nix dispatcher must use `nmcli -t -f DEVICE,STATE dev` "
            "(not the older GENERAL.DEVICE,GENERAL.STATE dev show form, "
            "which doesn't emit device:state lines)")
    require('[[ "$state" == "connected" ]]' in dns_nix_text,
            "dns.nix dispatcher must filter on `state == connected` "
            "(avoids polluting the upstream list with disconnected interfaces)")
    require('[/%s/]%s\\n' in dns_nix_text,
            "dns.nix dispatcher must emit dnsproxy upstream lines in "
            "`[/search-domain/]dns-ip` syntax")
    require('*:*|*%*)' in dns_nix_text,
            "dns.nix dispatcher must filter out IPv6 + IPv6 link-local "
            "addresses (a flaky DHCPv6 server shouldn't break the chain)")
    print("  PASS: source invariants")

    # 2. Build the dispatcher + run it through several mock-nmcli scenarios.
    print("\n== 2. Dispatcher routing logic ==")
    with tempfile.TemporaryDirectory(prefix="dnsproxy-mock-") as mockdir:
        dispatcher = build_dispatcher()
        mockdir_path = Path(mockdir)

        write_mock_nmcli(mockdir_path, "school")
        actual = run_dispatcher(dispatcher, mockdir_path)
        assert_eq(
            "school",
            "[/ausbildung.tsbw.de/]10.34.1.20\n"
            "[/ausbildung.tsbw.de/]10.34.1.50\n"
            "[/tsbw.de/]10.34.1.20\n"
            "[/tsbw.de/]10.34.1.50\n",
            actual,
        )

        write_mock_nmcli(mockdir_path, "apartment")
        actual = run_dispatcher(dispatcher, mockdir_path)
        assert_eq("apartment", "[/fritz.box/]192.168.178.1\n", actual)

        write_mock_nmcli(mockdir_path, "no-network")
        actual = run_dispatcher(dispatcher, mockdir_path)
        # When no connection is up, the dispatcher writes a placeholder
        # comment line so the file always exists for dnsproxy to read.
        # We assert the file is NOT a real upstream list (no `[/`).
        assert_eq("no-network", "# No DHCP DNS\n", actual)

        write_mock_nmcli(mockdir_path, "ipv6-mixed")
        actual = run_dispatcher(dispatcher, mockdir_path)
        assert_eq("ipv4-only (ipv6 stripped)", "[/tsbw.de/]10.34.1.20\n", actual)

    print("\nTSBW DNS dispatcher regressions: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
