#!/usr/bin/env python3
"""Behavioral checks for the exact realized Hermes extension installer."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCE_NAMES = (
    "skill_source",
    "mnemosyne_source",
    "minimax_image_source",
    "minimax_video_source",
)
TARGET_NAMES = (
    "skill_path",
    "local_plugin_path",
    "minimax_image_path",
    "minimax_video_path",
    "local_minimax_image_path",
    "local_minimax_video_path",
)
LINKS = (
    ("skill_source", "skill_path"),
    ("mnemosyne_source", "local_plugin_path"),
    ("minimax_image_source", "minimax_image_path"),
    ("minimax_video_source", "minimax_video_path"),
    ("minimax_image_source", "local_minimax_image_path"),
    ("minimax_video_source", "local_minimax_video_path"),
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def assignments(script: str, names: tuple[str, ...]) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for name in names:
        match = re.search(rf"^{re.escape(name)}=([^\n]+)$", script, re.MULTILINE)
        if match is None:
            raise AssertionError(f"missing installer assignment: {name}")
        value = match.group(1).strip()
        require(not value.startswith(("'", '"')), f"unexpected quoted assignment: {name}")
        result[name] = Path(value)
    return result


def prior_store_path(current: Path, store: Path) -> Path:
    relative = current.relative_to(store)
    entry = relative.parts[0]
    require("-" in entry, f"store entry lacks a derivation name: {entry}")
    _, name = entry.split("-", 1)
    prior_entry = "0" * 32 + "-" + name
    return store / prior_entry / Path(*relative.parts[1:])


def run(installer: Path, *, expect_success: bool) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment.pop("HERMES_HOME", None)
    result = subprocess.run(
        ["bash", str(installer)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        check=False,
    )
    if expect_success and result.returncode != 0:
        raise AssertionError(f"installer failed unexpectedly: {result.stderr}")
    if not expect_success and result.returncode == 0:
        raise AssertionError("installer unexpectedly accepted an unsafe target layout")
    return result


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: hermes-server-installer-runtime.py INSTALLER")
    realized = Path(sys.argv[1])
    require(realized.is_file(), f"realized installer is missing: {realized}")

    with tempfile.TemporaryDirectory(prefix="hermes_server_installer_") as temporary:
        root = Path(temporary)
        fake_store = root / "nix/store"
        fake_home = root / "home/.hermes"
        calls = root / "hermes-calls.log"
        fake_hermes = root / "hermes-fake"
        fake_hermes.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            f"printf '%s|%s\\n' \"${{HERMES_HOME:-DEFAULT}}\" \"$*\" >> {calls}\n",
            encoding="utf-8",
        )
        fake_hermes.chmod(0o700)

        script_text = realized.read_text(encoding="utf-8")
        script_text = script_text.replace("/home/luna/.hermes", str(fake_home))
        script_text = script_text.replace("/nix/store", str(fake_store))
        script_text = re.sub(
            r"(?<![A-Za-z0-9_-])hermes(?=\s)",
            str(fake_hermes),
            script_text,
        )
        installer = root / "installer-under-test.sh"
        installer.write_text(script_text, encoding="utf-8")
        installer.chmod(0o700)

        sources = assignments(script_text, SOURCE_NAMES)
        targets = assignments(script_text, TARGET_NAMES)
        for source in sources.values():
            source.mkdir(parents=True, exist_ok=True)

        # A symlinked parent at a late target must fail before any earlier mutation.
        fake_home.mkdir(parents=True)
        outside_plugins = root / "outside-plugins"
        outside_plugins.mkdir()
        (fake_home / "plugins").symlink_to(outside_plugins, target_is_directory=True)
        refusal = run(installer, expect_success=False)
        require(
            "refusing symlinked parent for managed Hermes target" in refusal.stderr,
            "installer did not identify the symlinked target parent",
        )
        for _, target_name in LINKS:
            target = targets[target_name]
            require(not target.exists() and not target.is_symlink(), f"partial mutation before refusal: {target}")
        require(not any(outside_plugins.iterdir()), "installer wrote through a symlinked parent")
        (fake_home / "plugins").unlink()

        # Clean install on a fresh home succeeds and records the manifest.
        run(installer, expect_success=True)
        for source_name, target_name in LINKS:
            source = sources[source_name]
            target = targets[target_name]
            require(target.is_symlink(), f"managed target is not a symlink: {target}")
            require(target.resolve() == source.resolve(), f"managed target did not install: {target}")
        manifest = fake_home / ".hermes-server-managed-extensions"
        require(manifest.is_file(), "installer did not record a managed-extensions manifest")

        # Same-generation execution must be idempotent.
        before = {target_name: os.readlink(targets[target_name]) for _, target_name in LINKS}
        run(installer, expect_success=True)
        after = {target_name: os.readlink(targets[target_name]) for _, target_name in LINKS}
        require(after == before, "same-generation execution rewrote managed links")

        # An un-manifested same-name store path must be refused as unmanaged.
        for _, target_name in LINKS:
            target = targets[target_name]
            target.unlink()
            previous = prior_store_path(sources[LINKS[0][0]], fake_store)
            previous.mkdir(parents=True, exist_ok=True)
            target.symlink_to(previous, target_is_directory=True)
        refusal2 = run(installer, expect_success=False)
        require(
            "refusing to replace unmanaged" in refusal2.stderr,
            "installer accepted an un-manifested same-name target as prior generation",
        )

        call_lines = calls.read_text(encoding="utf-8").splitlines()
        require(
            bool(call_lines) and call_lines[0] == "DEFAULT|config set memory.provider mnemosyne",
            "fresh default profile did not select Mnemosyne before profile-specific configuration",
        )

        shutil.rmtree(fake_home)

    print("Hermes server installer parent, upgrade, idempotence, and fresh-home checks: PASS")


if __name__ == "__main__":
    main()
