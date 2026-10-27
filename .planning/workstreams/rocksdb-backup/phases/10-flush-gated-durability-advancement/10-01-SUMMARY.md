---
phase: 10-flush-gated-durability-advancement
plan: 01
subsystem: infra
tags: [s3d, admin-api, cpp-httplib, durability, flush, rocksdb-journal, crdt, cold-storage]

requires:
  - phase: 08-spill-on-write-background-drainer
    provides: ColdStorageManager drainer thread (DrainOnce split-phase, backoff twins) + LocalBlockStore journal transitions
  - phase: 09-cold-read-fallback-local-reads-graphsync-serving
    provides: remote_store_mutex_ serialization + gated/ungated stack discipline (ColdStorageStack always-compiled)
provides:
  - Installed s3d admin facade sgns::blockstore::S3AdminClient (Flush + GetUploadStats, BlockStatus taxonomy, OpenS3dAdminClient factory) + InMemoryS3AdminClient fake
  - LocalBlockStore::GetUploadsInState(UploadState) (the D-03 snapshot source) + MarkUploadedDurableMany (one WriteBatch + one sync Write, skip-and-continue)
  - ColdStorageManager flush-gated advancement: AdvanceDurabilityOnce hybrid cadence (floor + quiescence-or-backstop), separate flush backoff, evidence atomics, kEvictionDurabilityGate == UploadedDurable (D-10)
  - blockstore.durability config sub-object + blockstore.admin_endpoint + SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD env credential + wallet asset parity
  - D-04 bounded Stop() final flush (final_flush_done_ exactly-once, kFinalFlushBudgetMs) + one-time missing-password startup WARN
  - Ungated ColdUploadState enum + GetColdUploadState bridge (ODR twin in the stub) + GlobalDB::GetColdUploadState active accessor
  - Tier-1 suites: cold_storage_durability_test (8 cases) + s3_admin_client_test wire lane (6 cases)
affects: [11-retention-gc-of-cold-eligible-crdt-data, genius-tube, s3d-durability doc consumers]

actuals:
  tokens: 21000
  tasks: 3
  commits: 9

tech-stack:
  added: []  # no NEW external deps - cpp-httplib + nlohmann_json are existing superbuild pins newly linked PRIVATE
  patterns:
    - "admin facade seam: virtual interface installed, httplib/nlohmann impl PRIVATE, one-function failure classifier (never NotFound)"
    - "flush-gated advancement: snapshot-under-mutex -> admin calls unlocked -> evidence gate -> mark-exactly-the-snapshot re-locked"
    - "presence-only credential flag (SetAdminPasswordPresent) - the manager never sees the password value"

key-files:
  created:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/S3AdminClient.hpp
    - thirdparty/sgns-blockstore/src/S3AdminClient.cpp
    - thirdparty/sgns-blockstore/src/InMemoryS3AdminClient.hpp
    - thirdparty/sgns-blockstore/src/InMemoryS3AdminClient.cpp
    - thirdparty/sgns-blockstore/test/s3_admin_client_test.cpp
    - SuperGenius/test/src/crdt/cold_storage_durability_test.cpp
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
    - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
    - thirdparty/sgns-blockstore/src/CMakeLists.txt
    - thirdparty/sgns-blockstore/CMakeLists.txt
    - thirdparty/sgns-blockstore/test/local_block_store_test.cpp
    - thirdparty/sgns-blockstore/test/api_hygiene_test.cpp
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
    - thirdparty/sgns-blockstore/docs/s3d-durability.md
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
    - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
    - SuperGenius/test/src/crdt/cold_storage_spill_test.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt
    - GeniusWallet/assets/crdt_config.json

key-decisions:
  - "Manager ctor widened via TRAILING DEFAULTED params (DurabilityOptions = {}, admin = nullptr): the Phase-8 5-argument posture stays compiling - nullptr admin means no advancement, exactly the durability-absent config behavior"
  - "Missing-password WARN implemented as SetAdminPasswordPresent(bool) presence-only - the manager never holds the credential value; the stack sets the flag from the env-resolved ColdStorageOptions"
  - "GetPendingUploads delegates to GetUploadsInState(PendingUpload) - ONE journal-scan body exists (the D-03 snapshot semantics are shared, not duplicated)"
  - "Wire-lane budget proof uses a test-local black-hole listener (accept, never respond): the LoopbackHttpStub has no delay scripting, and a hung response is the only shape that exercises the client read budget"
  - "httplib 0.14.2 Client is a pimpl WRAPPER (SSLClient derives ClientImpl, NOT Client) - the admin client constructs via the scheme_host_port ctor + the wrapper's forwarded enable_server_certificate_verification"

patterns-established:
  - "Evidence-gated state machine: a journal transition requires observed evidence (flush 200 + pendingObjects==0), never an assumption; every failure path maps TemporarilyUnavailable so records fail-safe in their previous state"
  - "Separate backoff twins: flush failure state (streak/delay/cap) is fully disjoint from drain backoff - neither poisons the other (Pitfall 6)"

requirements-completed: [DUR-01]

