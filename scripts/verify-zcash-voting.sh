#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/manifests/sources.toml"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/wallet-libraries-verify.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

read -r voting_url voting_rev < <(
  python3 - "$manifest" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as source_file:
    consumer = tomllib.load(source_file)["consumer"]["zcash_voting"]

print(consumer["url"], consumer["rev"])
PY
)

checkout="$tmp_root/zcash_voting"
git init --quiet "$checkout"
git -C "$checkout" remote add origin "$voting_url"
git -C "$checkout" fetch --quiet --depth=1 origin "$voting_rev"
git -C "$checkout" checkout --quiet --detach FETCH_HEAD

# The vendored package set has a single definition, in the injection script.
vendored_names=()
vendored_paths=()
while IFS=$'\t' read -r name path; do
  vendored_names+=("$name")
  vendored_paths+=("$path")
done < <(python3 "$repo_root/scripts/inject-patch-entries.py" --list "$repo_root")

for path in "${vendored_paths[@]}"; do
  if [[ ! -f "$path/Cargo.toml" ]]; then
    echo "missing synced crate: $path" >&2
    exit 1
  fi
done

# Redirect every patched package at the vendored trees.
python3 "$repo_root/scripts/inject-patch-entries.py" \
  "$checkout/Cargo.toml" "$repo_root"

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$repo_root/target/verify-zcash-voting}"
check_log="$tmp_root/cargo-check.log"

set +e
cargo check \
  --manifest-path "$checkout/Cargo.toml" \
  --package zcash_voting \
  --package vote-commitment-tree \
  2>&1 | tee "$check_log"
check_status="${PIPESTATUS[0]}"
set -e

if [[ "$check_status" -ne 0 ]]; then
  exit "$check_status"
fi

# A `[patch]` entry whose version cannot satisfy the consumer's requirement is
# a warning, not an error: Cargo silently resolves the registry copy and the
# check still passes. Moving a pin to a semver-incompatible release is exactly
# the case this script exists to catch, so treat it as a failure.
if grep -q "was not used in the crate graph" "$check_log"; then
  echo >&2
  echo "at least one [patch.crates-io] entry was not used; the vendored" >&2
  echo "sources did not take part in this build" >&2
  exit 1
fi

# Independently confirm the resolved graph: every patched package must resolve
# to the vendored tree, and to exactly one copy of it. Two copies of a package
# that exchanges public types produce incompatible Rust types downstream.
cargo metadata \
  --format-version 1 \
  --manifest-path "$checkout/Cargo.toml" \
  > "$tmp_root/metadata.json"

python3 - "$tmp_root/metadata.json" "$repo_root" "${vendored_names[@]}" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text())
vendored_root = Path(sys.argv[2]) / "lrz"
expected = set(sys.argv[3:])

resolved: dict[str, list[Path]] = {name: [] for name in expected}
for package in metadata["packages"]:
    if package["name"] in expected:
        resolved[package["name"]].append(Path(package["manifest_path"]))

problems = []
for name, manifests in sorted(resolved.items()):
    if not manifests:
        problems.append(f"{name}: not present in the resolved graph")
        continue
    if len(manifests) > 1:
        locations = ", ".join(str(path) for path in sorted(manifests))
        problems.append(f"{name}: resolved to {len(manifests)} copies: {locations}")
        continue
    if not manifests[0].is_relative_to(vendored_root):
        problems.append(f"{name}: resolved outside the vendored trees: {manifests[0]}")

if problems:
    print("resolved graph does not match the vendored sources:", file=sys.stderr)
    for problem in problems:
        print(f"  {problem}", file=sys.stderr)
    raise SystemExit(1)

print("verified: all patched packages resolve to the vendored trees")
PY
