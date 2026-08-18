#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_name="${1:-}"

if [[ -z "$source_name" ]]; then
  echo "usage: $0 <source-name>" >&2
  exit 2
fi

source_dir="$repo_root/lrz/$source_name"
patch_dir="$repo_root/patches/$source_name"

if [[ ! -d "$source_dir" ]]; then
  echo "source tree does not exist: $source_dir" >&2
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