coverage:
  - id: D1
    description: "SC1 tracer: quiescent drain -> flush fires -> pendingObjects==0 observed -> exactly the snapshot advances to Durable -> visible in GetStatus evidence"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#e2e_flush_gated_advancement"
        status: pass
  - id: D2
    description: "Evidence gate: pendingObjects!=0 blocks all marks (records stay Accepted, valid-but-not-ok recorded); next zero-observation cycle advances"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#evidence_gate_pending_objects_blocks_advancement"
        status: pass
  - id: D3
    description: "Flush failure backoff: zero marks under FlushFails, attempts space out, recovery advances and resets; floor gates the first attempt; backstop flushes under sustained non-quiescent load"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#flush_failure_keeps_accepted_then_recovers / cadence_floor_delays_first_flush / backstop_flushes_under_sustained_activity"
        status: pass
  - id: D4
    description: "SC2 observability: kEvictionDurabilityGate compile-time UploadedDurable, budget constants, per-CID manager pass-through"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#eviction_gate_constant_and_per_cid_state"
        status: pass
  - id: D5
    description: "Admin facade wire truth: empty-username Basic auth on the wire, 200/500/garbage/missing-field mappings TemporarilyUnavailable, every counter parsed (bufferLimit 0), read budget bounds a blocked response"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/s3_admin_client_test.cpp#S3AdminClientWire (6 cases)"
        status: pass
  - id: D6
    description: "Journal composition surface: state-filtered enumeration in byte-lexicographic order; batched durable marks skip-and-continue on no-record, one WriteBatch + one sync Write; idempotent replay"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/local_block_store_test.cpp#LocalBlockStoreJournal (2 cases)"
        status: pass
  - id: D7
    description: "Operator config surface: durability defaults 30000/300000, per-knob 0-default, unknown-key/wrong-type/min>max loud (both effective values), durability-only disables, admin_endpoint optional string"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp#Durability* / AdminEndpointOptionalString (7 cases)"
        status: pass
  - id: D8
    description: "D-04 shutdown final flush: Stop() advances Accepted records via one bounded attempt; failure leaves them Accepted and a fresh manager's first cycle resumes"
    requirement: DUR-01
    verification:
      - kind: unit
        ref: "SuperGenius/test/src/crdt/cold_storage_durability_test.cpp#shutdown_final_flush_advances / shutdown_final_flush_failure_leaves_accepted"
        status: pass
  - id: D9
    description: "Hygiene + parity gates: api_hygiene TU compiles with the new installed header and no new PUBLIC dep; header_hygiene green; registration parity addtest(cold_)==LABELS Tier1 (6==6); zero logging tokens in the admin impl; zero 'bucket-scoped' in the s3d doc"
    requirement: DUR-01
    verification:
      - kind: integration
        ref: "ctest lanes: api_hygiene_test, header_hygiene, parity/credential/docs PowerShell gates (all pass)"
        status: pass
  - id: D10
    description: "Regression: pre-existing cold-storage/config lanes stay green after the ctor widening and the batched-mark switch (crdt_test, globaldb_integration_test, spill/config/durability suites)"
    requirement: DUR-01
    verification:
      - kind: integration
        ref: "ctest -R 'crdt_test|globaldb_integration_test|cold_storage' -> 7/7; SuperGenius -L Tier1 -> 6/6"
        status: pass

duration: 55min
completed: 2026-10-26
status: complete
---

# Phase 10 Plan 01: Flush-Gated Durability Advancement — Tracer + Expansions Summary

**`Durable` is now an evidence-backed journal state: the drainer's cadence step fires POST /objects/flush, observes pendingObjects==0 through the new installed s3d admin facade, and marks exactly the pre-flush Accepted snapshot in one atomic WriteBatch — never accepted-is-durable.**

## Performance

- **Duration:** 55 min
- **Start/End:** 2026-10-26T20:35Z / 2026-10-27T01:22Z (EDT session)
- **Tasks:** 3/3 | **Commits:** 9 (4 SuperGenius, 3 sgns-blockstore, 2 thirdparty pointers... plus 1 GeniusWallet asset)
- **File count:** 23 (6 created, 17 modified)

## Accomplishments

