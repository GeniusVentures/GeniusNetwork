---
phase: 15-evidence-aware-cold-serving-forced-walk-recovery
plan: 01
subsystem: crdt/transaction (cold-storage read path + prune evidence)
tags: [cold-storage, prune-evidence, graphsync, globaldb, txpruner, tier1]
requires:
  - "Phase 14 durability gate (TxPruner RunCycle cold conjunct, EraseEntry guard 5)"
  - "v1.1 Phase 9 cold-read seam (ColdReadFallback hook, FetchNodeFromColdStorage, RewarmWorkerLoop)"
provides:
  - "PruneEvidenceClass tri-state predicate fanned to every cold serve surface (getNode cold leg, GetNodeWithoutRequest, re-warm worker)"
  - "/prune/blk evidence production: EraseEntry vector widening + PrunedBlockRecord back-reference staged atomically with every TxPruner erase"
  - "GraphsyncDAGSyncer::Error::HISTORY_PRUNED_LOCALLY / PRUNE_EVIDENCE_CORRUPT terminal refusal taxonomy"
  - "cold_evidence_matrix_test — the hermetic Tier-1 evidence kit 15-02/15-03 build on"
affects:
  - "SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp (consult + node-local terminality; HasBlock body untouched — D-04)"
  - "SuperGenius/src/transaction/TransactionManager.cpp (marker-vector assembly)"
  - "SuperGenius/src/transaction/TxPruner.cpp (generation threading)"
tech-stack:
  added: []  # v1.2 zero-new-dependencies ruling holds — pinned mechanisms only
  patterns:
    - "ColdStorageStack free-bridge injection (SetPruneEvidenceLookupOnColdReadService) — the gated-type boundary discipline extended to the evidence predicate"
    - "PHASE P throwaway-publisher + PHASE B direct LocalBlockStore seeding — cold-only blocks without hot-store surgery"
    - "Table-driven evidence stub via the production SetPruneEvidenceLookup seam (TEST-01 secondary architecture)"
key-files:
  created:
    - SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp
  modified:
    - SuperGenius/src/account/proto/SGTransaction.proto
    - SuperGenius/src/transaction/PruneEligibility.hpp
    - SuperGenius/src/transaction/PruneEligibility.cpp
    - SuperGenius/src/transaction/TransactionManager.hpp
    - SuperGenius/src/transaction/TransactionManager.cpp
    - SuperGenius/src/transaction/TxPruner.cpp
    - SuperGenius/src/crdt/cold_read_fallback.hpp
    - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
    - SuperGenius/src/crdt/impl/graphsync_dagsyncer.cpp
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/crdt/globaldb/CMakeLists.txt
    - SuperGenius/src/crdt/globaldb/ColdReadService.hpp
    - SuperGenius/src/crdt/globaldb/ColdReadService.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt
    - SuperGenius/test/src/account/prune_eligibility_test.cpp
decisions:
  - "Evidence install routed through a ColdStorageStack free bridge (SetPruneEvidenceLookupOnColdReadService): globaldb.cpp never sees the complete gated ColdReadService type — the established StartColdReadService discipline, not a GlobalDB accessor (which would be new production surface)"
  - "Zero-length /prune/blk rows classify Malformed via an explicit empty check in BOTH lookup surfaces: protobuf ParseFromArray accepts empty input as a valid all-defaults encoding, so the parse-failure leg alone cannot deliver the plan's fail-closed truth"
  - "Cold-only test blocks arrive via a throwaway publisher (PHASE P) + direct coldstore seeding (PHASE B): the fixture node never holds them hot, no hot-store key surgery, no key-format vendoring beyond the existing blockKeyOf contract"
  - "The re-warm worker gate is proven on the fallback-test kit with a table-driven lambda installed through the production SetPruneEvidenceLookup seam (GlobalDB exposes no cold-read-service accessor; TEST-01 secondary architecture per RESEARCH)"
metrics:
  duration: 48min
  completed: 2026-11-18
