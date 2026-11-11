---
phase: 10-flush-gated-durability-advancement
verified: 2026-10-27T02:22:00Z
status: passed
score: 16/16 must-haves verified
covered_files:
  - .planning/workstreams/rocksdb-backup/phases/10-flush-gated-durability-advancement/10-01-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/10-flush-gated-durability-advancement/10-02-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/10-flush-gated-durability-advancement/10-01-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/10-flush-gated-durability-advancement/10-02-SUMMARY.md
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.hpp
  - SuperGenius/src/crdt/globaldb/globaldb.cpp
  - SuperGenius/test/src/crdt/cold_storage_durability_test.cpp
  - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - thirdparty/sgns-blockstore/include/sgns-blockstore/S3AdminClient.hpp
  - thirdparty/sgns-blockstore/src/S3AdminClient.cpp
  - thirdparty/sgns-blockstore/src/InMemoryS3AdminClient.hpp
  - thirdparty/sgns-blockstore/src/InMemoryS3AdminClient.cpp
  - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
  - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
  - thirdparty/sgns-blockstore/test/s3_admin_client_test.cpp
  - thirdparty/sgns-blockstore/test/local_block_store_test.cpp
  - thirdparty/sgns-blockstore/test/api_hygiene_test.cpp
  - thirdparty/sgns-blockstore/docs/s3d-durability.md
  - GeniusWallet/assets/crdt_config.json
covered_digest: "v2:sha256:7bb438ec8c2e5408f2c8fad5aeb5a2e58df723bf3c6dd203405add196e659fb3"
---

# Phase 10: Flush-Gated Durability Advancement — Verification Report

**Phase Goal:** `Durable` is an evidence-backed state, not an assumption — recorded durability advances LocalCommitted → ObjectStoreAccepted → Durable via s3d `/objects/flush` + `pendingObjects==0` evidence before bulk `MarkUploadedDurable`, making the eviction safety gate honest before any GC exists
**Verified:** 2026-10-27T02:22:00Z
**Status:** passed
**Re-verification:** No — initial verification

**Method:** goal-backward verification against the actual codebase. SUMMARY claims were not trusted; every must-have was checked at all four levels (exists → substantive → wired → data flows), and — because every truth in this phase is behavior-dependent (journal state transitions, cancellation/budget invariants) — the phase's own Tier-1 suites were **re-run by the verifier** as behavioral evidence:

```
ctest -R "^cold_storage_durability_test$|^cold_storage_config_gate_test$"  → 2/2 Passed (9.98 s + 0.02 s, Tier1)
ctest -R "^s3_admin_client_test$|^local_block_store_test$|^api_hygiene_test$" → 3/3 Passed (2.95 s, Tier1)
```

