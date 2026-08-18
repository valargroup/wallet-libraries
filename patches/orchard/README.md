# Orchard patches

Place ordered `*.patch` files in this directory when voting requires a delta
from the pinned upstream release. Patches must be generated relative to the
root of the upstream `zcash/orchard` repository.

The initial prototype intentionally carries no functional patch. Orchard
0.15.5 exposes the `unstable-voting-circuits` feature required by
`zcash_voting` and `voting-circuits`.
