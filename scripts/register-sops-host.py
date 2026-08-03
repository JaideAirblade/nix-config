#!/usr/bin/env python3
"""Register one host recipient in Jaide's SOPS creation rules.

This intentionally edits the small, conventional .sops.yaml used by this
repository without loading decrypted secret values or requiring a YAML library.
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
from pathlib import Path
from typing import NoReturn

HOST_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")
AGE_RE = re.compile(r"^age1[023456789acdefghjklmnpqrstuvwxyz]{20,}$")
PATH_RULE_RE = re.compile(r"^  - path_regex: (.+)$")
KEY_ANCHOR_RE = re.compile(r"^  - &([A-Za-z0-9_-]+) (\S+)$")


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ERROR: {message}")


def rule_ranges(lines: list[str]) -> list[tuple[int, int, str]]:
    starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = PATH_RULE_RE.match(line)
        if match:
            starts.append((index, match.group(1)))
    return [
        (start, starts[pos + 1][0] if pos + 1 < len(starts) else len(lines), path)
        for pos, (start, path) in enumerate(starts)
    ]


def add_reference(lines: list[str], path_pattern: str, reference: str) -> None:
    for start, end, path in rule_ranges(lines):
        if path != path_pattern:
            continue
        block = lines[start:end]
        ref_line = f"          - *{reference}"
        if ref_line in block:
            return
        age_index = next((i for i, line in enumerate(block) if line == "      - age:"), None)
        if age_index is None:
            fail(f"creation rule {path_pattern!r} has no conventional age key group")
        insert_at = age_index + 1
        while insert_at < len(block) and block[insert_at].startswith("          - *"):
            insert_at += 1
        lines.insert(start + insert_at, ref_line)
        return
    fail(f"required creation rule {path_pattern!r} not found")


def register(path: Path, hostname: str, pubkey: str) -> None:
    if not HOST_RE.fullmatch(hostname):
        fail(f"unsafe or invalid hostname: {hostname!r}")
    if not AGE_RE.fullmatch(pubkey):
        fail("invalid age public key")
    if not path.is_file():
        fail(f"rules file does not exist: {path}")

    original = path.read_text()
    lines = original.splitlines()

    try:
        creation_index = lines.index("creation_rules:")
    except ValueError:
        fail("creation_rules section not found")

    anchors: list[tuple[int, str]] = []
    for index, line in enumerate(lines[:creation_index]):
        match = KEY_ANCHOR_RE.match(line)
        if match:
            anchors.append((index, match.group(1)))
    if not anchors:
        fail("keys section contains no YAML anchors")

    anchor_name = f"host_{hostname}"
    anchor_line = f"  - &{anchor_name} {pubkey}"
    existing_anchor = next((index for index, name in anchors if name == anchor_name), None)
    if existing_anchor is not None:
        lines[existing_anchor] = anchor_line
    else:
        last_host = next((index for index, name in reversed(anchors) if name.startswith("host_")), None)
        insert_at = (last_host if last_host is not None else anchors[-1][0]) + 1
        lines.insert(insert_at, anchor_line)

    admin_refs = [name for _, name in anchors if not name.startswith("host_")]
    if not admin_refs:
        fail("no non-host/admin recipients found")

    host_pattern = rf"secrets/{hostname}/.*\.yaml$"
    existing_paths = {rule_path for _, _, rule_path in rule_ranges(lines)}
    if host_pattern not in existing_paths:
        shared_start = next(
            (start for start, _, rule_path in rule_ranges(lines) if rule_path == r"secrets/shared/.*\.yaml$"),
            None,
        )
        if shared_start is None:
            fail("shared secrets creation rule not found")
        host_rule = [
            f"  - path_regex: {host_pattern}",
            "    key_groups:",
            "      - age:",
            *(f"          - *{name}" for name in admin_refs),
            f"          - *{anchor_name}",
            "",
        ]
        lines[shared_start:shared_start] = host_rule
    else:
        add_reference(lines, host_pattern, anchor_name)

    add_reference(lines, r"secrets/shared/.*\.yaml$", anchor_name)
    add_reference(lines, r"secrets\.yaml$", anchor_name)

    updated = "\n".join(lines) + "\n"
    if updated == original:
        print(f"{hostname}: SOPS recipient already registered")
        return

    mode = path.stat().st_mode & 0o777
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        handle.write(updated)
        temp_name = handle.name
    os.chmod(temp_name, mode)
    os.replace(temp_name, path)
    print(f"{hostname}: registered {pubkey}")


def main() -> None:
    if len(sys.argv) != 4:
        fail("usage: register-sops-host.py <.sops.yaml> <hostname> <age-public-key>")
    register(Path(sys.argv[1]), sys.argv[2], sys.argv[3])


if __name__ == "__main__":
    main()
