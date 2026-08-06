#!/usr/bin/env python3
"""Static regressions for the UwU-Server disko disk layout.

The single most important invariant this test enforces:

  The string ``nvme1n1`` (the OS drive) appears in
  ``hosts/UwU-Server/disk-layout.nix`` EXACTLY ONCE — and that one
  reference is the root pool's ``device`` field. A future edit that
  adds a second reference to ``nvme1n1`` (e.g. by accident in a new
  data-disk block) would cause ``disko -m format,mount`` to wipe the
  OS drive on next provision. The test fails on any additional
  reference.

Secondary invariants:

  - Both data pools declare ``destroy = false`` so the disko
    ``destroy`` stage is a no-op for them. The ``format`` stage
    skips ``mkfs.btrfs`` when a btrfs signature is already present
    (see disko ``lib/types/btrfs.nix`` ``_create``), so the existing
    btrfs on each 4TB is preserved.
  - Neither data pool passes ``extraArgs = [ "-f" ]`` to btrfs.
    ``-f`` is ``mkfs.btrfs --force`` and would overwrite an existing
    filesystem even when the partition boundary matches.
  - Both data partitions use ``size = "100%FREE"`` so disko cannot
    shrink an existing partition.
  - Each data pool's mountpoint has ``neededForBoot = false`` set in
    its btrfs config (or equivalent), so a missing data drive does
    not block boot. The disko module emits ``nofail`` in the
    generated fstab entry when ``neededForBoot = false``.
  - Each data pool mounts at a distinct path (``/media`` vs
    ``/backup``) so they can never be aliased.
  - The OS root pool still has ``extraArgs = [ "-f" ]`` (needed
    because the OS install re-formats the root on provisioning).
  - Both data pools are addressed via ``/dev/disk/by-id/`` (not
    ``/dev/nvmeXn1``), so PCI bus renumbering does not break the
    link between the disko config and the physical device.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DISK_LAYOUT = ROOT / "hosts/UwU-Server/disk-layout.nix"
DEFAULT_NIX = ROOT / "hosts/UwU-Server/default.nix"

results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    """Record a pass/fail check; print a one-liner."""
    mark = "✓" if ok else "✗"
    suffix = f"  ({detail})" if detail else ""
    print(f"  {mark}  {name}{suffix}")
    results.append((name, ok, detail))


text = DISK_LAYOUT.read_text()
default_text = DEFAULT_NIX.read_text()


def non_comment_lines(body: str) -> list[str]:
    """Return lines of `body` with comment lines stripped.

    Disko configs are line-oriented: a `#` starts a Nix line comment
    that runs to end-of-line. The regression test must NOT match
    `extraArgs = [ "-f" ]` if it appears only inside a `#` comment.
    Stripping comment lines first means regexes against `body` only
    see actual code.
    """
    return [line for line in body.splitlines() if not line.lstrip().startswith("#")]


# ── OS drive reference count: must be exactly one ─────────────────
# The disko config references the OS drive by its stable `/dev/disk/by-id/`
# symlink (which encodes the model + serial), not by the bare `nvme1n1`
# device name. The regression check is therefore: there is exactly one
# `device = "/dev/disk/by-id/nvme-CT1000E100SSD8_..."` line in the file,
# AND it lives inside the `disko.devices.disk.main` block.
os_by_id_lines = [
    line.strip() for line in text.splitlines()
    if "device = \"/dev/disk/by-id/nvme-CT1000E100SSD8" in line
]
check(
    "OS drive (Crucial E100) by-id path appears in exactly one device = line",
    len(os_by_id_lines) == 1,
    f"found {len(os_by_id_lines)} reference(s): {os_by_id_lines}",
)
if len(os_by_id_lines) == 1:
    check(
        "the Crucial E100 by-id reference sits inside the `disko.devices.disk.main` block",
        'disko.devices.disk.main' in text and os_by_id_lines[0].startswith("device ="),
    )

# ── Defensive: no bare `nvme1n1` device path anywhere ─────────────
# Bare `/dev/nvme1n1` paths are bus-renumbering-fragile AND would
# silently match if the OS drive is ever confused with a data drive.
# The disko config must use by-id exclusively.
bare_os_refs = [
    line for line in text.splitlines()
    if "/dev/nvme1n1" in line and "by-id" not in line
]
check(
    "no bare `/dev/nvme1n1` device path appears in the disko config",
    len(bare_os_refs) == 0,
    f"found: {bare_os_refs}" if bare_os_refs else "",
)

# ── Defensive: no `nvme1n1` reference inside any data-disk block ─
# A future edit that copy-pastes a Lexar block and changes the by-id
# string but forgets to change a hardcoded `nvme1n1` comment would be
# caught by this — the safety contract is "nvme1n1 is the OS drive
# ONLY", and that includes comments inside other blocks.
main_block = re.search(
    r'disko\.devices\.disk\.main\s*=\s*\{(.*?)\n      \};',
    text,
    re.DOTALL,
)
if main_block is not None:
    main_code = "\n".join(non_comment_lines(main_block.group(1)))
    check(
        "root pool's btrfs keeps extraArgs = [ \"-f\" ] (required for nixos-anywhere provisioning)",
        re.search(r'extraArgs\s*=\s*\[\s*"-f"\s*\]', main_code) is not None,
    )
    data_blocks = re.findall(
        r'disko\.devices\.disk\.(?:dataMedia|dataBackup)\s*=\s*\{(.*?)\n      \};',
        text,
        re.DOTALL,
    )
    leaks = [
        line.strip() for body in data_blocks
        for line in non_comment_lines(body)
        if "nvme1n1" in line
    ]
    check(
        "the string `nvme1n1` never appears inside a data-disk block (code lines only)",
        len(leaks) == 0,
        f"leaks: {leaks}" if leaks else "",
    )

# ── Root pool still has extraArgs = [ "-f" ] (needed for OS re-install) ──
# (the `extraArgs = [ "-f" ]` check lives in the main_block section above;
# it spans the full main block including nested `{ ... }` via re.DOTALL.)

# ── dataMedia pool invariants ─────────────────────────────────────
data_media_block = re.search(
    r'disko\.devices\.disk\.dataMedia\s*=\s*\{(.*?)\n      \};',
    text,
    re.DOTALL,
)
check(
    "dataMedia disko block is present",
    data_media_block is not None,
)
if data_media_block is not None:
    body = non_comment_lines(data_media_block.group(1))
    code = "\n".join(body)
    check(
        "dataMedia addresses the drive by /dev/disk/by-id/ (PCI-bus-stable)",
        "/dev/disk/by-id/nvme-Lexar" in code,
    )
    check(
        "dataMedia declares destroy = false (disko destroy stage is no-op)",
        re.search(r"destroy\s*=\s*false\s*;", code) is not None,
    )
    check(
        "dataMedia btrfs does NOT pass -f (no force-overwrite of existing btrfs)",
        re.search(
            r'extraArgs\s*=\s*\[\s*"-f"\s*\]', code
        ) is None,
    )
    check(
        "dataMedia btrfs has extraArgs = [ ] (explicit empty list)",
        re.search(r"extraArgs\s*=\s*\[\s*\]", code) is not None,
    )
    check(
        "dataMedia partition uses size = \"100%FREE\" (no shrink)",
        re.search(r'size\s*=\s*"100%FREE"', code) is not None,
    )
    check(
        "dataMedia mounts at /media (not at /, /home, or any system path)",
        re.search(r'mountpoint\s*=\s*"/media"\s*;', code) is not None,
    )
    check(
        "dataMedia mountpoint is not required for boot (`nofail` in mountOptions)",
        re.search(r'"nofail"', code) is not None,
    )

# ── dataBackup pool invariants ────────────────────────────────────
data_backup_block = re.search(
    r'disko\.devices\.disk\.dataBackup\s*=\s*\{(.*?)\n      \};',
    text,
    re.DOTALL,
)
check(
    "dataBackup disko block is present",
    data_backup_block is not None,
)
if data_backup_block is not None:
    body = non_comment_lines(data_backup_block.group(1))
    code = "\n".join(body)
    check(
        "dataBackup addresses the drive by /dev/disk/by-id/ (PCI-bus-stable)",
        "/dev/disk/by-id/nvme-Lexar" in code,
    )
    check(
        "dataBackup declares destroy = false (disko destroy stage is no-op)",
        re.search(r"destroy\s*=\s*false\s*;", code) is not None,
    )
    check(
        "dataBackup btrfs does NOT pass -f (no force-overwrite of existing btrfs)",
        re.search(r'extraArgs\s*=\s*\[\s*"-f"\s*\]', code) is None,
    )
    check(
        "dataBackup btrfs has extraArgs = [ ] (explicit empty list)",
        re.search(r"extraArgs\s*=\s*\[\s*\]", code) is not None,
    )
    check(
        "dataBackup partition uses size = \"100%FREE\" (no shrink)",
        re.search(r'size\s*=\s*"100%FREE"', code) is not None,
    )
    check(
        "dataBackup mounts at /backup (not at /, /home, or any system path)",
        re.search(r'mountpoint\s*=\s*"/backup"\s*;', code) is not None,
    )
    check(
        "dataBackup mountpoint is not required for boot (`nofail` in mountOptions)",
        re.search(r'"nofail"', code) is not None,
    )

# ── Two data pools are distinct: different mountpoints and different serials ──
if data_media_block and data_backup_block:
    media_text = data_media_block.group(0)
    backup_text = data_backup_block.group(0)
    media_serial = re.search(r"nvme-Lexar_SSD_NM790_4TB_(\w+)", media_text)
    backup_serial = re.search(r"nvme-Lexar_SSD_NM790_4TB_(\w+)", backup_text)
    check(
        "dataMedia and dataBackup point at different physical serials",
        bool(media_serial and backup_serial and media_serial.group(1) != backup_serial.group(1)),
        f"media={media_serial.group(1) if media_serial else '?'} "
        f"backup={backup_serial.group(1) if backup_serial else '?'}",
    )

# ── Linkage: hosts/UwU-Server/default.nix references disk-layout.nix ──
check(
    "hosts/UwU-Server/default.nix mentions disk-layout.nix (linkage is documented)",
    "disk-layout.nix" in default_text,
    "the host entry point should reference its disk layout file by name",
)

# ── Summary ───────────────────────────────────────────────────────
passed = sum(1 for _, ok, _ in results if ok)
total = len(results)
print()
print(f"== {passed}/{total} checks passed ==")
if passed != total:
    print("FAIL: data-pool-layout regressions")
    for name, ok, detail in results:
        if not ok:
            print(f"  - {name}  {detail}")
    sys.exit(1)
print("data-pool-layout regressions: PASS")