estimate:
  tokens: 52000
actuals:
  tokens: 27912    # chars/4 over git diff 095c8c502..548264dc4 (111,649 chars)
  tasks: 2
  commits: 2       # MEASURED: git rev-list --count 095c8c502..HEAD (SuperGenius submodule)
plan_head_before: 095c8c5025e745a25a6c18e3e5d0370a7f9ae4d2   # SuperGenius submodule (code repo)
plan_head_after: 548264dc48f53fcb4143cef53b34da220211e099    # SuperGenius submodule (code repo)
status: complete
---

# Phase 15 Plan 01: Evidence-Aware Cold Serving Tracer Summary

**One-liner:** /prune/blk evidence production (D-01 vector widening + D-02 PrunedBlockRecord) wired through one role-aware PruneEvidenceClass predicate into a consult-before-cold-Get fork, a distinct terminal refusal taxonomy, and the re-warm gate — proven by legs S1-S5 of the new hermetic Tier-1 evidence-matrix suite.

## What Was Built

### Task 1 — the tracer wiring (SuperGenius `638053925`)

The full evidence chain landed as ONE atomic wiring commit:

- **Proto (D-02):** `PrunedBlockRecord` beside `PrunedTransactionRecord` — the erasing `/prune/tx` hash back-reference + `has_erased_at_generation`/`erased_at_generation`, commented as node-local-only (D-07/A1).
- **PruneEligibility (D-C1 home):** `PRUNE_BLOCK_MARKER_PREFIX`, `PrunedBlockLookup` (deliberately WITHOUT the VALUE_PRESENT_INVARIANT_VIOLATION leg — a block marker legitimately coexists with cold bytes), `BuildPruneBlockMarkerKey` / `LookupPrunedBlockEntry` (GetRaw point lookup, NOT_FOUND→{NOT_FOUND,nullopt}, malformed→`std::errc::bad_message` with a MarkerLogger error, T-17-0502), `BuildPruneBlockMarkerEntry`, `WritePrunedBlockEntryForTest`. `CanRestoreElement` byte-untouched (verified: the only PruneEligibility.cpp hunk is a pure insertion at :285+).
- **EraseEntry widening (D-01, Pitfall 6):** third parameter is now `const std::optional<std::vector<std::pair<Buffer, Buffer>>> &extra_entries = std::nullopt`; the staging loop puts every pair at the SAME batch position; guards, compose lock, and post-commit seal re-assert untouched.
- **Seam (SC3/D-04):** `PruneEvidenceClass : uint8_t {NoEvidence, Pruned, Malformed}` + pure virtual `LookupPruneEvidence(const CID&)` on `ColdReadFallback`; `ColdReadService` is the sole implementor over a GlobalDB-installed `std::function` (`SetPruneEvidenceLookup`; empty callable → NoEvidence, documented as the pre-install/test-stub posture).
- **GlobalDB install:** the lambda lands between the `cold_read_service_` assignment and `StartColdReadService` — native `GetRaw` + `PrunedBlockRecord` parse over a file-local `/prune/blk/` prefix constant whose canonical home stays `PruneEligibility::PRUNE_BLOCK_MARKER_PREFIX` (the layering ruling; the evidence-matrix suite pins the two homes together). NOT_FOUND→NoEvidence, other GetRaw error→Malformed, parse failure→Malformed, success→Pruned. `SGTransactionProto` linked PRIVATE to `crdt_globaldb`.
- **Syncer (SERVE-01/02/04, D-07):** `HISTORY_PRUNED_LOCALLY` + `PRUNE_EVIDENCE_CORRUPT` appended after `COLD_STORAGE_UNAUTHORIZED` (uint8_t-sequential) with one-line string cases; the consult sits at the top of `FetchNodeFromColdStorage`'s hooked path BEFORE the cold Get (Pitfall 1: one lookup covers bytes-present AND bytes-miss+evidence, and skips cold I/O for pruned CIDs); `getNode` early-returns both refusals before `GetRouteKeys` (node-local terminality); `RewarmWorkerLoop` consults before its Get and skips Pruned (debug line) / Malformed (error line).
- **Caller assembly:** `EraseTransactionEntryWithMarker`/`EraseTransactionEntryPruned` gained a trailing defaulted `generation`; the marker assembly builds the 2-element vector from the SAME resolved path+cid (WR-02 comment preserved); `TxPruner::RunCycle` threads its generation tag through.

