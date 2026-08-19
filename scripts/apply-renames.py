#!/usr/bin/env python3
"""Rename a vendored crate to its published `zakura-*` package name.

Usage: apply-renames.py <repo-root>

Only `[package] name` changes. The library target keeps the upstream name, so
`use zcash_client_backend::...` continues to resolve inside the crate's own
tests and benches, and a consumer that declares the dependency with
`package = "zakura-client-backend"` keeps the upstream key as well. This is the
convention `zakura-core/libraries` already uses for its crates.
"""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

PACKAGE_NAME = re.compile(r'^name = "(?P<name>[^"]+)"$', re.MULTILINE)
LIB_SECTION = re.compile(r"^\[lib\]$", re.MULTILINE)


def rename(manifest_path: Path, upstream_name: str, package: str) -> None:
    text = manifest_path.read_text()

    # The first `name = "..."` in the file belongs to [package]; later ones
    # belong to [lib], [[bin]], [[bench]] and must not be touched.
    text, count = PACKAGE_NAME.subn(f'name = "{package}"', text, count=1)
    if count != 1:
        raise SystemExit(f"{manifest_path}: no [package] name to rename")

    # Unless the library target already names itself, give it the upstream name
    # explicitly; otherwise it would inherit the renamed package name.
    if not re.search(rf'^name = "{re.escape(upstream_name)}"$', text, flags=re.MULTILINE):
        match = LIB_SECTION.search(text)
        if match:
            insert = match.end() + 1
            text = text[:insert] + f'name = "{upstream_name}"\n' + text[insert:]
        else:
            text = text.rstrip() + f'\n\n[lib]\nname = "{upstream_name}"\n'

    manifest_path.write_text(text)


def link_vendored_paths(manifest_path: Path, renamed: dict[str, str]) -> None:
    """Teach sibling path dependencies the new package name of their target.

    A vendored crate may depend on another by relative path (`{ path =
    "../zcash_pool_migration" }`). Renaming the target breaks that edge unless
    the dependency also names the package, so add it while leaving the
    dependency key — and therefore the crate's source — untouched.
    """
    text = original = manifest_path.read_text()

    for upstream_name, package in renamed.items():
        # The inline table may span lines, because a `features = [...]` array
        # inside it is allowed to; match up to its closing brace either way.
        pattern = re.compile(
            rf'^(?P<key>[A-Za-z0-9_-]+) = \{{(?P<fields>[^{{}}]*?'
            rf'path = "\.\./{re.escape(upstream_name)}"[^{{}}]*?)\}}',
            re.MULTILINE,
        )

        def add_package(match: re.Match[str]) -> str:
            if "package = " in match.group("fields"):
                return match.group(0)
            fields = match.group("fields").rstrip().rstrip(",")
            return f'{match.group("key")} = {{{fields}, package = "{package}" }}'

        text = pattern.sub(add_package, text)

    if text != original:
        manifest_path.write_text(text)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    repo_root = Path(argv[1])
    with (repo_root / "manifests" / "sources.toml").open("rb") as manifest_file:
        manifest = tomllib.load(manifest_file)
    crates = manifest["crate"]
    vendored_root = repo_root / manifest["layout"]["vendored_directory"]

    renamed: dict[str, str] = {}
    for crate in crates:
        manifest_path = vendored_root / crate["path"] / "Cargo.toml"
        if not manifest_path.is_file():
            raise SystemExit(f"vendored crate is missing: {manifest_path}")
        if "package" not in crate:
            continue  # Vendored unpublished; upstream name is kept.
        rename(manifest_path, crate["path"], crate["package"])
        renamed[crate["path"]] = crate["package"]
        print(f"renamed {crate['path']} -> {crate['package']}")

    for crate in crates:
        link_vendored_paths(vendored_root / crate["path"] / "Cargo.toml", renamed)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