## Goal Achievement — Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| T1 | SC1: a flush cadence drives POST /objects/flush, observes pendingObjects==0, then advances exactly the pre-flush UploadedAccepted snapshot | ✓ VERIFIED | `ColdStorageManager.cpp:411-541` `AdvanceDurabilityOnce`: cadence gate (floor + quiescence-or-backstop, flush backoff replaces floor while streak held) → snapshot via `GetUploadsInState(UploadedAccepted)` under `cold_store_mutex_` (:453-472) → admin `Flush(kCadenceFlushReadTimeoutMs)` + `GetUploadStats()` UNLOCKED, serialized only by `admin_mutex_` (:475-497) → evidence gate (:501) → `MarkUploadedDurableMany` over exactly the snapshot, re-locked (:514-524). Wired in the drainer lambda at :136 (`DrainOnce() → AdvanceDurabilityOnce(quiescent) → MarkIdle()`), quiescence from DrainOnce's own return value (:405-407). Behavior: `e2e_flush_gated_advancement` green (flush_count ≥ 1 → all CIDs UploadedDurable → status evidence fields) |
| T2 | SC1: a record marked Durable is ALWAYS evidence-backed — failed/non-200/non-zero-evidence cycles mark ZERO, records stay Accepted, separate flush backoff engages | ✓ VERIFIED | Evidence gate `:501-505` (`pendingObjects != 0` → `RecordFlushNoEvidence`, zero marks); flush/stats failures → `RecordFlushFailedCycle` before any mark (:479, :486); flush backoff state fully disjoint from drain backoff (`flush_failure_streak_`/`flush_delay_` vs `failure_streak_`/`current_delay_`, hpp :311-318; `RecordFlushFailedCycle` never touches `healthy_`, .cpp :596-618). Behavior: `evidence_gate_pending_objects_blocks_advancement`, `flush_failure_keeps_accepted_then_recovers`, `garbage_stats_keeps_accepted_then_recovers` all green |
| T3 | Every S3AdminClient failure (transport/timeout/non-200/non-JSON/missing field) classifies TemporarilyUnavailable — never NotFound | ✓ VERIFIED | `S3AdminClient.cpp:43-48`: ONE classifier `AdminUnavailable` is the only status minter, always `StatusClass::TemporarilyUnavailable`; zero `NotFound` occurrences in the file; strict `ParseUploadStats` requires all 15 fields present+unsigned (:110-142). Behavior: `S3AdminClientWire.Flush500MapsTemporarilyUnavailable`, `.StatsGarbageBodyMapsTemporarilyUnavailable`, `.StatsMissingPendingObjectsMapsTemporarilyUnavailable`, `.FlushReadBudgetBoundsABlockedResponse` green |
| T4 | SC2: per-CID LocalCommitted→ObjectStoreAccepted→Durable transitions observable via `GlobalDB::GetColdUploadState` + the ColdStorageStack bridge | ✓ VERIFIED | `globaldb.cpp:898-909` active-accessor (lifecycle_mutex_, shutdown → NoRecord); ungated `ColdUploadState` enum in `ColdStorageStack.hpp:44-52`; null-safe bridge `ColdStorageStack.cpp:262-289` mapping the library triple + no-record; ODR twin `ColdStorageStackStub.cpp:59` (OFF builds link); manager pass-through `.cpp:543-547` under `cold_store_mutex_`. Behavior: `eviction_gate_constant_and_per_cid_state` reads PendingUpload pre-cycle; every suite assertion uses the pass-through |
| T5 | SC2: the eviction gate `kEvictionDurabilityGate` is compile-time `UploadedDurable`; no config can lower it | ✓ VERIFIED | `ColdStorageManager.hpp:77-79` `static constexpr ... UploadState::UploadedDurable`; behavior: `static_assert` + `EXPECT_EQ` in `eviction_gate_constant_and_per_cid_state` (test :611-613); config surface offers no gate knob (T13 parse accepts only the two interval knobs) |
| T6 | SC3: crash-between-journal-and-drain recovers via journal reconciliation over mixed Pending+Accepted leftovers | ✓ VERIFIED | Behavior: `crash_reconciliation_mixed_leftovers` (test :646-720) — manager A without admin client drains 3→Accepted/2→Pending, store released (WAL tail), reopen over SAME dir, first poll re-drains Pending, first eligible cycle advances Accepted, all 5 Durable, accepted count 0. Green |
| T7 | SC3: an s3d admin outage never surfaces NotFound, never blocks a publish, drain/flush backoffs independent | ✓ VERIFIED | Behavior: `admin_outage_never_not_found_and_drain_unpoisoned` (test :722-776) — publishes through the decorator succeed during Unreachable, `GetUploadState` never NotFound-shaped, `drainer_healthy` true while `flush_backoff_active` engages, recovery resets both. Green |
| T8 | SC3: shutdown under load with SlowFlush is bounded (grace + final budget), records left Accepted, resume proven | ✓ VERIFIED | Behavior: `shutdown_under_load_slow_flush_bounded` (test :809-876) — 3 s SlowFlush > 2 s budget, publisher thread live, `Stop()` elapsed < `kShutdownGraceWindow + kFinalFlushBudgetMs + margin` (measurement printed), Accepted > 0 after Stop, fresh manager over same dir drains/advances everything. Green |
| T9 | Idempotent replay: extra cycles over an all-Durable journal mark nothing (10-01 flagged assumption discharged) | ✓ VERIFIED | Behavior: `idempotent_replay_marks_nothing` (test :879-896) — flush_count advances by ≥2, durable count unchanged, all states still Durable. Green. Construction: empty snapshot does NOT skip the observation (10-02 fix, .cpp :457-462 comment + code) |
| T10 | Acceptance race: a CID accepted after the snapshot is NOT marked on that cycle's evidence (10-01 flagged assumption discharged) | ✓ VERIFIED | Behavior: `acceptance_race_mid_flush_excluded_from_marks` (test :905-961) — `SetOnFlush` hook journals+accepts cid_y mid-flush under `cold_store_mutex_`; cid_x advances on the zero-pending evidence while cid_y stays Accepted until exactly the next cycle. Green |
| T11 | SC4: staging counters + conservative `staging_healthy` predicate; unhealthy on buffer fraction, failedUploads growth, unreachable/garbage evidence | ✓ VERIFIED | `UpdateStagingHealth` (.cpp :571-599): three-clause predicate `admin_reachable && (bufferLimit==0 ‖ bufferUsed ≤ 0.8·bufferLimit) && failedUploads flat-delta`, `kStagingBufferFraction = 0.8` public (hpp :101-105); called on every stats-observing tick (success :495 AND failure paths :479/:486 with `admin_reachable=false` fail-safe, counters keep last-known). Behavior: `staging_healthy_on_clean_stats`, `staging_unhealthy_when_buffer_fraction_exceeded`, `staging_zero_limit_is_unlimited`, `staging_unhealthy_on_failed_uploads_growth`, `staging_fail_safe_on_admin_unreachable` all green |
| T12 | SC4: `RefreshStagingStats()` on-demand, `admin_mutex_`-serialized, no poller; GetStatus pure atomics; restart count seeding | ✓ VERIFIED | `RefreshStagingStats` (.cpp :549-568) — one guarded `GetUploadStats` under `admin_mutex_`, fail-safe false; same `admin_mutex_` held by the tick's admin calls (:476) and Stop's final flush (:198) — the admin client is never used concurrently. `GetStatus` (.cpp :257-280) reads ONLY atomics — no journal scan, no HTTP, no lock (source-verified line-by-line). Restart seeding at first-poll boundary in the drainer lambda (.cpp :117-133). Behavior: `staging_refresh_on_demand_updates_without_tick`, `staging_restart_seeding_counts` green |
| T13 | Config: `blockstore.durability` strict parse — defaults 30000/300000, 0-knob → only its default, unknown/wrong-type loud naming `blockstore.durability.<key>`, min≤max loud naming BOTH effective values, durability-only section never activates; `admin_endpoint` optional string | ✓ VERIFIED | `globaldb.cpp:231-264` (must-be-object, strict two-knob uint-only sub-loop, exact loud strings), :134-135 (defaults 30000/300000), :345-365 (post-normalization min≤max with both effective values), :266-267/:301-304 (`admin_endpoint` optional string key, non-string loud), :380-389 (file-intent gate: optional-only ⇒ disabled — durability-only never activates). Defense-in-depth normalization at the stack (`ColdStorageStack.cpp:146-176`). Behavior: `DurabilityAbsentSubObjectGivesDefaults`, `DurabilityZeroKnobTakesOnlyItsDefault`, `DurabilityUnknownKeyFails`, `DurabilityWrongTypeFails`, `DurabilityMinAboveMaxFails`, `DurabilityOnlySectionDisables`, `AdminEndpointOptionalString` green in `cold_storage_config_gate_test` |
| T14 | `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` env-only, never activates, never logged, never at rest | ✓ VERIFIED | `globaldb.cpp:84-95` env read in the unset-or-empty-is-none shape; `LogSummary` (:97-116) references endpoint/knobs but NEVER the password (redaction by omission); `S3AdminClient.cpp` contains zero logging constructs; the manager sees only a presence flag (`SetAdminPasswordPresent`, hpp :160-172; stack sets it `ColdStorageStack.cpp:198`); the missing-password posture is default-on + one-time WARN naming the env var (`Start()`, .cpp :109-116). Wallet asset carries no credential |
| T15 | D-04: Stop()'s bounded final flush — `final_flush_done_` exactly-once, `kFinalFlushBudgetMs`, advance-or-leave-Accepted with resume | ✓ VERIFIED | `ColdStorageManager.cpp:177-242`: post-join, `final_flush_done_.exchange(true)` guard, snapshot under `cold_store_mutex_`, one `Flush(kFinalFlushBudgetMs)` + `GetUploadStats()` under `admin_mutex_` (short budget — NOT the cadence timeout), `pendingObjects==0` → `MarkUploadedDurableMany`, ANY failure → one log line + records stay Accepted. `AdvanceDurabilityOnce` checks `stop_flag_` before initiating (:418). Behavior: `shutdown_final_flush_advances` (flush_count 0→1, all Durable at Stop return) and `shutdown_final_flush_failure_leaves_accepted` (reopen + fresh manager advances) green, plus T8's under-load bound |
| T16 | Wallet asset parity: `GeniusWallet/assets/crdt_config.json` carries `"durability": {}` inside `blockstore` | ✓ VERIFIED | File read: `{"blockstore": {"backpressure": {}, "durability": {}}}` — blank form = defaults = no activation change (Phase-7 D-03 posture) |

