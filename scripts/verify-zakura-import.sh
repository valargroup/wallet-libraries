#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/manifests/sources.toml"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/wallet-libraries-zakura.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

read -r zakura_url source_commit metadata_commit < <(
  python3 - "$manifest" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as source_file:
    zakura = tomllib.load(source_file)["zakura"]

print(zakura["url"], zakura["source_commit"], zakura["metadata_commit"])
PY
)

packages=()
while IFS= read -r package_name; do
  packages+=("$package_name")
done < <(
  python3 - "$manifest" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as source_file:
    packages = tomllib.load(source_file)["zakura"]["packages"]

print("\n".join(packages))
PY
)

checkout="$tmp_root/libraries"
git init --quiet "$checkout"
git -C "$checkout" remote add origin "$zakura_url"
git -C "$checkout" fetch --quiet --depth=1 origin "$source_commit"
git -C "$checkout" fetch --quiet --depth=1 origin "$metadata_commit"
git -C "$checkout" checkout --quiet --detach "$source_commit"

for package_name in "${packages[@]}"; do
  imported="$repo_root/lrz/$package_name"
  source_package="$checkout/$package_name"

  if [[ ! -f "$imported/Cargo.toml" || ! -d "$source_package/src" ]]; then
    echo "missing imported or source package: $package_name" >&2
    exit 1
  fi

  for source_dir_name in src tests benches; do
    if [[ -d "$source_package/$source_dir_name" || -d "$imported/$source_dir_name" ]]; then
      if [[ "$package_name" == "orchard" && "$source_dir_name" == "benches" ]]; then
        diff -qr -x README.md "$source_package/$source_dir_name" "$imported/$source_dir_name"
        sed 's/zakura-orchard/orchard/g' "$source_package/benches/README.md" \
          | cmp - "$imported/benches/README.md"
      else
        diff -qr "$source_package/$source_dir_name" "$imported/$source_dir_name"
      fi
    fi
  done

  if [[ -f "$source_package/build.rs" || -f "$imported/build.rs" ]]; then
    cmp "$source_package/build.rs" "$imported/build.rs"
  fi

  for license_file in "$source_package"/LICENSE*; do
    if [[ -f "$license_file" ]]; then
      cmp "$license_file" "$imported/$(basename "$license_file")"
    fi
  done

  case "$package_name" in
    halo2_proofs|orchard|sinsemilla)
      ;;
    *)
      git -C "$checkout" show "$metadata_commit:$package_name/Cargo.toml" \
        | cmp - "$imported/Cargo.toml"
      ;;
  esac
done

python3 - "$repo_root" <<'PY'
import sys
import tomllib
from pathlib import Path

repo_root = Path(sys.argv[1])
expected = {
    "halo2_gadgets": ("halo2_gadgets", "0.5.0"),
    "halo2_legacy_pdqsort": ("halo2_legacy_pdqsort", "0.1.0"),
    "halo2_poseidon": ("halo2_poseidon", "0.1.0"),
    "halo2_proofs": ("halo2_proofs", "0.3.5"),
    "orchard": ("orchard", "0.15.5"),
    "pasta_curves": ("pasta_curves", "0.5.2"),
    "reddsa": ("reddsa", "0.5.2"),
    "redjubjub": ("redjubjub", "0.8.0"),
    "sapling-crypto": ("sapling-crypto", "0.7.0"),
    "sinsemilla": ("sinsemilla", "0.1.0"),
}

for directory, package_identity in expected.items():
    with (repo_root / "lrz" / directory / "Cargo.toml").open("rb") as manifest_file:
        package = tomllib.load(manifest_file)["package"]
    actual = (package["name"], package["version"])
    if actual != package_identity:
        raise SystemExit(f"unexpected package identity for {directory}: {actual}")
PY