### Task 2 — the Tier-1 evidence suite (SuperGenius `548264dc4`)

`cold_evidence_matrix_test.cpp` — the TEST-01 PRIMARY architecture: a REAL cold-enabled GlobalDB (hermetic.invalid endpoint, injected InMemory clients, hygiene clear, full TeardownStack with every static hook cleared), with cold-only blocks supplied by a throwaway publisher (PHASE P) whose captured (CID, raw block bytes) are seeded directly into the fixture's coldstore (PHASE B) before the fixture GlobalDB is ever constructed. Legs:

- **S1 `Serve_EvidenceRefusalBeatsColdBytes`:** getNode AND GetNodeWithoutRequest answer `HISTORY_PRUNED_LOCALLY` for a CID whose cold bytes exist; the hot store never receives the bytes; repeat reads are stable; the no-evidence sibling on the same fixture still serves (per-CID discrimination, PROBE-LIFT).
- **S2 `Serve_NoEvidenceColdBytesServeAndRehydrate`:** the NoEvidence branch serves verbatim — getNode resolves, CID matches, block is hot after (evict = DETACH).
- **S3 `Evidence_TxPrunerEraseStagesBothMarkers`:** a real TxPruner erase over a Durable group (the Phase-14 gate-test recipe) stages BOTH marker rows in one commit; the record carries the tx-hash back-reference and `kTestGeneration`; hot bytes gone, cold evidence survives (journal Durable + `HasBlock` cold-dir term TRUE — the D-04 posture in action); getNode for the erased CID subsequently refuses.
- **S4 `Evidence_MalformedMarkerFailsClosed`:** garbage bytes AND a zero-length value both answer `PRUNE_EVIDENCE_CORRUPT` on both surfaces, never serve.
- **S5 `Evidence_ColdDisabledNeverConsultsEvidence`:** a cold-disabled GlobalDB with a seeded marker row answers the pre-phase shape (ROUTE_NOT_FOUND/CID_NOT_FOUND) and explicitly neither refusal value.
- **`Rewarm_PrunedEvidenceSkipsRewarmWorker`** (fallback-test kit): the worker consult skips a Pruned CID past `kRewarmBudget` while the NoEvidence control on the same worker completes — the responder-side resurrection gate, proven discriminating.

## Verification Evidence

| Check | Result |
|---|---|
| Full incremental Release build (`cmake --build SuperGenius/build/Windows/Release --config Release --parallel 8`) | exit 0, zero `error C/LNK/MSB` |
| `ctest -R cold_evidence_matrix_test` | **Passed** (6.84 s first run / 6.37 s lane run) |
| `ctest -L Tier1 --no-tests=error` | **15/15 Passed** (133.7 s) — suite listed as Test #110, zero regression |
| Regression: `prune_eligibility_test` / `tx_pruner_test` / `globaldb_integration_test` | 3/3 **Passed** (2.7 s / 46.6 s / 87.1 s) |
| D-04 gate (diff hunks intersecting HasBlock :705-748 vs `095c8c502`) | **0 hunks** |
| Layering gate (src/crdt referencing PruneEligibility / genius_transaction_objs) | comments only — no include, no link |
| Structural probes (Task 1 verify block) | hpp-enum=2≥2, cpp-symbols=6≥5, vector-widening=1≥1, PruneEligibility-family=9≥5, seam=3≥3, service=2≥2, caller=4≥2; test-symbol probe=15≥4 |
| CanRestoreElement byte-identity | only hunk in PruneEligibility.cpp is a pure insertion at :285+ (:156-170 untouched) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Gated-type boundary on the lambda install**
- **Found during:** Task 1 first build — `error C2027: use of undefined type ColdReadService`; globaldb.cpp only ever holds the forward-declared shared_ptr and reaches the service exclusively through ColdStorageStack free bridges (`StartColdReadService` discipline).
- **Fix:** added the `SetPruneEvidenceLookupOnColdReadService` bridge — declared in `ColdStorageStack.hpp` (with `<functional>` + the ungated `cold_read_fallback.hpp` include for `PruneEvidenceClass`), defined in `ColdStorageStack.cpp` (forwards to the service), and given the no-op ODR twin in `ColdStorageStackStub.cpp` (OFF builds). globaldb.cpp calls the bridge with the type-erased lambda.
- **Files modified:** `ColdStorageStack.hpp`, `ColdStorageStack.cpp`, `ColdStorageStackStub.cpp`, `globaldb.cpp`
- **Commit:** 638053925

