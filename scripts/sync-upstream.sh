#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/manifests/sources.toml"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/wallet-libraries-sync.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

declare -A overrides=()
for arg in "$@"; do
  if [[ "$arg" != *=* ]]; then
    echo "invalid override '$arg'; expected source=ref" >&2
    exit 2
  fi
  overrides["${arg%%=*}"]="${arg#*=}"
done

read_sources() {
  python3 - "$manifest" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as source_file:
    manifest = tomllib.load(source_file)

for source in manifest["source"]:
    fields = (
        source["name"],
        source["url"],
        source["ref"],
        source["commit"],
        source["destination"],
    )
    if any("\t" in value or "\n" in value for value in fields):
        raise SystemExit("source manifest fields may not contain tabs or newlines")
    print("\t".join(fields))
PY
}

update_pin() {
  local name="$1"
  local ref="$2"
  local commit="$3"

  python3 - "$manifest" "$name" "$ref" "$commit" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
name, ref, commit = sys.argv[2:]
text = path.read_text()
blocks = re.split(r"(?=^\[\[source\]\]$)", text, flags=re.MULTILINE)
updated = False

for index, block in enumerate(blocks):
    if re.search(rf'^name = "{re.escape(name)}"$', block, flags=re.MULTILINE):
        block = re.sub(r'^ref = ".*"$', f'ref = "{ref}"', block, flags=re.MULTILINE)
        block = re.sub(
            r'^commit = "[0-9a-f]{40}"$',
            f'commit = "{commit}"',
            block,
            flags=re.MULTILINE,
        )
        blocks[index] = block
        updated = True
        break

if not updated:
    raise SystemExit(f"source not found in manifest: {name}")

path.write_text("".join(blocks))
PY
}

while IFS=$'\t' read -r name url pinned_ref pinned_commit destination; do
  if [[ "$destination" != "lrz/$name" ]]; then
    echo "unsafe or unexpected destination for $name: $destination" >&2
    exit 1
  fi

  ref="${overrides[$name]:-$pinned_ref}"
  clone_dir="$tmp_root/$name.git"
  extract_dir="$tmp_root/$name"
  destination_dir="$repo_root/$destination"

  echo "Syncing $name from $url at $ref"
  git init --quiet "$clone_dir"
  git -C "$clone_dir" remote add origin "$url"
  git -C "$clone_dir" fetch --quiet --depth=1 origin "$ref"
  resolved_commit="$(git -C "$clone_dir" rev-parse "FETCH_HEAD^{commit}")"

  if [[ -z "${overrides[$name]:-}" && "$resolved_commit" != "$pinned_commit" ]]; then
    echo "resolved commit $resolved_commit does not match pinned commit $pinned_commit" >&2
    exit 1
  fi

  mkdir -p "$extract_dir"
  git -C "$clone_dir" archive "$resolved_commit" | tar -x -C "$extract_dir"

  rm -rf "${destination_dir:?}"
  mkdir -p "$(dirname "$destination_dir")"
  mv "$extract_dir" "$destination_dir"

  "$repo_root/scripts/apply-patches.sh" "$name"

  if [[ -n "${overrides[$name]:-}" ]]; then
    update_pin "$name" "$ref" "$resolved_commit"
  fi
done < <(read_sources)