**Score:** 16/16 truths verified (0 present-but-behavior-unverified — every behavior-dependent truth has a passing wired test, re-run by the verifier)

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `thirdparty/sgns-blockstore/include/sgns-blockstore/S3AdminClient.hpp` | ✓ VERIFIED | Installed facade: `UploadStats` (15 verbatim openapi fields, `pendingObjects` the evidence field, `activeUploads` omitted), `Flush(explicit per-call budget)` virtual, `S3AdminFaultKind`, `OpenS3dAdminClient` factory; compiles standalone (`api_hygiene_test.cpp:58` includes it with only sgns-blockstore + p2p::p2p_cid — PRIVATE-link proof, green) |
| `thirdparty/sgns-blockstore/src/S3AdminClient.cpp` | ✓ VERIFIED | Pimpl, httplib/nlohmann confined to the TU, Basic auth `base64(":" + password)` (empty username — asserted on the wire by `FlushCarriesEmptyUsernameBasicAuth`), single failure classifier, zero logging |
| `thirdparty/sgns-blockstore/src/InMemoryS3AdminClient.{hpp,cpp}` | ✓ VERIFIED | Scripting surface `SetStats`/`SetAdminFault`/`SetSlowFlushDelayMs`/`SetOnFlush`/`flush_count` all tagged CONFORMANCE-TEST SEAM (hpp :49-84); budget-faithful Flush (delay beyond budget surfaces timeout) — exercised green by the shutdown-under-load test |
| `LocalBlockStore::GetUploadsInState(UploadState)` | ✓ VERIFIED | `.cpp:559-599`: CF iterator, state filter, byte-lexicographic ordering (bytewise comparator), undecodable skip, post-loop iterator status check; `GetPendingUploads` delegates (:601-606) — one scan body. Unit: `GetUploadsInStateFiltersAndSorts` green |
| `LocalBlockStore::MarkUploadedDurableMany(span)` | ✓ VERIFIED | `.cpp:669-723`: per-item read-gate with skip-and-continue on no-record (no fabrication, no batch abort), ONE `rocksdb::WriteBatch` + ONE sync Write (single fsync, all-or-nothing crash window). Unit: `MarkUploadedDurableManySkipsAndContinues` green |
| `ColdStorageManager::AdvanceDurabilityOnce(bool)` | ✓ VERIFIED | See T1/T2 — full split-phase chain, wired at :136 |
| Public constants `kEvictionDurabilityGate` / `kFinalFlushBudgetMs` / `kCadenceFlushReadTimeoutMs` | ✓ VERIFIED | hpp :70-107, all public; values pinned by `eviction_gate_constant_and_per_cid_state` (static_assert + EXPECT_EQ: 30000/300000/30000/2000) |
| `ColdStorageManager::RefreshStagingStats()` + `kStagingBufferFraction` | ✓ VERIFIED | See T11/T12 |
| `SuperGenius/test/src/crdt/cold_storage_durability_test.cpp` | ✓ VERIFIED | 21 tests, real fixture (per-case fresh RocksDB dirs, real LocalBlockStore + InMemoryS3Client + InMemoryS3AdminClient, direct manager construction, PollUntil with deadlines, given/when/then doc blocks). Registered `CMakeLists.txt:157-170` with `LABELS "Tier1"` and the relative sgns-blockstore/src include dir. **Re-run green by the verifier (9.98 s)** |
| `thirdparty/sgns-blockstore/test/s3_admin_client_test.cpp` | ✓ VERIFIED | 6 wire tests against LoopbackHttpStub incl. black-hole budget proof. **Re-run green (0.25 s)** |