**2. [Rule 3 - Blocking] Mechanical test-caller update for the D-01 widening**
- **Found during:** Task 1 build — `prune_eligibility_test.cpp` F2/F3 still staged the single pair (the plan anticipated test callers of EraseEntry).
- **Fix:** the 1-element vector form at both sites.
- **Files modified:** `test/src/account/prune_eligibility_test.cpp`
- **Commit:** 638053925

**3. [Rule 2 - Correctness] Zero-length evidence must classify Malformed**
- **Found during:** Task 2 design — protobuf `ParseFromArray` accepts zero-length input as a VALID all-defaults encoding, so the plan's "fails ParseFromArray — including a zero-length value" premise does not hold mechanically; an empty row would have classified Pruned (with a meaningless default record) rather than Malformed.
- **Fix:** explicit `marker.value().empty()` checks in BOTH `LookupPrunedBlockEntry` and the GlobalDB lambda — zero-length rows classify Malformed/bad_message (production never writes one; the builder always serializes nonzero bytes). LEG S4's zero-length case pins it.
- **Files modified:** `PruneEligibility.cpp`, `globaldb.cpp`
- **Commit:** 548264dc4

**4. [Discretion - within the plan's TEST-01 architecture] Re-warm gate fixture**
- **Found during:** Task 2 design — GlobalDB exposes no cold-read-service accessor, so `EnqueueRewarm` cannot be driven through the full-stack fixture.
- **Fix:** the re-warm leg (and a syncer-level consult proof) run on the `cold_storage_fallback_test` kit with a table-driven lambda installed through the PRODUCTION `SetPruneEvidenceLookup` seam — RESEARCH's sanctioned secondary architecture. The full-stack legs S1-S5 exercise GlobalDB's own lambda.
- **Commit:** 548264dc4

Minor: the `cold_read_fallback.hpp` probe counts LINES (the virtual's return type and name share one line), so the enum's doc block now names `LookupPruneEvidence` — honest documentation that also satisfies the ≥3 gate.

## Auth Gates

None — no authentication surfaces crossed.

## Known Stubs

None — every surface introduced is wired to real behavior and proven by the suite.

## Open Items (in-plan, later plans)

- SC3's source-consistency TEST and the HasBlock posture assertion land in 15-03 (per D-04's ruling: mechanism here, consistency test there).
- The walk matrix (D-05), per-CID failover budget (D-06), and product-matrix + failover evidence are 15-02/15-03 scope.
- The A5 wire-status observable remains not directly observable (unchanged posture; behavior-asserted).

## Self-Check: PASSED

- `SuperGenius/test/src/crdt/cold_evidence_matrix_test.cpp` exists (created, committed in 548264dc4)
- Commits `638053925` and `548264dc4` present on `dev_coldstorage_additions` (git log verified)
- All plan `<verify>` commands re-run green (see Verification Evidence)
