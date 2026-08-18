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
  "$repo_root/lrz/halo2_gadgets" \
  "$repo_root/lrz/halo2_legacy_pdqsort" \
  "$repo_root/lrz/halo2_poseidon" \
  "$repo_root/lrz/halo2_proofs" \
  "$repo_root/lrz/orchard" \
  "$repo_root/lrz/pasta_curves" \
  "$repo_root/lrz/reddsa" \
  "$repo_root/lrz/redjubjub" \
  "$repo_root/lrz/sapling-crypto" \
  "$repo_root/lrz/sinsemilla" \
  "$repo_root/lrz/librustzcash/pczt" \
  "$repo_root/lrz/librustzcash/zcash_client_backend" \
  "$repo_root/lrz/librustzcash/zcash_client_sqlite" \
  "$repo_root/lrz/librustzcash/zcash_keys" \
  "$repo_root/lrz/librustzcash/zcash_pool_migration" \
  "$repo_root/lrz/librustzcash/zcash_primitives" \
  "$repo_root/lrz/librustzcash/zcash_proofs" \
  "$repo_root/lrz/librustzcash/components/zcash_protocol"; do
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
    "halo2_gadgets": repo_root / "lrz/halo2_gadgets",
    "halo2_legacy_pdqsort": repo_root / "lrz/halo2_legacy_pdqsort",
    "halo2_poseidon": repo_root / "lrz/halo2_poseidon",
    "halo2_proofs": repo_root / "lrz/halo2_proofs",
    "orchard": repo_root / "lrz/orchard",
    "pasta_curves": repo_root / "lrz/pasta_curves",
    "reddsa": repo_root / "lrz/reddsa",
    "redjubjub": repo_root / "lrz/redjubjub",
    "sapling-crypto": repo_root / "lrz/sapling-crypto",
    "sinsemilla": repo_root / "lrz/sinsemilla",
    "pczt": repo_root / "lrz/librustzcash/pczt",
    "zcash_client_backend": repo_root / "lrz/librustzcash/zcash_client_backend",
    "zcash_client_sqlite": repo_root / "lrz/librustzcash/zcash_client_sqlite",
    "zcash_keys": repo_root / "lrz/librustzcash/zcash_keys",
    "zcash_pool_migration": repo_root / "lrz/librustzcash/zcash_pool_migration",
    "zcash_primitives": repo_root / "lrz/librustzcash/zcash_primitives",
    "zcash_proofs": repo_root / "lrz/librustzcash/zcash_proofs",
    "zcash_protocol": repo_root / "lrz/librustzcash/components/zcash_protocol",
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

metadata="$tmp_root/metadata.json"
cargo metadata \
  --manifest-path "$checkout/Cargo.toml" \
  --format-version 1 \
  --locked > "$metadata"

python3 - "$metadata" "$repo_root" <<'PY'
import json
import sys
from pathlib import Path

metadata_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2]).resolve()
patched_names = {
    "halo2_gadgets",
    "halo2_legacy_pdqsort",
    "halo2_poseidon",
    "halo2_proofs",
    "orchard",
    "pasta_curves",
    "pczt",
    "reddsa",
    "redjubjub",
    "sapling-crypto",
    "sinsemilla",
    "zcash_client_backend",
    "zcash_client_sqlite",
    "zcash_keys",
    "zcash_pool_migration",
    "zcash_primitives",
    "zcash_proofs",
    "zcash_protocol",
}

metadata = json.loads(metadata_path.read_text())
resolved_ids = {node["id"] for node in metadata["resolve"]["nodes"]}
resolved = [package for package in metadata["packages"] if package["id"] in resolved_ids]
resolved_by_name = {
    name: [package for package in resolved if package["name"] == name]
    for name in patched_names
}

for name, packages in resolved_by_name.items():
    for package in packages:
        manifest_path = Path(package["manifest_path"]).resolve()
        if package["source"] is not None or repo_root not in manifest_path.parents:
            raise SystemExit(
                f"resolved {name} outside wallet-libraries: {package['id']}"
            )

required = patched_names - {"zcash_proofs"}
missing = sorted(name for name in required if not resolved_by_name[name])
if missing:
    raise SystemExit(f"patched packages missing from resolved graph: {', '.join(missing)}")
PY
