#!/usr/bin/env python3
"""Regression checks for net-report's privileged WiFi monitor path."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "pkgs/net-report/net-report.sh").read_text()
MODULE = (ROOT / "modules/network/network.nix").read_text()


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")


require(MODULE, "net-report-ip = {", "capability wrapper for bringing monitor interface up")
require(MODULE, 'source = "${pkgs.iproute2}/bin/ip";', "net-report-ip source")
require(MODULE, 'capabilities = "cap_net_admin+eip";', "net-report-ip capability")
require(SCRIPT, "IP_BIN=/run/wrappers/bin/net-report-ip", "script uses privileged ip wrapper")
require(SCRIPT, '"$IP_BIN" link set "$mon_iface" up', "monitor interface is brought up with privileged ip")
require(SCRIPT, "Monitor interface failed to come UP", "monitor UP state is verified")
require(SCRIPT, "tcpdump failed to start", "capture startup is verified")
require(SCRIPT, "aireplay_rc", "aireplay result is checked instead of discarded")
require(SCRIPT, "Capture retained for inspection:", "failed capture evidence is retained")

old_silent_injection = '"$AIREPLAY_BIN" --deauth 5 -a "$ap_bssid" "$mon_iface" >/dev/null 2>&1 || true'
if old_silent_injection in SCRIPT:
    raise SystemExit("FAIL: aireplay output and status are still discarded")

# The pcap must NOT be deleted in the success path of wifi-scan — retained
# for inspection. Scope the search to just the wifi-scan function body.
wifi_scan_start = SCRIPT.find("section_wifi-scan()")
wifi_scan_end = SCRIPT.find("\n}", wifi_scan_start)  # end of the function
wifi_scan_body = SCRIPT[wifi_scan_start:wifi_scan_end]
require(wifi_scan_body, "Capture retained for inspection:", "capture is retained for inspection")

if 'rm -rf "$tmpdir"' in wifi_scan_body.split("Capture retained")[0]:
    # Before the "Capture retained" line, rm -rf is only in the error path — OK.
    # But check if it's after "Cleaning up monitor" (success path):
    pass

# Check the success path: after "Capture retained for inspection", no rm -rf
retained_idx = wifi_scan_body.find("Capture retained for inspection:")
success_body = wifi_scan_body[retained_idx:]
if 'rm -rf "$tmpdir"' in success_body:
    raise SystemExit("FAIL: capture is deleted in success path of wifi-scan")

# No stale/broken tshark fallback that reads a deleted file
broken_tshark = "re-reading pcap — this is from the in-memory copy, already cleaned up"
if broken_tshark in SCRIPT:
    raise SystemExit("FAIL: stale tshark fallback referencing deleted pcap")

print("net-report wifi-scan regressions: PASS")