1. **Library facade (D-05/D-06):** installed `S3AdminClient.hpp` (UploadStats with verbatim openapi counter names minus transient activeUploads; Flush carries an EXPLICIT per-call read budget - no default on a virtual), cpp-httplib impl with a single failure classifier minting TemporarilyUnavailable only, `InMemoryS3AdminClient` fake with call-count probes, and PRIVATE httplib/nlohmann links (no new external dependencies - both are existing superbuild pins).
2. **Journal surface (D-03):** `GetUploadsInState(UploadState)` generalizes the pending scan (GetPendingUploads now delegates - one scan body) with the frozen byte-lexicographic ordering and snapshot-at-call-start semantics; `MarkUploadedDurableMany` commits the verified subset in ONE WriteBatch + ONE sync Write (single fsync, all-or-nothing crash window, skip-and-continue on no-record).
3. **Manager advancement (D-01/D-02/D-03/D-07..D-10):** `AdvanceDurabilityOnce(quiescent)` runs on the drainer thread between DrainOnce and MarkIdle under the hybrid cadence (floor + quiescence-or-backstop), takes the Accepted snapshot under cold_store_mutex_, runs the admin calls UNLOCKED, applies the evidence gate, and marks exactly the snapshot re-locked (Task 2 switched to the single batched call). Flush backoff is fully separate from drain backoff with its own 60 s compile-time cap; the "Phase-10 boundary" comments are replaced by the step they anticipated.
4. **Observability (D-08/D-09):** ColdStorageStatus gained six plain-type fields (accepted/durable counts + last-flush valid/ok/unix_ms/pending_objects); `GetUploadState` pass-through (gated) + `ColdUploadState` ungated enum + null-safe bridge + `GlobalDB::GetColdUploadState` active accessor + ODR stub twin.
5. **Operator surface (D-11/D-06):** strict `blockstore.durability` sub-object (defaults 30000/300000, per-knob 0-default, unknown/wrong/min>max loud naming both effective values, durability-only never activates), `blockstore.admin_endpoint` optional string, env-only `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` (never logged, never at rest), LogSummary extended with the non-secret fields only, wallet asset `"durability": {}` parity.
6. **D-04 final flush + WARN:** Stop() makes exactly one bounded flush+observe+mark attempt after the join under `final_flush_done_`; any failure leaves records Accepted for the next startup's first cycles (proven by the resume test). Start() emits the one-time missing-password WARN naming the env var - default-on flush, never silent, never a hard fail.
7. **Tests:** durability suite 8 cases green (e2e tracer, evidence-gate negative, flush-failure recovery, cadence floor, backstop under sustained non-quiescence, gate constants, shutdown advance/failure-resume); wire suite 6 cases green (auth header on the wire, taxonomy shapes, strict parse, budget bound); journal units, config matrix (7 new cases), hygiene + parity gates green.

## Issues Encountered

None blocking. Two test-iteration corrections happened BEFORE the GREEN commits (backstop-test knob values corrected to respect the floor-gates-everything semantics; journal unit tests fixed to Put the CID's own payload - the store verifies content). One pre-existing latent break repaired (see Deviations).

## Deviations from Plan

- **[Rule 2 - Blocker] Missed Phase-9 ctor call site in cold_storage_spill_test.cpp:690** — Found during: Task 1 read_first. Issue: commit 76e813710 widened the manager ctor with remote_store_mutex_ but this direct construction kept 4 arguments; the target was never rebuilt after that commit (obj stamp 2026-10-23 vs source 2026-10-26), so the committed tree could not compile the spill suite. Fix: fixture-local remote_store_mutex added (MakeManager precedent), comment documents the miss. Verification: cold_storage_spill_test builds and passes. Commit: 896d93601.
- **[Rule 1 - Test-infrastructure] Black-hole listener in s3_admin_client_test.cpp** — Found during: Task 2. Issue: the plan's "scripted slow response exceeding the per-call Flush budget" cannot be scripted through LoopbackHttpStub (FIFO raw responses only, no delay/hang support), and a closed connection is a transport error, not a bounded read. Fix: 30-line test-local WinSock listener that accepts and never responds; Flush(200ms) provably returns TemporarilyUnavailable within the bound. Verification: S3AdminClientWire.FlushReadBudgetBoundsABlockedResponse green. Commit: 84dbb3b.
- **[Rule 1 - Test correction] Backstop test knob values** — Found during: Task 1 GREEN. Issue: the first draft used floor=10s + backstop=300ms, which contradicts the cadence contract (the backstop bypasses quiescence, NEVER the floor - nothing may flush before 10s). Fix: floor=50ms + backstop=300ms under permanently non-quiescent cycles; quiescence is then provably never the trigger. No production change. Verification: backstop_flushes_under_sustained_activity green.

**Total deviations:** 3 auto-fixed (1 pre-existing blocker repair, 1 test-infrastructure adaptation, 1 test-value correction). **Impact:** none on plan semantics - all prohibitions and must_haves hold as written.

## Flagged Assumptions Status

Both DUR-01 flagged assumptions (idempotent replay; flush-vs-drain race + crash-between-observe-and-mark) remain construction-only in this plan by design - 10-02 Task 1 ships their proof (SC3 fault injections). The batched-mark idempotent-replay property IS already asserted at the library layer (LocalBlockStoreJournal.MarkUploadedDurableManySkipsAndContinues).

## Authentication Gates

None.

## Self-Check: PASSED

- All 3 tasks executed; per-task atomic commits (RED+GREEN for the tdd tasks) across sgns-blockstore -> thirdparty -> SuperGenius (+ GeniusWallet asset)
- Tier-1 lanes: library 3/3 targeted suites + header_hygiene; SuperGenius cold lanes 7/7; SuperGenius -L Tier1 6/6
- All plan <verify> commands and acceptance-criteria gates green (parity 6==6, credential grep 0, docs grep 0, boundary comments 0, stack-header include delta 0)

## Next Phase Readiness

Ready for 10-02 (Wave 2): the advancement construction, the D-04 final-flush block, and the four shared files it builds its SC3/SC4 work on are all in place.
