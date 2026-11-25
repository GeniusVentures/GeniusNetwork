---
phase: 15-evidence-aware-cold-serving-forced-walk-recovery
plan: 02
subsystem: testing
tags: [crdt, forced-walk, cold-storage, prune-evidence, graphsync, recovery, gtest]

requires:
  - phase: 15-01
    provides: "ColdReadFallback::LookupPruneEvidence single-predicate evidence classification (SC3/D-04), GlobalDB-installed callable, cold_evidence_matrix hermetic seeding recipes"
provides:
  - "D-05 walk evidence matrix live in ProcessForcedWalkCID (nullopt/Pruned skip, Malformed bad_message, NoEvidence fall-through to bounded fetch)"
  - "ForcedWalkStatus::walk_gaps counter + Error::FORCED_WALK_GAP + frontier-clearing abort routing in ProcessForcedWalkStep + Incomplete predicate/log in FinishForcedWalkLocked"
  - "GraphsyncDAGSyncer::kForcedWalkPeerFailoverPerCid = 8 (knob-free, derived) + bounded getNode(cid, budget) overload; 1-arg virtual delegates with the unbounded sentinel"
  - "GraphsyncDAGSyncer::LookupPruneEvidence(cid) -> optional<PruneEvidenceClass> walk consult accessor"
  - "Node-level behavioral proof of RECOVER-02/03/04 + cold-off posture: W1 restore / W2 pruned-skip / W3 gap-abort / W4 cold-off legs in node_startup_test"
affects: [15-03-failover-mesh, phase-17-probe, cold-serving, tx-pruner]

actuals:
  tokens: 12500   # chars/4 over the realized diff (907 added lines across the two SuperGenius commits)
  tasks: 2
  commits: 2      # SuperGenius: d6a2dc08b (Task 1), de37f79e8 (Task 2)

tech-stack:
  added: []
  patterns:
    - "Walk-passed budget parameter (sibling overload + unbounded-sentinel delegate) — no config knob, general getNode callers unchanged (D-06 / Phase-14 D-04 posture)"
    - "Counter-keyed abort routing: ProcessForcedWalkStep keys the gap abort off progress.walk_gaps, not error-value comparison"
    - "Node-level walk-leg fixture: full node parked at the trust-genesis gate so the full-nodes-topic listen (INITIALIZING_TRANSACTIONS) is live before the history source publishes"
    - "Split-phase ancestry seeding: publish the ancestor alone first (head set = {ancestor}), then the descendant (its delta replaces ancestor→descendant) so EraseEntry's head guard admits the ancestor"

key-files:
  created: []
  modified:
    - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
    - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
    - SuperGenius/src/crdt/crdt_datastore.hpp
    - SuperGenius/src/crdt/impl/crdt_datastore.cpp
    - SuperGenius/test/src/blockchain/node_startup_test.cpp
    - SuperGenius/test/src/blockchain/CMakeLists.txt

key-decisions:
  - "Budget placement ruled WALK-PASSED: getNode gains a 2-arg overload carrying uint32_t peer_failover_budget; the existing 1-arg virtual delegates with std::numeric_limits<uint32_t>::max() so every other caller keeps today's routes+20s behavior — no checkpoint needed since general fetch behavior is unchanged"
  - "Abort routing keys off progress.walk_gaps (the counter ProcessForcedWalkCID increments), robust regardless of error-category plumbing"
  - "Walk-side Malformed evidence returns std::errc::bad_message (T-17-0502 vocabulary), counted in errors — distinct taxonomy from the syncer's PRUNE_EVIDENCE_CORRUPT, same fail-closed discipline"
  - "Walk legs live in node_startup_test.cpp (plan placement option A) under the existing SGNS_COLD_STORAGE guard conventions; CMake gains the compile definition + sgns-blockstore link only for that target"
  - "W3 gap shape is seal-only ghost CIDs (real content-addressed CIDs whose bytes exist nowhere) pre-sealed via the syncer's public markResolved so gossip link-traversal skips them while QueueForcedWalkLinks still queues them for the walk visit"

patterns-established:
  - "AwaitNodeParkedAndListening: full-node park at WAITING_FOR_TRUST_GENESIS as the replication-ready posture for node-level gossip tests (the broadcaster's full-topic AddListenTopic runs at INITIALIZING_TRANSACTIONS; a light node parks earlier and never replicates)"
  - "Manual head announce must carry the source syncer's PeerInfo — PubSubBroadcasterExt::Broadcast with a none peerInfo drops the publish silently ('No addresses found', success without publishing)"

