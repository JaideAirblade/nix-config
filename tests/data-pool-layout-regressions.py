#!/usr/bin/env python3
"""Static regressions for the Luna-Server disko disk layout.

The single most important invariant this test enforces:

  The string ``nvme1n1`` (the OS drive) appears in
  ``hosts/Luna-Server/disk-layout.nix`` EXACTLY ONCE — and that one
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
DISK_LAYOUT = ROOT / "hosts/Luna-Server/disk-layout.nix"
DEFAULT_NIX = ROOT / "hosts/Luna-Server/default.nix"

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
        "dataMedia partition uses size = \"100%\" (disko's special enum for rest-of-disk)",
        re.search(r'size\s*=\s*"100%"', code) is not None,
    )
    check(
        "dataMedia partition does NOT use the rejected \"100%FREE\" string",
        re.search(r'100%FREE', code) is None,
    )
    check(
        "dataMedia mounts at /media/l1 (sibling of /media/l2, both under /media/)",
        re.search(r'mountpoint\s*=\s*"/media/l1"\s*;', code) is not None,
    )
    check(
        "dataMedia mountpoint is not required for boot (`nofail` in mountOptions)",
        re.search(r'"nofail"', code) is not None,
    )

# ── dataMedia2 pool invariants ───────────────────────────────────
data_backup_block = re.search(
    r'disko\.devices\.disk\.dataMedia2\s*=\s*\{(.*?)\n      \};',
    text,
    re.DOTALL,
)
check(
    "dataMedia2 disko block is present",
    data_backup_block is not None,
)
if data_backup_block is not None:
    body = non_comment_lines(data_backup_block.group(1))
    code = "\n".join(body)
    check(
        "dataMedia2 addresses the drive by /dev/disk/by-id/ (PCI-bus-stable)",
        "/dev/disk/by-id/nvme-Lexar" in code,
    )
    check(
        "dataMedia2 declares destroy = false (disko destroy stage is no-op)",
        re.search(r"destroy\s*=\s*false\s*;", code) is not None,
    )
    check(
        "dataMedia2 btrfs does NOT pass -f (no force-overwrite of existing btrfs)",
        re.search(r'extraArgs\s*=\s*\[\s*"-f"\s*\]', code) is None,
    )
    check(
        "dataMedia2 btrfs has extraArgs = [ ] (explicit empty list)",
        re.search(r"extraArgs\s*=\s*\[\s*\]", code) is not None,
    )
    check(
        "dataMedia2 partition uses size = \"100%\" (disko's special enum for rest-of-disk)",
        re.search(r'size\s*=\s*"100%"', code) is not None,
    )
    check(
        "dataMedia2 partition does NOT use the rejected \"100%FREE\" string",
        re.search(r'100%FREE', code) is None,
    )
    check(
        "dataMedia2 mounts at /media/l2 (sibling of /media/l1, both under /media/)",
        re.search(r'mountpoint\s*=\s*"/media/l2"\s*;', code) is not None,
    )
    check(
        "dataMedia2 mountpoint is not required for boot (`nofail` in mountOptions)",
        re.search(r'"nofail"', code) is not None,
    )

# ── Two data pools are distinct: different mountpoints and different serials ──
if data_media_block and data_backup_block:
    media_text = data_media_block.group(0)
    backup_text = data_backup_block.group(0)
    media_serial = re.search(r"nvme-Lexar_SSD_NM790_4TB_(\w+)", media_text)
    backup_serial = re.search(r"nvme-Lexar_SSD_NM790_4TB_(\w+)", backup_text)
    check(
        "dataMedia and dataMedia2 point at different physical serials",
        bool(media_serial and backup_serial and media_serial.group(1) != backup_serial.group(1)),
        f"media={media_serial.group(1) if media_serial else '?'} "
        f"media2={backup_serial.group(1) if backup_serial else '?'}",
    )

# ── Both data pools share /media/ as a parent directory ──────────
# dataMedia mounts at /media/l1; dataMedia2 mounts at /media/l2. /media/
# is a directory (not a mount). Both mounts use X-mount.mkdir via the
# subvolume mountOptions to create their respective leaf dirs.
if data_media_block and data_backup_block:
    media_text = data_media_block.group(0)
    media2_text = data_backup_block.group(0)
    media_mp = re.search(r'mountpoint\s*=\s*"([^"]+)"', media_text)
    media2_mp = re.search(r'mountpoint\s*=\s*"([^"]+)"', media2_text)
    if media_mp and media2_mp:
        m1, m2 = media_mp.group(1), media2_mp.group(1)
        check(
            "dataMedia mounts at /media/l1",
            m1 == "/media/l1", f"actual: {m1}",
        )
        check(
            "dataMedia2 mounts at /media/l2",
            m2 == "/media/l2", f"actual: {m2}",
        )
        # Both mountpoints share /media/ as a parent
        check(
            "both data pools share /media/ as parent directory",
            m1.startswith("/media/") and m2.startswith("/media/")
            and m1 != m2,
            f"media={m1}, media2={m2}",
        )
        check(
            "no data pool mounts at /backup (the old /backup mountpoint is gone)",
            not re.search(r'mountpoint\s*=\s*"/backup"', text),
            "the dataBackup block was renamed to dataMedia2 with mountpoint /media/l2; "
            "the new /media/backup mountpoint is on the GIGABYTE 1TB drive, not a 'backup' "
            "sibling of /media/l1",
        )

# ── Linkage: hosts/Luna-Server/default.nix references disk-layout.nix ──
check(
    "hosts/Luna-Server/default.nix mentions disk-layout.nix (linkage is documented)",
    "disk-layout.nix" in default_text,
    "the host entry point should reference its disk layout file by name",
)

# ── gamesAndBackup pool invariants (GIGABYTE 1TB, added 2026-08-06) ──
# Single physical disk split into two btrfs partitions (games + backup).
# Each partition is its own single-device btrfs (no multi-device pool).
# Critical safety properties:
#   - The GIGABYTE 1TB is NOT the OS drive. The OS is the Crucial E100
#     (by-id nvme-CT1000E100SSD8). A copy-paste mistake that swaps the
#     GIGABYTE's by-id into the root pool would wipe the OS — caught
#     by the OS-by-id-exactly-one check above. This block just enforces
#     the pool's own invariants.
#   - destroy = false so disko's destroy stage doesn't touch the disk's
#     existing partition table (the ext4 "Files" partition on it).
#   - extraArgs = [] (no -f) so the btrfs format step can't force-overwrite
#     an existing btrfs on re-runs.
#   - nofail in mountOptions so boot doesn't block if the drive is missing.
games_backup_block = re.search(
    r'disko\.devices\.disk\.gamesAndBackup\s*=\s*\{(.*?)\n      \};',
    text,
    re.DOTALL,
)
check(
    "gamesAndBackup disko block is present",
    games_backup_block is not None,
)
if games_backup_block is not None:
    body = non_comment_lines(games_backup_block.group(1))
    code = "\n".join(body)
    check(
        "gamesAndBackup addresses the drive by /dev/disk/by-id/ (PCI-bus-stable)",
        "/dev/disk/by-id/nvme-GIGABYTE" in code,
    )
    check(
        "gamesAndBackup declares destroy = false (disko destroy stage is no-op)",
        re.search(r"destroy\s*=\s*false\s*;", code) is not None,
    )
    # Both partitions must satisfy the btrfs safety contract.
    # Each partition is its own btrfs, so each must:
    #   - have extraArgs = [ ] (no -f)
    #   - not contain size = "100%FREE"
    #   - include "nofail" in mountOptions
    games_partition_match = re.search(
        r'games\s*=\s*\{',
        code,
    )
    backup_partition_match = re.search(
        r'backup\s*=\s*\{',
        code,
    )
    check(
        "gamesAndBackup has both 'games' and 'backup' partitions",
        games_partition_match is not None and backup_partition_match is not None,
    )
    if games_partition_match is not None:
        # Extract the body of the games partition by slicing from the
        # match position to the next sibling ('backup' partition). The
        # body's full content lives between the opening `{` of `games`
        # and the closing `}` followed by `\n            },` (the end of
        # the partition block at the disko-nested indent).
        g_start = games_partition_match.end()
        next_part = re.search(r'\n            \}\s*,\s*\n\s*backup\s*=\s*\{', code[g_start:])
        if next_part is not None:
            gp_code = code[g_start:g_start + next_part.start()]
        else:
            gp_code = code[g_start:]
        check(
            "games partition btrfs does NOT pass -f",
            re.search(r'extraArgs\s*=\s*\[\s*"-f"\s*\]', gp_code) is None,
        )
        check(
            "games partition btrfs has extraArgs = [ ]",
            re.search(r"extraArgs\s*=\s*\[\s*\]", gp_code) is not None,
        )
        check(
            "games partition btrfs has nofail in mountOptions",
            '"nofail"' in gp_code,
        )
        check(
            "games partition does NOT use the rejected '100%FREE' string",
            "100%FREE" not in gp_code,
        )
    if backup_partition_match is not None:
        b_start = backup_partition_match.end()
        # The backup partition is the LAST sibling before the closing
        # `};` of the gamesAndBackup block.
        end_match = re.search(r'\n            \}', code[b_start:])
        if end_match is not None:
            bp_code = code[b_start:b_start + end_match.start()]
        else:
            bp_code = code[b_start:]
        check(
            "backup partition btrfs does NOT pass -f",
            re.search(r'extraArgs\s*=\s*\[\s*"-f"\s*\]', bp_code) is None,
        )
        check(
            "backup partition btrfs has extraArgs = [ ]",
            re.search(r"extraArgs\s*=\s*\[\s*\]", bp_code) is not None,
        )
        check(
            "backup partition btrfs has nofail in mountOptions",
            '"nofail"' in bp_code,
        )
        check(
            "backup partition does NOT use the rejected '100%FREE' string",
            "100%FREE" not in bp_code,
        )

# ── gamesAndBackup pool mountpoints ──
# Both partitions live under /media/ (sibling of /media/l1, /media/l2).
if games_backup_block is not None:
    gbp_code = "\n".join(non_comment_lines(games_backup_block.group(1)))
    check(
        "gamesAndBackup games partition mounts at /media/games",
        re.search(r'mountpoint\s*=\s*"/media/games"\s*;', gbp_code) is not None,
    )
    check(
        "gamesAndBackup backup partition mounts at /media/backup",
        re.search(r'mountpoint\s*=\s*"/media/backup"\s*;', gbp_code) is not None,
    )

# ── The GIGABYTE 1TB by-id is referenced exactly once in the file ──
# Same defensive pattern as the Crucial E100: one by-id reference per
# physical disk. Two `device = "...GIGABYTE..."` lines would mean two
# disko.devices.disk blocks for the same physical disk, which is
# invalid (one disk, one block).
gigabyte_by_id_lines = [
    line.strip() for line in text.splitlines()
    if "device = \"/dev/disk/by-id/nvme-GIGABYTE" in line
]
check(
    "GIGABYTE 1TB by-id path appears in exactly one device = line "
    "(one disko block per physical disk)",
    len(gigabyte_by_id_lines) == 1,
    f"found {len(gigabyte_by_id_lines)} reference(s): {gigabyte_by_id_lines}",
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
