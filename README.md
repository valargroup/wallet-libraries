# Valargroup wallet libraries

Upstream-compatible Rust library trees for wallets that integrate Zcash
voting.

This repository keeps the original Cargo package names (`zcash_*`, `orchard`,
and related crates), so a wallet can select the whole compatible graph with
Cargo `[patch.crates-io]` entries pinned to one git revision.

## Why this is separate from `zakura-core/libraries`

[`zakura-core/libraries`](https://github.com/zakura-core/libraries) is
Zakura's product fork of the proving stack. Its packages are intentionally
published under `zakura-*` names. That is the right model for Zakura, but
those names cannot replace the upstream-named packages in wallets that still
consume `zcash_voting` and librustzcash crates.

This repository is the compatibility counterpart:

- source trees retain their upstream names and layout;
- releases are copied from official Zcash upstream tags;
- voting-specific changes, if needed, live as a small, reviewable patch set;
- CI proves that the pinned `zcash_voting` revision builds against the result.

It does not replace `zakura-core/libraries`,
`valargroup/librustzcash`, or the local orchestration in
`valargroup/shielded-vote-workspace`.

## Current baseline

Pins are recorded in [`manifests/sources.toml`](manifests/sources.toml):

- `zcash/librustzcash` at `zcash_client_sqlite-0.22.0-rc.7`
- `zcash/orchard` at `0.15.5`
- `valargroup/zcash_voting` at a fixed commit on its 3.0.0 line

The selected librustzcash tag contains the matching versions of
`zcash_client_backend`, `zcash_client_sqlite`, `zcash_keys`,
`zcash_primitives`, `zcash_protocol`, and `pczt`.

The initial prototype requires **no functional patches**. Clean upstream
sources build `zcash_voting` and `vote-commitment-tree`; the patch directories
are ready for the first voting-only delta that cannot be carried upstream.

## Layout

```text
lrz/
  librustzcash/       vendored zcash/librustzcash release tree
  orchard/            vendored zcash/orchard release tree
patches/
  librustzcash/       ordered patches relative to the LRZ repository root
  orchard/            ordered patches relative to the Orchard repository root
manifests/
  sources.toml        upstream refs and immutable peeled commits
scripts/
  sync-upstream.sh
  apply-patches.sh
  verify-zcash-voting.sh
  discover-upstream-updates.py
  inject-patch-entries.py
consumers/
  zcash_voting.patch.example.toml
```

The sources are copied into the repository rather than added as submodules.
This makes a single git revision a complete Cargo source and lets the sync
workflow reapply a small patch series deterministically.

See [`patches/README.md`](patches/README.md) for the complete procedure for
creating, extending, regenerating, and retiring voting patches.

## Verify the voting build

```bash
./scripts/verify-zcash-voting.sh
```

The script checks out the pinned voting revision in a temporary directory,
injects local path patches, and checks both `zcash_voting` and
`vote-commitment-tree`. Cargo follows LRZ's internal path dependencies, keeping
the transitive LRZ closure on the same source tree.

A successful check is not by itself proof that the vendored sources were used.
Cargo drops a `[patch]` entry whose version cannot satisfy the consumer's
requirement with a warning, then builds against the registry copy, so a pin
moved to a semver-incompatible release would otherwise pass silently. The
script therefore also fails when any patch entry goes unused, and reads
`cargo metadata` to confirm that every patched package resolves to exactly one
copy inside `lrz/`.

## Consume from a wallet

For local development, copy the entries from
[`consumers/zcash_voting.patch.example.toml`](consumers/zcash_voting.patch.example.toml)
and adjust the relative paths.

For a remote consumer, point every entry at the same repository revision:

```toml
[patch.crates-io]
zcash_client_backend = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_client_sqlite = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_keys = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_primitives = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_protocol = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
pczt = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
orchard = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
```

Cargo searches nested directories in git dependencies by package name, so the
`lrz/` subdirectory does not appear in the remote form.

All patched packages must use the same revision. Mixing registry and vendored
copies of packages that exchange public types can produce incompatible Rust
types even when the package versions match.

## Sync an upstream release

Refresh the currently pinned trees:

```bash
./scripts/sync-upstream.sh
```

Move either pin to a new tag or commit:

```bash
./scripts/sync-upstream.sh \
  librustzcash=zcash_client_sqlite-0.22.0 \
  orchard=0.16.0
```

An override updates both the human-readable ref and its resolved commit in
`manifests/sources.toml`. The script then replaces the vendored tree and
reapplies ordered `*.patch` files. Run voting verification before accepting
the result.

## Automatic upstream updates

The **Sync upstream releases** workflow runs daily. It lists the tags of each
source, keeps those matching the source's `tag_pattern` in
`manifests/sources.toml`, and compares the highest semantic version against the
current pin. `allow_prerelease` decides whether a prerelease tag may be
proposed automatically; librustzcash allows it because the voting pin currently
tracks a release candidate.

Each source with a newer release is synced, verified, and raised as its own
pull request on a long-lived `automation/upstream-sync/<source>` branch, so a
failing update never blocks the other source and a later tag updates the open
pull request instead of opening a second one. Nothing is auto-merged.

Running the workflow by hand does the same discovery; filling in an input pins
that source to an explicit tag or commit, which is how a prerelease or an
older release gets selected deliberately.

Reproducing the same discovery locally:

```bash
./scripts/discover-upstream-updates.py
```

Pull requests created with the default `GITHUB_TOKEN` do not trigger other
workflows, so a sync pull request shows no checks even though the sync job
verified the result before opening it. Setting an `UPSTREAM_SYNC_TOKEN` secret
that may open pull requests makes `verify.yml` run on the branch as well.

## Generated trees

`lrz/` is generated output: the pinned upstream commit plus the ordered patch
series. CI regenerates it on every pull request and fails if the result differs
from what is committed, because a hand edit under `lrz/` would otherwise
survive review and disappear at the next sync.