requirements-completed: [RECOVER-02, RECOVER-03, RECOVER-04]

coverage:
  - id: D1
    description: "W1 restore leg — GC-evicted (cold-resident, no-evidence) ancestor restored by the forced walk through getNode's cold-before-peers chain"
    requirement: RECOVER-02
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/blockchain/node_startup_test.cpp#NodeStartupTest.ForcedWalkRestoresColdResidentAncestor"
        status: pass
  - id: D2
    description: "W2 pruned-skip leg — evidence-bearing ancestor skipped at block level while CanRestoreElement stays terminal at element level (unrestorable assertion)"
    requirement: RECOVER-03
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/blockchain/node_startup_test.cpp#NodeStartupTest.ForcedWalkSkipsEvidenceBearingAncestor"
        status: pass
  - id: D3
    description: "W3 gap-abort leg — true gap produces walk_gaps, FORCED_WALK_GAP, Incomplete with frontier cleared; never skipped_pruned, never deferred, never errors; processing stops after the first gap"
    requirement: RECOVER-04
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/blockchain/node_startup_test.cpp#NodeStartupTest.ForcedWalkAbortsNeverSkipsOnTrueGap"
        status: pass
  - id: D4
    description: "W4 cold-off leg — cold-disabled node preserves today's prune-boundary skip byte-identically (Completed, skipped_pruned >= 1, walk_gaps == 0)"
    requirement: RECOVER-04
    verification:
      - kind: integration
        ref: "SuperGenius/test/src/blockchain/node_startup_test.cpp#NodeStartupTest.ColdDisabledWalkPreservesLegacyPruneBoundarySkip"
        status: pass
  - id: D5
    description: "D-06 bounded getNode overload + knob-free kForcedWalkPeerFailoverPerCid = 8 with recorded derivation; 1-arg virtual behavior unchanged"
    requirement: RECOVER-04
    verification:
      - kind: unit
        ref: "SuperGenius/src/crdt/graphsync_dagsyncer.hpp#kForcedWalkPeerFailoverPerCid (+ Task 1 verify greps, commit d6a2dc08b)"
        status: pass
    human_judgment: false

duration: 95min
completed: 2026-11-17
status: complete
---

# Phase 15 Plan 02: Evidence-Aware Forced-Walk Recovery Summary

**D-05 evidence matrix + D-06 per-CID failover budget landed in the forced walk, proven at node level: evicted ancestors restore from cold, erased ancestors skip bounded by evidence, true gaps abort loudly with a dedicated counter, and the cold-disabled posture stays byte-identical.**

## Performance

- **Duration:** ~95 min total (Task 1 by the original executor; Task 2 finished by a continuation after a mid-plan crash — see Deviations)
- **Completed:** 2026-11-17
- **Tasks:** 2/2
- **Files modified:** 6 (4 production, 2 test/build)

## Accomplishments

- **The four-quadrant walk matrix is live** — `ProcessForcedWalkCID`'s sealed+not-retained branch now consults `LookupPruneEvidence` first: nullopt (cold disabled) and `Pruned` take the existing skip shape, `Malformed` fails closed with `std::errc::bad_message`, `NoEvidence` falls through to the bounded fetch — the RECOVER-04 conflation bug (GC-evicted ancestors silently validated as pruned) is dead.
- **Abort-never-skip gap semantics** — a failed bounded recovery increments `walk_gaps`, returns `Error::FORCED_WALK_GAP` after the existing cleanup, and `ProcessForcedWalkStep` clears the frontier without touching `errors`/`deferred`/`skipped_pruned`; `FinishForcedWalkLocked` finishes Incomplete and the counter log prints `walk_gaps`.
- **D-06 knob-free budget** — `kForcedWalkPeerFailoverPerCid{8}` with the three-converging-8s derivation (root ladder 8, walk retries 8, observed refusal-failover ≤ 8) + Phase 17 re-tune note; the route loop counts attempted peers and exits into the existing ROUTE_NOT_FOUND terminal path with a budget-naming error log; the 1-arg virtual delegates with the unbounded sentinel so general fetch behavior is untouched.
- **Node-level behavioral evidence (W1–W4)** — all four quadrants proven through the node's own opt-in walk surface with `GetForcedWalkStatus()` polls: W1 `Completed, fetched=1, restored=1, skipped_pruned=0`; W2 `Completed, skipped_pruned=1, walk_gaps=0` + element-level unrestorable assertion; W3 `Incomplete, walk_gaps=1, skipped_pruned=0, deferred=0, errors=0` with the loud abort log naming the CID and budget 8, frontier stopped at visited=2; W4 `Completed, skipped_pruned=1, walk_gaps=0` on a cold-disabled node.

