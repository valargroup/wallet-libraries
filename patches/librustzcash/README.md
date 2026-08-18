# librustzcash patches

Place ordered `*.patch` files in this directory when voting requires a delta
from the pinned upstream release. Patches must be generated relative to the
root of the upstream `zcash/librustzcash` repository.

See [`../README.md`](../README.md) for the patch creation and update workflow.

The initial prototype intentionally carries no functional patch. The selected
upstream release already contains the LRZ APIs required by the pinned
`zcash_voting` consumer.
