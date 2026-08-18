#!/usr/bin/env bash
set -euo pipefail

# Apply the ordered patch series for one vendored crate, if it has one.
# Patches are generated relative to the crate directory, not the upstream
# repository root, because only the crate directory is vendored.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate_path="${1:-}"

if [[ -z "$crate_path" ]]; then
  echo "usage: $0 <crate-directory-name>" >&2
  exit 2
fi

source_dir="$repo_root/crates/$crate_path"
patch_dir="$repo_root/patches/$crate_path"

if [[ ! -d "$source_dir" ]]; then
  echo "vendored crate does not exist: $source_dir" >&2
  exit 1
fi

if [[ ! -d "$patch_dir" ]]; then
  exit 0
fi

shopt -s nullglob
patches=("$patch_dir"/*.patch)

for patch in "${patches[@]}"; do
  echo "Applying ${patch#"$repo_root/"}"
  git -C "$source_dir" apply --check "$patch"
  git -C "$source_dir" apply "$patch"
done
