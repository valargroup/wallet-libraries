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

for path in \
  "$repo_root/lrz/librustzcash/pczt" \
  "$repo_root/lrz/librustzcash/zcash_client_backend" \
  "$repo_root/lrz/librustzcash/zcash_client_sqlite" \
  "$repo_root/lrz/librustzcash/zcash_keys" \
  "$repo_root/lrz/librustzcash/zcash_primitives" \
  "$repo_root/lrz/librustzcash/components/zcash_protocol" \
  "$repo_root/lrz/orchard"; do
  if [[ ! -f "$path/Cargo.toml" ]]; then
    echo "missing synced crate: $path" >&2
    exit 1
  fi
done

python3 - "$checkout/Cargo.toml" "$repo_root" <<'PY'
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
text = manifest_path.read_text()

patches = {
    "pczt": repo_root / "lrz/librustzcash/pczt",
    "zcash_client_backend": repo_root / "lrz/librustzcash/zcash_client_backend",
    "zcash_client_sqlite": repo_root / "lrz/librustzcash/zcash_client_sqlite",
    "zcash_keys": repo_root / "lrz/librustzcash/zcash_keys",
    "zcash_primitives": repo_root / "lrz/librustzcash/zcash_primitives",
    "zcash_protocol": repo_root / "lrz/librustzcash/components/zcash_protocol",
    "orchard": repo_root / "lrz/orchard",
}
entries = "".join(
    f'{name} = {{ path = "{path}" }}\n' for name, path in patches.items()
)

heading = "[patch.crates-io]"
if heading in text:
    start = text.index(heading) + len(heading)
    section_end = text.find("\n[", start)
    if section_end == -1:
        section_end = len(text)
    text = text[:section_end].rstrip() + "\n" + entries + text[section_end:]
else:
    text = text.rstrip() + f"\n\n{heading}\n" + entries

manifest_path.write_text(text)
PY

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$repo_root/target/verify-zcash-voting}"
cargo check \
  --manifest-path "$checkout/Cargo.toml" \
  --package zcash_voting \
  --package vote-commitment-tree
