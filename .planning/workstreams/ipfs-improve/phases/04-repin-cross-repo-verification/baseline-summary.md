# D-11 Pre-Repin Baseline Summary (Phase 4 / Plan 04-01 / Task 2)

Captured: 2026-10-14 (execute-phase 4 session), BEFORE any integrated-tree rebuild.
Per CONTEXT D-10/D-11: the four focus exes below are Sep-15, 2026 builds that statically
embed pre-fix thirdparty lib content - running them as-is IS the pre-repin baseline.
The repinned runs (04-03) must add ZERO new failures vs the per-case ledger below (D-13
flake policy: retry once + document).

## Baseline exe provenance

| Exe | Length (bytes) | LastWriteTime |
|-----|----------------|---------------|
| pubsub_counts_test.exe | 33183232 | 9/15/2026 3:13:01 PM |
| globaldb_integration_test.exe | 55501312 | 9/15/2026 3:13:44 PM |
| pubsub_graphsync_test.exe | 169004032 | 9/15/2026 3:19:46 PM |
| transaction_sync_test.exe | 169166336 | 9/15/2026 3:19:22 PM |

## No-rebuild assertion (pre-run)

Deployed thirdparty libs at baseline capture time (pre-repin mixed state, unchanged from
04-RESEARCH Runtime State):

| Deployed lib | LastWriteTime | State |
|--------------|---------------|-------|
| p2p_gossip.lib | 10/13/2026 6:45:31 PM | fix content (Phase 3 rebuild) |
| ipfs-pubsub.lib | 10/2/2026 4:24:33 PM | pre-fix |
| ipfs-bitswap-cpp.lib | 9/29/2026 1:53:58 PM | pre-fix |

## Per-target pre-existing-red ledger

(ledger filled from Select-String extraction after the runs - never read wholesale)

| Target | Ran | Passed | Failed | Exit | Pre-existing red cases | Notes |
|--------|-----|--------|--------|------|------------------------|-------|
| pubsub_counts_test | 1 | 1 | 0 | 0 | (none) | CRDT/PubSub path |
| globaldb_integration_test | 9 | 9 | 0 | 0 | (none) | CRDT/PubSub path (crdt suite's pubsub consumer) |
| pubsub_graphsync_test | 1 | 1 | 0 | 0 | (none) | DAG-syncer path |
| transaction_sync_test | 6 | 6 | 0 | 0 | (none) | AccountMessenger path |

Zero `^\[  FAILED  \]` case lines across all four logs (Select-String extraction).

**A3/OQ3 contingency: NOT triggered** - transaction_sync_test ran to completion (6/6 PASSED,
exit 0), so no fifth substitute target (`genius_node_bootstrap_reconnect_test`) enters the
set; no fifth baseline log exists.

**D-11 implication for 04-03:** the baseline is fully green, so the no-new-failures bar
degenerates to "the repinned runs must also be fully green" - any failed case at repin time
is by definition a NEW failure (D-13 retry-once policy applies before that classification).

Post-run exe mtime check: pubsub_counts_test.exe 9/15/2026 3:13:01 PM,
transaction_sync_test.exe 9/15/2026 3:19:22 PM - unchanged (nothing rebuilt the baseline
exes during capture; D-11 ordering intact).

