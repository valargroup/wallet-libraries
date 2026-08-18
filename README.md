# Valargroup wallet libraries

Upstream-compatible Rust library trees for wallets that integrate Zcash
voting.

This repository keeps the original Cargo package names (`zcash_*`, `orchard`,
and related crates), so a wallet can select the whole compatible graph with
Cargo `[patch.crates-io]` entries pinned to one git revision. The wallet and
LRZ crates retain their upstream source identities while the proving stack uses
the source from Zakura's optimized libraries.

## Why this is separate from `zakura-core/libraries`

[`zakura-core/libraries`](https://github.com/zakura-core/libraries) is
Zakura's product fork of the proving stack. Its packages are intentionally
published under `zakura-*` names. That is the right model for Zakura, but
those names cannot replace the upstream-named packages in wallets that still
consume `zcash_voting` and librustzcash crates.

This repository is the compatibility counterpart:

- LRZ releases are copied from official Zcash upstream tags;
- the proving stack tracks a pinned Zakura source revision but retains the
  original package names and versions;
- all source identities are selected together by the consuming workspace;
- CI proves that the pinned `zcash_voting` revision builds against the result.

It does not replace `zakura-core/libraries`,
`valargroup/librustzcash`, or the local orchestration in
`valargroup/shielded-vote-workspace`.

## Current baseline

Pins are recorded in [`manifests/sources.toml`](manifests/sources.toml):

- `zcash/librustzcash` at `zcash_client_sqlite-0.22.0-rc.7`
- `zakura-core/libraries` at
  `80a5dd73bc12f6a513c6afd14488911f11f2a9db`
- `valargroup/zcash_voting` at a fixed commit on its 3.0.0 line

The selected librustzcash tag contains the matching versions of
`zcash_client_backend`, `zcash_client_sqlite`, `zcash_keys`,
`zcash_primitives`, `zcash_protocol`, and `pczt`.

The imported Zakura source covers `orchard`, the Halo2 family, Pasta curves,
RedDSA/RedJubjub, Sapling, and Sinsemilla. Package identities come from the
final pre-rename Zakura revision; Orchard retains its official 0.15.5 manifest,
and all implementation source matches the pinned current Zakura revision.

## Layout

```text
lrz/
  librustzcash/       vendored zcash/librustzcash release tree
  orchard/            upstream-named Zakura Orchard source
  halo2_*/            upstream-named Zakura Halo2 source
  pasta_curves/       upstream-named Zakura Pasta source
  ...                 remaining compatible proving-stack packages
patches/
  librustzcash/       ordered patches relative to the LRZ repository root
  orchard/            ordered patches relative to the Orchard repository root
manifests/
  sources.toml        upstream refs and immutable peeled commits
scripts/
  sync-upstream.sh
  apply-patches.sh
  verify-zakura-import.sh
  verify-zcash-voting.sh
consumers/
  zcash_voting.patch.example.toml
```

The sources are copied into the repository rather than added as submodules.
This makes a single git revision a complete Cargo source. The sync workflow can
refresh LRZ independently, while CI verifies that the Zakura implementation
snapshot still matches its immutable source pin.

## Verify the voting build

```bash
./scripts/verify-zakura-import.sh
./scripts/verify-zcash-voting.sh
```

The script checks out the pinned voting revision in a temporary directory,
injects local path patches, and checks both `zcash_voting` and
`vote-commitment-tree`. Cargo follows LRZ's internal path dependencies, keeping
the transitive LRZ closure on the same source tree.

## Consume from a wallet

For local development, copy the entries from
[`consumers/zcash_voting.patch.example.toml`](consumers/zcash_voting.patch.example.toml)
and adjust the relative paths.

For a remote consumer, point every entry at the same repository revision:

```toml
[patch.crates-io]
halo2_gadgets = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
halo2_legacy_pdqsort = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
halo2_poseidon = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
halo2_proofs = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
orchard = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
pasta_curves = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
reddsa = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
redjubjub = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
sapling-crypto = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
sinsemilla = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
pczt = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_client_backend = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_client_sqlite = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_keys = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_pool_migration = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_primitives = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_proofs = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
zcash_protocol = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>" }
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

Move the LRZ pin to a new tag or commit:

```bash
./scripts/sync-upstream.sh \
  librustzcash=zcash_client_sqlite-0.22.0
```

An override updates both the human-readable ref and its resolved commit in
`manifests/sources.toml`. The script then replaces the vendored tree and
reapplies ordered `*.patch` files. Run voting verification before accepting
the result.

The **Sync upstream releases** GitHub workflow performs the same operation,
verifies the Zakura source snapshot and voting compatibility, and opens a
reviewable pull request. It does not auto-merge upstream updates.
