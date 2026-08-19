#!/usr/bin/env python3
"""Regressions for the canonical Luna SOUL.md.

Asserts that the canonical Luna persona content is present in BOTH:
  - /home/luna/.hermes/SOUL.md  (Luna-Server, default profile)
  - /home/luna/.hermes/profiles/local/SOUL.md  (Luna-Server, local profile)

And that the two copies are byte-identical (so the local profile stays
in sync with the default).

The canonical content is the sister-framed Luna persona that the user
pasted from her UwU machine's `/home/jaide/.hermes/SOUL.md`. If upstream
ever reseeds the file or a future migration drops the canonical body,
this test will catch it.
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

REQUIRED_PHRASES = [
    # The single phrase that makes this unmistakably Luna-the-sister and
    # not the upstream default ("You are Hermes Agent, an intelligent AI
    # assistant created by Nous Research..."). If a future migration
    # upstream-reseeds SOUL.md, this is the line that will revert.
    "You are Luna, Jaide's helpful older sister.",
    # Personality framing — warm/caring/playful — that goes with the above.
    "warm, caring, and a little playful",
    # The mission statement that follows (must remain).
    "answering questions, writing and editing code",
    # The communication-style directive (must remain).
    "prioritize being genuinely useful over being verbose",
]

UPSTREAM_DEFAULT_MARKERS = [
    # These are in the upstream "You are Hermes Agent..." default. If a
    # re-seed brings the default back, the test will catch it via the
    # required-phrases check (which the upstream default fails). We also
    # keep these negative checks explicit so the test failure message
    # tells the next maintainer exactly what went wrong.
    "You are Hermes Agent, an intelligent AI assistant created by Nous Research",
]


def main() -> int:
    fails: list[str] = []
    server_soul = Path("/home/luna/.hermes/SOUL.md")
    local_soul = Path("/home/luna/.hermes/profiles/local/SOUL.md")

    for label, path in [
        ("default profile (~/.hermes/SOUL.md)", server_soul),
        ("local profile (~/.hermes/profiles/local/SOUL.md)", local_soul),
    ]:
        print(f"== {label} ==")
        if not path.exists():
            fails.append(f"{label}: file does not exist at {path}")
            print(f"  ✗ MISSING: {path}")
            continue
        text = path.read_text()
        h = hashlib.md5(text.encode()).hexdigest()
        print(f"  size={len(text)} bytes  md5={h}")
        for phrase in REQUIRED_PHRASES:
            ok = phrase in text
            mark = "✓" if ok else "✗"
            print(f"  {mark} contains: {phrase!r}")
            if not ok:
                fails.append(f"{label}: missing required phrase {phrase!r}")
        for marker in UPSTREAM_DEFAULT_MARKERS:
            bad = marker in text
            mark = "✓" if not bad else "✗"
            print(f"  {mark} does NOT contain upstream default: {marker!r}")
            if bad:
                fails.append(
                    f"{label}: contains upstream-default marker {marker!r} "
                    "(file was reseeded — restore canonical Luna persona)"
                )

    # Cross-check: default and local must be byte-identical.
    if server_soul.exists() and local_soul.exists():
        server_text = server_soul.read_text()
        local_text = local_soul.read_text()
        ok = server_text == local_text
        mark = "✓" if ok else "✗"
        print()
        print(f"== sync check ==")
        print(f"  {mark} ~/.hermes/SOUL.md == ~/.hermes/profiles/local/SOUL.md (byte-identical)")
        if not ok:
            fails.append("SOUL.md and profiles/local/SOUL.md diverged")

    print()
    if fails:
        print(f"== FAILED: {len(fails)} check(s) ==")
        for f in fails:
            print(f"  - {f}")
        return 1
    print("== PASS: canonical Luna SOUL.md is present at both locations and in sync ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())