### Key Link Verification

| From | To | Via | Status |
|------|----|----|--------|
| Drainer lambda | AdvanceDurabilityOnce | `ColdStorageManager.cpp:136` — DrainOnce() → AdvanceDurabilityOnce(quiescent) → MarkIdle(), quiescence from DrainOnce's return | ✓ WIRED |
| AdvanceDurabilityOnce | Library journal | snapshot `GetUploadsInState(UploadedAccepted)` + `MarkUploadedDurableMany` (exactly the snapshot) under `cold_store_mutex_` | ✓ WIRED |
| OpenColdStorageStack | Admin facade | `ColdStorageStack.cpp:177-199` — `OpenS3dAdminClient` beside `OpenMinioS3Client`, inside the invalid_argument try/catch; durability normalization :146-176; widened ctor + `SetAdminPasswordPresent` | ✓ WIRED |
| Env → config → manager | `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` | `DefaultColdStorageEnvLookup` (globaldb.cpp:84-95) → `options.adminPassword` (:425) → stack → admin config + presence flag | ✓ WIRED |
| GlobalDB | Per-CID state | `GlobalDB::GetColdUploadState` (globaldb.cpp:898-909) → `GetColdUploadState` bridge (ColdStorageStack.cpp:262) / stub twin (ColdStorageStackStub.cpp:59) | ✓ WIRED (both build configs) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| ColdStorageStatus flush evidence | accepted/durable counts, last_flush_* | journal scans on the drainer tick → atomics | Yes — journal-derived, re-derived every cycle, seeded at restart | ✓ FLOWING |
| ColdStorageStatus staging fields | staging_* counters | live `GetUploadStats()` observations (tick + on-demand) → atomics | Yes — fake-scripted in tests, real admin client in production | ✓ FLOWING |
| Durability marks | snapshot vector | `GetUploadsInState(UploadedAccepted)` over the real RocksDB journal | Yes — the only mark input; race test proves late accepts excluded | ✓ FLOWING |

