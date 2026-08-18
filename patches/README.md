# Maintaining source patches

`crates/` is generated output. Do not commit a manual edit there without a
corresponding ordered patch in this directory: the next upstream sync replaces
each crate directory before reapplying its patch series, and CI regenerates the
tree on every pull request and fails if the result differs from what is
committed.

There are currently **no patches**. The Zakura rewiring is expressed entirely
as dependency renames in `manifests/sources.toml`, which the generated root
`Cargo.toml` carries — this directory is for the first change that has to touch
crate source, such as a Vizor-specific tweak that cannot go upstream.

Use `patches/<crate-directory>/`, for example `patches/zcash_client_sqlite/`.
Patch files are applied in filename order, so name them
`0001-<description>.patch`.

## Start a patch

Patches are generated relative to the **crate directory**, not the upstream
repository root, because only the crate directories are vendored.

Start from the latest `main`:

```bash
git switch main
git pull --ff-only
git switch -c feat/<change-name>
```

Read the source commit from `manifests/sources.toml`, then create a temporary
checkout of that exact upstream commit:

```bash
repo_root="$(pwd)"
tmp="$(mktemp -d)"
source_commit="<commit from manifests/sources.toml>"

git clone https://github.com/zcash/librustzcash.git "$tmp/librustzcash"
git -C "$tmp/librustzcash" checkout --detach "$source_commit"
```

## Build on the existing patch series

Apply every existing patch for that crate, from inside the crate directory:

```bash
crate=zcash_client_sqlite
for patch in "$repo_root"/patches/$crate/*.patch; do
  [ -e "$patch" ] || continue
  git -C "$tmp/librustzcash/$crate" apply "$patch"
done
git -C "$tmp/librustzcash" add -A
```

The index now represents the existing series, so subsequent `git diff` output
contains only the new change.

Make and test the change inside the temporary checkout, then generate the next
patch — note the `--relative`, which is what keeps paths crate-relative:

```bash
git -C "$tmp/librustzcash" diff --check
git -C "$tmp/librustzcash/$crate" diff --binary --relative \
  > "$repo_root/patches/$crate/0001-<description>.patch"
```

Inspect the generated file before continuing.

## Regenerate and verify

This proves the complete series applies to a clean sync:

```bash
cd "$repo_root"
./scripts/sync-upstream.sh
./scripts/verify-zakura-graph.sh
git diff --check
git status --short
```

Commit both the new file under `patches/<crate>/` and the regenerated files
under `crates/<crate>/`.

## Updating an existing patch

Prefer adding a new patch when a later change depends on one that has already
shipped. To rewrite an existing patch, reproduce the series only through the
patch immediately before it, stage that state, implement the corrected result,
and regenerate the patch at the same filename. Then run the full regeneration
and verification sequence.

## Moving to a new upstream release

```bash
./scripts/sync-upstream.sh librustzcash=<new-tag-or-commit>
```

If a patch no longer applies:

1. check whether upstream now includes the change — if so, delete the obsolete
   patch and sync again;
2. otherwise regenerate it against the new pinned source, preserving its intent.

Never resolve a sync failure by editing `crates/` alone; that edit disappears at
the next sync.

## What does not belong here

Dependency rewiring. Pointing a crate at a `zakura-*` fork, or moving a
component from a local path to its crates.io release, is a rule in
`manifests/sources.toml` that `scripts/generate-workspace.py` applies to the
root manifest. Rules survive an upstream version bump; a patch against a
`Cargo.toml` line that upstream also edits does not.