## Task Commits

Each task was committed atomically:

1. **Task 1: D-05 walk evidence matrix + walk_gaps abort + FORCED_WALK_GAP error + D-06 bounded getNode overload** — `d6a2dc08b` (feat, SuperGenius `dev_coldstorage_additions`)
2. **Task 2: node-level walk suites — restore / pruned-skip / gap-abort / cold-off legs** — `de37f79e8` (test, SuperGenius `dev_coldstorage_additions`)

**Plan metadata:** root wrap-up commit (this SUMMARY + submodule pointer)

## Verification Results

| Lane | Result |
| ---- | ------ |
| Incremental Release build (`cmake --build .../Windows/Release --config Release --parallel 8`) | exit 0, no `error C`/`LNK` diagnostics |
| `ctest -R node_startup_test` (full suite incl. pre-existing ForcedBootstrapWalk tests) | 1/1 passed (42.74 s) — existing walk tests unmodified and green |
| `ctest -L Tier1` | 15/15 passed |
| Phase-13/14 regression lane (`cold_storage_fallback\|prune_eligibility\|crdt_erase\|cold_storage_gc\|cold_storage_gc_retrievability\|globaldb_erase\|tx_pruner\|cold_storage_resurrection\|cold_storage_durability\|cold_prune_gate\|cold_prune_toctou\|cold_evidence_matrix`) | 10/10 passed |

Individual leg counters (joint run):

- W1: `Forced walk completed: visited=2, fetched=1, restored=1, skipped_pruned=0, walk_gaps=0, skipped_existing=1, deferred=0, errors=0`
- W2: `Forced walk completed: visited=2, fetched=0, restored=0, skipped_pruned=1, walk_gaps=0, skipped_existing=1, deferred=0, errors=0`
- W3: `Forced walk gap at CID …: bounded cold+peer recovery exhausted (per-CID peer budget 8) - aborting the walk` → `Forced walk incomplete: visited=2, …, walk_gaps=1, …, deferred=0, errors=0`
- W4: `Forced walk completed: visited=2, fetched=0, restored=0, skipped_pruned=1, walk_gaps=0, …`

## Files Created/Modified

- `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` — `kForcedWalkPeerFailoverPerCid`, bounded `getNode` overload declaration, `LookupPruneEvidence` declaration
- `SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp` — 1-arg delegate with unbounded sentinel, per-CID attempted-peer count in the route loop, optional-shaped evidence accessor
- `SuperGenius/src/crdt/crdt_datastore.hpp` — `ForcedWalkStatus::walk_gaps`, `Error::FORCED_WALK_GAP`
- `SuperGenius/src/crdt/impl/crdt_datastore.cpp` — D-05 matrix, bounded fetch call, gap mapping, abort routing, finish predicate + log
- `SuperGenius/test/src/blockchain/node_startup_test.cpp` — W1–W4 legs + fixture helpers (`syncerOf`, `AwaitNodeDatabase`, `AwaitNodeParkedAndListening`, `AttachHistorySource`, `AwaitNodeHoldsSealedBlock`, `RequestWalkOverFullTopic`, `kWalkLegsColdConfig`)
- `SuperGenius/test/src/blockchain/CMakeLists.txt` — `SGNS_COLD_STORAGE` compile definition + `sgns-blockstore` link for `node_startup_test` (OFF builds unchanged)

## Decisions Made

- Budget placement: walk-passed sibling overload, not unconditional (rejected variant changes general fetch behavior) — within the plan's granted discretion; no checkpoint required.
- W3 budget observability: the >8-route deterministic topology is impractical on the node fixture (routes arrive via gossip intake; no per-CID attempt counter exposed) — deferral recorded in a code comment naming 15-03's failover mesh window and Phase 17's SC2 probe, per the plan's recorded disposition.
- Walk legs placed in `node_startup_test.cpp` (option A) — the fixture carried cold options without disturbing existing legs via the `crdt_config_content` parameter defaulting to empty.

