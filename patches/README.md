# Maintaining voting patches

The `lrz/` trees are generated output. Do not commit a manual edit there
without a corresponding ordered patch in this directory: the next upstream
sync replaces each tree before reapplying its patch series.

Use:

- `patches/librustzcash/` for changes relative to
  `zcash/librustzcash`.
- `patches/orchard/` for changes relative to `zcash/orchard`.

Patch files are applied in filename order. Use names such as
`0001-expose-voting-selector.patch` and
`0002-add-wallet-snapshot-query.patch`.

## Start a patch

Start from the latest `wallet-libraries` main branch:

```bash
git switch main
git pull --ff-only
git switch -c feat/<change-name>
```

Read the source commit from `manifests/sources.toml`, then create a temporary
checkout of that exact upstream commit. For librustzcash:

```bash
repo_root="$(pwd)"
tmp="$(mktemp -d)"
source_commit="<librustzcash commit from manifests/sources.toml>"

git clone https://github.com/zcash/librustzcash.git "$tmp/librustzcash"
git -C "$tmp/librustzcash" checkout --detach "$source_commit"
```

For an Orchard patch, clone `https://github.com/zcash/orchard.git` and use the
Orchard commit from the manifest.

## Build on the existing patch series

Apply every existing patch to the temporary checkout:

```bash
for patch in "$repo_root"/patches/librustzcash/*.patch; do
  [ -e "$patch" ] || continue
  git -C "$tmp/librustzcash" apply "$patch"
done
```

Stage that state without committing it:

```bash
git -C "$tmp/librustzcash" add -A
```

The index now represents the existing patch series. Subsequent
`git diff` output contains only the new change.

Make and test the new source change inside the temporary checkout. Generate
the next patch:

```bash
git -C "$tmp/librustzcash" diff --check
git -C "$tmp/librustzcash" diff --binary \
  > "$repo_root/patches/librustzcash/0002-<description>.patch"
```

Choose the next available numeric prefix. Replace `librustzcash` with
`orchard` in the paths for an Orchard patch.

Inspect the generated file before continuing:

```bash
git -C "$tmp/librustzcash" diff --stat
less "$repo_root/patches/librustzcash/0002-<description>.patch"
```

## Regenerate and verify

Regenerate the checked-in source trees from their pinned upstream commits.
This step proves that the complete patch series applies cleanly:

```bash
cd "$repo_root"
./scripts/sync-upstream.sh
./scripts/verify-zcash-voting.sh
git diff --check
git status --short
```

Commit both:

1. The new file under `patches/<source>/`.
2. The regenerated files under `lrz/<source>/`.

The checked-in source makes one git revision directly consumable by Cargo;
the patch series makes the source reproducible after future upstream updates.

CI enforces this: every pull request regenerates `lrz/` from the pins and
fails if the result differs from what is committed.

## Updating an existing patch

Prefer adding a new patch when a later change depends on a patch that has
already shipped. Rewrite an existing patch only to fix or replace that patch
before release.

To rewrite one, reproduce the series only through the patch immediately before
it, stage that state, implement the corrected result, and regenerate the patch
at the same filename. Then run the full regeneration and verification sequence.

## Moving to a new upstream release

Run the sync workflow or pass new refs directly:

```bash
./scripts/sync-upstream.sh \
  librustzcash=<new-tag-or-commit> \
  orchard=<new-tag-or-commit>
```

If a patch no longer applies:

1. Check whether upstream now includes the change. If so, remove the obsolete
   patch and sync again.
2. Otherwise, regenerate the patch against the new pinned source while
   preserving its intent.

Never resolve a sync failure by editing only `lrz/`; that edit would disappear
on the next sync.

After merging a patch or upstream update, consumers must update every
`wallet-libraries` Cargo patch entry to the new repository commit. Cargo
`[patch]` settings are not inherited transitively, so `zcash_voting` and each
wallet workspace require their own revision update.