No static returns, hardcoded evidence, or mock-only paths found on any production path (fakes are test-fixture-only and seam-tagged).

### Behavioral Spot-Checks (verifier-executed)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full SC1-SC4 suite (21 tests) | `ctest -R "^cold_storage_durability_test$" ...` | Passed, 9.98 s | ✓ PASS |
| Config matrix (incl. 7 Durability/AdminEndpoint cases) | `ctest -R "^cold_storage_config_gate_test$" ...` | Passed, 0.02 s | ✓ PASS |
| Library wire lane (auth header, 500/garbage/missing/timeout mappings) | `ctest -R "^s3_admin_client_test$" ...` | Passed, 0.25 s | ✓ PASS |
| Library journal units + hygiene | `ctest -R "^local_block_store_test$|^api_hygiene_test$" ...` | Passed, 2.70 s | ✓ PASS |

### DUR-01 Traceability

**Requirement (REQUIREMENTS.md:36):** *"recorded durability advances LocalCommitted → ObjectStoreAccepted → Durable via s3d `/objects/flush` + `pendingObjects==0` evidence (`MarkUploadedDurable`); local bytes become evictable only after the configured durability state is recorded"*

| Must | Evidence | Status |
|------|----------|--------|
| Transitions advance via flush + pendingObjects==0 evidence | T1/T2 — `AdvanceDurabilityOnce` + 5 green tests | ✓ SATISFIED |
| Bulk mark via `MarkUploadedDurable` (batched) | `MarkUploadedDurableMany` — one WriteBatch + one sync Write, the sole mark path in both the tick (:516) and final flush (:226) | ✓ SATISFIED |
| Local bytes evictable only after the durability state is recorded | The gate the Phase-11 eviction consults exists and is pinned: `kEvictionDurabilityGate == UploadedDurable` compile-time (T5), per-CID state queryable end-to-end (T4), testable standalone. Eviction EXECUTION is Phase 11 by roadmap design — no deletion code exists in this phase (prohibition held: no evict/delete/backup-engine files touched) | ✓ SATISFIED (gate recorded; execution deferred to Phase 11 by design) |
| Status | REQUIREMENTS.md coverage matrix :83 — DUR-01 Complete (10-01 + 10-02, 2026-10-26); both plans declare `requirements: [DUR-01]`; no orphaned requirement maps to Phase 10 | ✓ SATISFIED |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `thirdparty/sgns-blockstore/include/sgns-blockstore/Durability.hpp` | 19, 27 | "placeholder" wording | ℹ️ Info | Pre-existing v1.0 enum docs anchoring future (Phase 11+) eviction states — NOT modified by this phase, references formal follow-up work; no action needed |
| `cold_storage_durability_test.cpp` (cadence_floor test) | 491 | one 500 ms settle sleep | ℹ️ Info | A single bounded settle wait after a PollUntil gate, not a fixed-sleep test construct; suite runs in 10 s — no flakiness signal |

