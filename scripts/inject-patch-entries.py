#!/usr/bin/env python3
"""Point a consumer manifest's `[patch.crates-io]` table at the vendored trees.

Usage: inject-patch-entries.py <consumer-Cargo.toml> <wallet-libraries-root>
       inject-patch-entries.py --list <wallet-libraries-root>

`--list` prints one `name<TAB>absolute-path` line per vendored package, so
callers can check the same set this script patches without repeating it.

Existing entries for the packages this repository vendors are removed before
the new ones are written: a released consumer already pins this repository by
git revision, and two entries for the same package in one `[patch.crates-io]`
table are a TOML duplicate-key error. Entries for other packages, and other
`[patch.*]` tables, are left untouched.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Package name -> path of the vendored crate, relative to the repository root.
VENDORED = {
    "pczt": "lrz/librustzcash/pczt",
    "zcash_client_backend": "lrz/librustzcash/zcash_client_backend",
    "zcash_client_sqlite": "lrz/librustzcash/zcash_client_sqlite",
    "zcash_keys": "lrz/librustzcash/zcash_keys",
    "zcash_primitives": "lrz/librustzcash/zcash_primitives",
    "zcash_protocol": "lrz/librustzcash/components/zcash_protocol",
    "orchard": "lrz/orchard",
}

HEADING = "[patch.crates-io]"
KEY_PATTERN = re.compile(r'^\s*(?:"([^"]+)"|([A-Za-z0-9_-]+))\s*=')
TABLE_PATTERN = re.compile(r"^\s*\[")


def rewrite(text: str, repo_root: Path) -> str:
    entries = [
        f'{name} = {{ path = "{repo_root / path}" }}'
        for name, path in VENDORED.items()
    ]

    kept: list[str] = []
    in_patch_table = False
    section_end: int | None = None

    for line in text.splitlines():
        if TABLE_PATTERN.match(line):
            if in_patch_table:
                # The `[patch.crates-io]` table ended at the previous kept line.
                section_end = len(kept)
            in_patch_table = line.strip() == HEADING

        if in_patch_table and line.strip() != HEADING:
            match = KEY_PATTERN.match(line)
            if match and (match.group(1) or match.group(2)) in VENDORED:
                continue

        kept.append(line)

    if in_patch_table:
        section_end = len(kept)

    if section_end is None:
        while kept and not kept[-1].strip():
            kept.pop()
        kept.extend(["", HEADING, *entries])
    else:
        trailing = [""] if section_end < len(kept) else []
        kept[section_end:section_end] = entries + trailing

    return "\n".join(kept) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    if argv[1] == "--list":
        repo_root = Path(argv[2])
        for name, path in VENDORED.items():
            print(f"{name}\t{repo_root / path}")
        return 0

    manifest_path = Path(argv[1])
    repo_root = Path(argv[2])
    manifest_path.write_text(rewrite(manifest_path.read_text(), repo_root))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
