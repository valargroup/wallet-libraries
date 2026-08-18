# Zakura wallet libraries

The wallet layer of the Zakura stack: the librustzcash crates a wallet needs
that [`zakura-core/libraries`](https://github.com/zakura-core/libraries) does
not already ship, forked and rewired onto the published `zakura-*` crypto
crates.

`libraries` covers the proving stack and the crates that sit directly on top of
it — `zakura-primitives`, `zakura-keys`, `zakura-proofs`, `zakura-orchard`, the
halo2 family. It stops below the wallet layer, so a wallet consuming it still
resolves `zcash_client_backend` and `zcash_client_sqlite` from crates.io, which
drags the crates.io `orchard` and `zcash_primitives` back into the graph
alongside their Zakura forks. This repository closes that gap.

## What is vendored

| Directory | Published as | Forked from |
| --- | --- | --- |
| `librustzcash/pczt` | `zakura-pczt` | `zcash/librustzcash` |
| `librustzcash/zcash_client_backend` | `zakura-client-backend` | `zcash/librustzcash` |
| `librustzcash/zcash_client_sqlite` | `zakura-client-sqlite` | `zcash/librustzcash` |
| `librustzcash/zcash_pool_migration` | `zakura-pool-migration` | `zcash/librustzcash` |
| `librustzcash/zcash_pool_migration_memory` | not published | `zcash/librustzcash` |

Directory names and library target names keep their upstream spelling, so crate
sources and `use` paths are untouched; only the package name changes. This is
the convention `libraries` already follows.

**Membership rule.** A crate belongs here when it depends on the renamed crypto
stack and `libraries` does not already ship it. A crate that `zakura-*` resolves
from crates.io must *not* be vendored here — two copies of a package whose types
cross the boundary are two different types, and the build only fails later, in a
consumer. `zcash_address`, `zip321`, `zcash_protocol`, `zcash_transparent`,
`zcash_encoding` and `equihash` therefore stay on crates.io.

`zcash_pool_migration_memory` is the one exception to the naming rule: it is a
test-only path dev-dependency of `zcash_pool_migration`, and Cargo drops
path-only dev-dependencies when publishing, so it is never published and keeps
its upstream name.

## Layout

Three directories, following the split Dev sketched:

```text
librustzcash/   forked upstream crates   generated; sync deletes and rewrites it
compat/         the backend selector     hand-written
zakura/         new Zakura work          hand-written; empty for now
```

Only `librustzcash/` and the root `Cargo.toml` are generated. Anything
hand-written goes in `compat/` or `zakura/` and is listed in
`layout.extra_members` in `manifests/sources.toml`, which the workspace
generator appends to the members it produces — a crate placed under
`librustzcash/` would be deleted by the next sync.

## How the rewiring works

Nothing is patched at the source level. `manifests/sources.toml` holds a
`[rewire]` table, and the generated root `Cargo.toml` turns each entry into a
Cargo dependency rename:

```toml
orchard = { version = "1.0.0-rc.1", package = "zakura-orchard" }
```

The dependency key stays `orchard`, so every `orchard::` path in the vendored
sources keeps compiling, while the package that satisfies it is the fork. The
vendored crates inherit these through `workspace = true`, which is why the fork
currently carries **no source patches at all**.

There is no `[patch.crates-io]` anywhere in this design. Package names differ
from their upstream originals, so consumers declare these crates directly and
every edge is explicit — the same reasoning `libraries` documents.

## Verify

```bash
./scripts/verify-zakura-graph.sh
```

Checks the workspace with all targets and all features, then reads
`cargo metadata` to prove the resolved graph is Zakura-only: no crates.io
original of a forked crate is present, and no vendored crate appears twice.
Compiling alone would not prove this — an edge that escapes the rewiring builds
fine here and fails later where the two type families meet.

## Selecting a backend

`compat/` holds `zakura-wallet-deps`, which exists for code that has to build
for **both** ZODL and Vizor from one source tree — `zcash_voting` and the vote
commitment tree. It re-exports one family under stable names:

```rust
use zakura_wallet_deps::{client_backend, orchard};
```

```toml
# ZODL: upstream, the default
zakura-wallet-deps = "0.1"

# Vizor: the forks
zakura-wallet-deps = { version = "0.1", default-features = false, features = ["zakura"] }
```

The two features are mutually exclusive. Cargo features are additive and there
is no way to enable a dependency when a feature is *off*, so the upstream
family needs its own named feature rather than being the implicit
`not(zakura)` case — which is why selecting `zakura` also requires
`default-features = false`. Enabling both, or neither, is a compile error.

`scripts/verify-compat-modes.sh` builds it each way and fails if a crate from
the other family appears, or if the mutually-exclusive rules stop holding.

An end consumer that builds for exactly one stack does not need this crate at
all — it declares the packages it wants directly, as below.

## Consume from a wallet

Until these crates are published, pin them by git revision. The dependency keys
keep their upstream names, so wallet source needs no changes:

```toml
zcash_client_backend = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>", package = "zakura-client-backend" }
zcash_client_sqlite = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>", package = "zakura-client-sqlite" }
pczt = { git = "https://github.com/valargroup/wallet-libraries.git", rev = "<commit>", package = "zakura-pczt" }
```

The crypto stack comes from crates.io as `zakura-*`; do not also declare the
upstream crates.

## Sync an upstream release

```bash
./scripts/sync-upstream.sh                                  # refresh the pin
./scripts/sync-upstream.sh librustzcash=<tag-or-commit>     # move the pin
```

The script extracts the vendored crate directories and the upstream workspace
manifest at the pinned commit, regenerates the root `Cargo.toml` through
`scripts/generate-workspace.py`, applies the package renames, and reapplies any
patch series. `librustzcash/` and `Cargo.toml` are generated output; CI regenerates
them on every pull request and fails on drift.

## Automatic upstream updates

The **Sync upstream releases** workflow runs daily. It lists the upstream tags,
keeps those matching `tag_pattern` in `manifests/sources.toml` — the
`zcash_client_sqlite` release train, which is how `zcash_voting` selects its LRZ
version — and compares the highest semantic version against the current pin.
`allow_prerelease` decides whether a prerelease may be proposed automatically.

A newer release is synced, verified, and raised as a pull request on the
long-lived `automation/upstream-sync/librustzcash` branch. Nothing is
auto-merged. The same discovery runs locally:

```bash
./scripts/discover-upstream-updates.py
```

Pull requests created with the default `GITHUB_TOKEN` do not trigger other
workflows, so a sync pull request shows no checks even though the sync job
verified the result before opening it. Setting an `UPSTREAM_SYNC_TOKEN` secret
that may open pull requests makes `verify.yml` run on the branch as well.

## Files

```text
librustzcash/           vendored wallet-layer crates (generated)
compat/                 zakura-wallet-deps, the backend selector
zakura/                 new Zakura work
Cargo.toml              workspace manifest (generated)
patches/                ordered patches per crate, relative to the crate root
manifests/sources.toml  layout, upstream pin, crate list, rewiring rules
scripts/
  sync-upstream.sh            regenerate everything from the pin
  generate-workspace.py       root manifest from the upstream workspace
  apply-renames.py            package renames and sibling path links
  apply-patches.sh            ordered patch series for one crate
  verify-zakura-graph.sh      build and graph-purity check
  verify-compat-modes.sh      build the facade against each backend
  discover-upstream-updates.py
```

## Status

Not yet moved to the Zakura organization, and not yet published.
`zakura-pool-migration` still needs a name reservation in
`zakura-core/reserved`; the other published names are already reserved there.