## Deviations from Plan

### Continuation note (factual)

The original executor crashed mid-Task-2 after committing Task 1 (`d6a2dc08b`) and leaving the Task 2 test work uncommitted (~576 lines, compile-broken). This continuation verified the resume state, reconciled and completed the legs, and finished the plan. No Task 1 mechanism was re-implemented; the pre-existing ForcedBootstrapWalk tests are untouched.

### Auto-fixed Issues

**1. [Rule 3 - blocking] W4 helper calls left at the wrong arity (crash leftover)**
- **Found during:** Task 2 reconciliation (first rebuild)
- **Issue:** the two `AwaitNodeHoldsSealedBlock` calls in W4 passed 4 of 6 arguments — `error C2660`
- **Fix:** completed the calls with `fixture` + `source` matching W1/W2
- **Files:** `node_startup_test.cpp`
- **Commit:** `de37f79e8`

**2. [Rule 3 - blocking] Replication never happened on light nodes (listen-topic gating)**
- **Found during:** Task 2 first run (all four legs timed out at "node did not retain + seal")
- **Issue:** the node's broadcaster subscribes to the full-nodes topic only at `INITIALIZING_TRANSACTIONS` (`AddListenTopic`, GeniusNode.cpp:1002); a light node parks in `INITIALIZING_BLOCKCHAIN` retrying `BLOCKCHAIN_NOT_INITIALIZED` and never listens — no gossip ingest, no replication
- **Fix:** legs create full nodes (`isFullNode=true` + `Blockchain::SetAuthorizedFullNodeAddress`) and wait for the `WAITING_FOR_TRUST_GENESIS` park via a new `AwaitNodeParkedAndListening` helper — the exact `CanonicalCertificatesAcceptedBeforeTransactionManager` shape; purely test-side
- **Files:** `node_startup_test.cpp`
- **Commit:** `de37f79e8`

**3. [Rule 3 - blocking] EraseEntry guard 1 refused the ancestor (head-set replacement ordering)**
- **Found during:** Task 2 runs after fix 2 ("cid … is the head of topic …, refusing erase")
- **Issue:** publishing both blocks up front lets the node process the descendant first; the link-fetched ancestor is then finalized as its own root and re-added as an extra head, so the ancestor never leaves the head set
- **Fix:** split-phase seeding — replicate the ancestor alone first (head set = {ancestor}), then publish the descendant whose delta replaces ancestor→descendant
- **Files:** `node_startup_test.cpp` (W1/W2/W4)
- **Commit:** `de37f79e8`

**4. [Rule 3 - blocking] W1 replay deferred forever ("missing dependency, another guarded walk is required")**
- **Found during:** Task 2 W1 run (walk Incomplete, deferred=1, restored=0)
- **Issue:** `GlobalDB::RequestForcedWalk` forwards with `require_registered_filters=true`, so an element without a registered validator is stripped and deferred at replay
- **Fix:** W1 registers the accepting validator for `^/?walk/w1/ancestor$` before the walk — the same final-phase shape `ForcedBootstrapWalkRetriesLateValidatorAfterReady` uses; `RegisterElementFilter` returns `bool` (not `outcome`), which the first attempt got wrong and the compiler caught
- **Files:** `node_startup_test.cpp`
- **Commit:** `de37f79e8`

**5. [Rule 3 - blocking] W3 manual head announce silently dropped**
- **Found during:** Task 2 W3 run ("node did not retain + seal the ghost-linking head")
- **Issue:** `PubSubBroadcasterExt::Broadcast` with a `none` peerInfo has no addresses and returns success WITHOUT publishing ("No addresses found for broadcasting") — the custom head (not in the composition's head list, so `RequestHeadBroadcast` can't carry it) never reached the node
- **Fix:** the announce passes the source syncer's `GetPeerInfo()` (mirroring `BroadcastHeadsForTopics`)
- **Files:** `node_startup_test.cpp`
- **Commit:** `de37f79e8`

## Known Stubs

None — no placeholder logic shipped. The single recorded deferral (W3's budget-count runtime observability) is the plan's own documented disposition (comment naming 15-03 + Phase 17), not a stub.

## Threat Flags

None — no security-relevant surface beyond the plan's threat model (T-15-05/06/07 mitigations all verified by the W2/W3 counter assertions and the budget-naming abort log).