No TBD/FIXME/XXX markers, no stub implementations, no console-only bodies, no empty handlers in any phase-modified file. `GetStatus()` purity, never-NotFound taxonomy, password-redaction-by-omission, and snapshot-only marking were each verified at source level AND pinned by green tests.

### Prohibition Discharge (must-NOT checks from both plans)

1. **No mark without observed evidence** — evidence gate :501 + `evidence_gate_pending_objects_blocks_advancement` / `flush_failure` / `garbage_stats` green. HELD.
2. **No CID outside the snapshot marked** — snapshot is the only mark input; `acceptance_race_mid_flush_excluded_from_marks` green. HELD.
3. **Flush failures never NotFound, never block writes, backoffs separate** — classifier (T3) + `admin_outage_never_not_found_and_drain_unpoisoned` green (publishes succeed, drainer_healthy true). HELD.
4. **No config knob lowers the gate** — compile-time constant; parse accepts only interval knobs. HELD.
5. **Admin password never at rest/logged/in status** — T14. HELD.
6. **No eviction, no backup-engine touch** — phase file list touches neither; gate-recording only. HELD.
7. **(10-02) No crash path fabricates/drops/partially applies journal state** — batched mark all-or-nothing over the verified set; crash test proves leftovers resume. HELD.
8. **(10-02) Staging never healthy on unreadable/garbage/absent evidence** — fail-safe false on unreachable/garbage; `staging_fail_safe_on_admin_unreachable` green. HELD.
9. **(10-02) No scan/HTTP/lock in GetStatus** — source-verified pure atomics. HELD.

### Gaps Summary

None. All 16 merged must-haves (ROADMAP SC1-SC4 + both plans' must-have truths + prohibitions) verified against the codebase with the phase's Tier-1 suites re-run green by the verifier. Both 10-01 flagged assumptions (idempotent replay, acceptance race) are discharged by wired green tests, not construction claims. The 10-02 construction change those tests forced (empty-snapshot cadence observation) is present in the shipped code with its rationale comment.

Deferred (informational, by roadmap design — not gaps): eviction execution consuming the gate is Phase 11 ("Retention GC of Cold-Eligible CRDT Data" — "Eviction-only GC behind durability + non-reachability gates"); race-matrix hardening is Phase 12.

### Human Verification Required

None. Every truth is exercised by automated Tier-1 evidence re-run in this verification. (Optional, dev-gated only, never CI/blocking per 10-02's verification section: re-running the s3d spike runbook against a live s3d v0.2.1 to eyeball flush/stats shapes remains available to the developer.)

---

_Verified: 2026-10-27T02:22:00Z_
_Verifier: the agent (gsd-verifier)_
