---
phase: 16-txpruner-gc-composition-hardening
verified: 2026-11-24T20:45:00Z
status: passed
score: 3/3 must-haves verified
covered_files:
  - .planning/workstreams/rocksdb-backup/notes/16-txpruner-gc-composition-rulings.md
  - .planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-01-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-01-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-02-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-02-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-03-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-03-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/16-txpruner-gc-composition-hardening/16-UAT.md
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
  - SuperGenius/src/crdt/globaldb/globaldb.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.hpp
  - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
  - SuperGenius/src/transaction/TxPruner.cpp
  - SuperGenius/src/transaction/TxPruner.hpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - SuperGenius/test/src/crdt/cold_compose_live_smoke_test.cpp
  - SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp
covered_digest: "v2:sha256:65fe4a16635c3ed384627710fcc3af3e70620b91f3dd9bcdab10a79feeeaa3c7"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: passed_with_uat
  previous_score: 3/3
  gaps_closed:
    - "The MinIO live SC3 leg (the sole prior human-verification item): closed via 16-UAT.md - 1/1 passed, accepted on hermetic coverage (cold_compose_matrix_test, the S3a deterministic stand-in) with the live leg recorded as the standing dev-opt-in per D-11b's hybrid posture (parent commit c0af2ab)"
  gaps_remaining: []
  regressions: []
---

# Phase 16: TxPruner × GC Composition Hardening — Verification Report

**Phase Goal (ROADMAP):** Concurrent TxPruner and GC passes proven safe on the gated, evidence-aware line — sequenced (never unified) — with the stale-LRU erase window closed (SC1/COMP-01), the interleave matrix proven (SC2/COMP-02), and the disposal-starvation interplay ruled fail-safe: under-prune (SC3/COMP-03).
**Verified:** 2026-11-24T20:45:00Z
**Status:** passed
**Re-verification:** Yes — regeneration of the prior nonstandard `passed_with_uat` report (written by the inline executor) now that its one human item has closed; all checks re-run against CURRENT HEAD after phases 17-19 forward drift.

**Lineage at verification:** SuperGenius `41776b0c0` (fix(19-05), tag `test_coldstorage`) · parent `c0af2ab` (test(16): complete UAT — 1 passed, 0 issues).

## Goal Achievement

### Observable Truths

| # | Truth (ROADMAP SC / requirement) | Status | Evidence (at HEAD, this verification) |
|---|--------------------------------|--------|----------------------------------------|
| 1 | **SC1 / COMP-01** — `EraseEntry`'s post-commit cleanup hardened to GC parity: a concurrent `GrabCIDBlock`-path insert between compose-start and commit cannot leave a stale LRU entry | ✓ VERIFIED | `globaldb.cpp:1739` `BOOST_OUTCOME_TRY( batch->commit() )` → `:1755` `(void)m_dagSyncer->DeleteCIDBlock( cid )` → `:1763` seal re-assert — the delete sits strictly between the commit and the re-assert, so **both committed exits** (success and `POST_COMMIT_ERASE_ANOMALY` at `:1772`) are covered; full block read — the call is **unconditional** (no caller-identity, cold-state, marker, or flag condition). Guard 3 admission intact (`:1645-1652`, `IsCIDInCache` refusal with `Error::INVALID_PARAMETERS`). GC parity intact: `ColdStorageManager.cpp:1389-1424` `RunHotCleanup` still batch → commit → A6 `DeleteCIDBlock` (no symmetry edit leaked through phases 17-19). Deterministic seam present: static `erase_window_observer_for_test_` (`:1477`), setter (`:1483`), fire immediately before the commit (`:1735-1737`, void observe-and-continue). Legs W1-W4 present in the suite (truth 2). Behavioral: suite PASS this run |
| 2 | **SC2 / COMP-02** — interleave matrix over overlapping set rows, seal rows, and the block LRU proves both pruners idempotent on absent keys, seals untouched, both erase orders converging | ✓ VERIFIED | Full 18-leg inventory present in `cold_compose_matrix_test.cpp` at HEAD: W1 `:1092`, W2 `:1211` (real-thread `WindowGate` `:1154`), W3 `:1279`, W4 `:1340`; M1 `Converge_TxPrunerThenGC_Matches_GCThenTxPruner` `:1788`, M2-M4 `Interleave_*` `:2027/:2098/:2154`, M5-M6 `Crossfire_*` `:2211/:2267`, M7 `Seals_NeverTouched…` `:2306`, M8 `Converge_FixedPointIsStable…` `:2359`; R1-R2 `Race_*` `:2507/:2589`, R3 `InteractionC_DurabilityFlipStraddlingReads_LastCopySurvives` `:2645`. Registration: `CMakeLists.txt:487-518` — inside `if(SGNS_COLD_STORAGE)` with `set_tests_properties(cold_compose_matrix_test PROPERTIES LABELS "Tier1")`. Sequencing (never unified) holds: ruling doc §f D-01 records free concurrency + no mutex/serialization wrapper; no mutual-exclusion machinery found in either pruner at HEAD. The 16-03 semantic re-scoping (order-INVARIANT projection converges; the walk-gap under-eviction and D-10 stranding are designed per-order terminal states, asserted as the divergence table) stands as recorded — no idempotence-contract divergence (D-03) ever fired. Behavioral: suite PASS this run |
| 3 | **SC3 / COMP-03** — GC-disposal starvation interplay ruled, documented, fail-safe direction asserted by test: under-prune, never destruction of the last copy | ✓ VERIFIED | Consult chain intact at HEAD: `TxPruner.cpp:133` `globaldb.IsColdDisposed( cid )` → `globaldb.cpp:1521` `GlobalDB::IsColdDisposed` (const) → free bridge `sgns::crdt::IsColdDisposed( cold_manager_, cid )` `:1534` → `ColdStorageManager.cpp:736-742` `IsDisposed` under `cold_store_mutex_` → `local_block_store_->IsDisposed` (library-owned keyspace, no third builder). **Only the NoRecord arm consults** (`TxPruner.cpp:120-135`); Pending/Accepted/default never consult (`:137-146`). Stranded split counter surfaces: `++stats.cold_disposed_stranded_groups` (`:135`) + INFO `cold_disposed_stranded={}` between `cold_unreadable` and `skipped` (`:422-431`) — a counter, never an error. Deterministic legs present: S3a `:1508`, S3b `:1626`, S3c `:1689`; Tier-3 live leg `cold_compose_live_smoke_test` registered with `LABELS "Tier3"` (`CMakeLists.txt:702-732`). Rulings documented at both destructive homes + `notes/16-txpruner-gc-composition-rulings.md` (D-01/D-02/D-10/D-12 records present, incl. the D-01 sequencing record and the under-prune ruling). Prior human item CLOSED: 16-UAT.md 1/1 pass (parent commit `c0af2ab`) — the live leg accepted on hermetic coverage with the dev-opt-in posture recorded. Behavioral: suite PASS this run |

**Score:** 3/3 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/src/crdt/globaldb/globaldb.cpp` | SC1 close + observer seam + IsColdDisposed bridge | ✓ VERIFIED | Commit→delete→re-assert ordering at `:1739/:1755/:1763`; seam fire `:1735`; bridge `:1521-1534` |
| `SuperGenius/src/crdt/globaldb/globaldb.hpp` | Seam declaration + bridge declaration | ✓ VERIFIED | Declarations present beside the sibling hook families |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp/.hpp` | `IsDisposed` pass-through + D-12 comment at the disposal home | ✓ VERIFIED | `:736-742` pass-through; `EvictLocalAndMarkDisposed` consumption `:1353`; `RunHotCleanup` A6 order unchanged |
| `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp/.hpp` | Null-safe `IsColdDisposed` free bridge | ✓ VERIFIED | The D-09 layering hop the consult routes through |
| `SuperGenius/src/transaction/TxPruner.cpp/.hpp` | NoRecord split + stranded counter + INFO surfacing | ✓ VERIFIED | `:120-146` arm structure; `:135` counter; `:422-431` INFO label |
| `SuperGenius/src/crdt/graphsync_dagsyncer.hpp` | AddCIDBlock/GrabCIDBlock public beside their siblings | ✓ VERIFIED | The counter-test surface (16-01 access-only change) |
| `SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp` | 18-leg Tier-1 evidence suite (W/S/M/R families) | ✓ VERIFIED | All 18 legs located by name at HEAD (truth table); PASS this run |
| `SuperGenius/test/src/crdt/cold_compose_live_smoke_test.cpp` | Env-gated Tier-3 live leg | ✓ VERIFIED | Registered `:702-732`, `LABELS "Tier3"`, env-gated loud skip |
| `SuperGenius/test/src/crdt/CMakeLists.txt` | Suite registrations | ✓ VERIFIED | `:487-518` Tier-1 under `SGNS_COLD_STORAGE`; `:702-732` Tier-3 |
| `.planning/…/notes/16-txpruner-gc-composition-rulings.md` | D-12 ruling doc (options, v2 pointer, lag, sequencing) | ✓ VERIFIED | D-01 §f / D-02 / D-10 / D-12 / under-prune records confirmed present |

### Key Link Verification

| From | To | Via | Status |
|------|----|----|--------|
| Observer fire (pre-commit) | Post-commit `DeleteCIDBlock` eviction | `batch->commit()` between them — the deterministic SC1 proof path | ✓ WIRED (`:1735 → :1739 → :1755`) |
| TxPruner NoRecord arm | Library disposed keyspace | `GlobalDB::IsColdDisposed` → free bridge → `ColdStorageManager::IsDisposed` → `LocalBlockStore::IsDisposed` | ✓ WIRED (all four hops read at HEAD) |
| `PruneCycleStats.cold_disposed_stranded_groups` | Operator visibility | `RecordCompletedCycle` INFO `cold_disposed_stranded={}` | ✓ WIRED (`TxPruner.cpp:422-431`) |
| Matrix legs | Park points | `SetEraseWindowObserverForTest` + GC hook families + `WindowGate` barriers | ✓ WIRED (gate at `:1154`, used `:1233/:2052-2169/:2517-2746`) |
| Suite → ctest | Tier-1 lane | `if(SGNS_COLD_STORAGE)` + `set_tests_properties … LABELS "Tier1"` | ✓ WIRED (ran green via exactly this registration) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| The phase's full evidence suite at CURRENT HEAD (all 18 legs: SC1 window close both layers, SC3 stranded cycle, SC2 matrix + races) | `ctest --test-dir SuperGenius/build/Windows/Release -C Release -R "^cold_compose_matrix_test$" --no-tests=error` | `1/1 Test #112: cold_compose_matrix_test … Passed 37.14 sec`, exit=0, Tier1 label | ✓ PASS |

Corroborating runs cited (today, per execution context): the same suite PASSED at 37.22s inside an 18/18 Tier-1 local lane, and the phase-19 CI capstone ran Tier-1 20/20 on three platforms — consistent with the independent PASS recorded above.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| COMP-01 | 16-01 | Post-commit cleanup hardened to GC parity — stale-LRU window closed | ✓ SATISFIED | Truth 1 |
| COMP-02 | 16-03 | Interleave matrix proven — idempotent, seals untouched, converging | ✓ SATISFIED | Truth 2 |
| COMP-03 | 16-02 | Disposal-starvation interplay ruled, documented, fail-safe asserted by test | ✓ SATISFIED | Truth 3 (deterministic + UAT-closed live posture) |

No orphaned requirements: REQUIREMENTS.md maps exactly COMP-01/02/03 to Phase 16, all claimed by plans and satisfied.

### Anti-Patterns Found

Debt-marker scan (`TBD|FIXME|XXX`) over all phase-changed production and test files: zero matches. The prior verification's registered deferred items (coldstore handle leak after retention-GC shutdown; the standing PollUntil sleep-count probe-letter deviation) remain documented postures in the ruling doc/16-02 SUMMARY — non-blocking, unchanged by phases 17-19.

### Human Verification Required

None remaining. The prior report's sole human item — the MinIO live SC3 leg — was resolved in 16-UAT.md (1/1 passed, `c0af2ab`): accepted on hermetic coverage with the live run recorded as the standing developer opt-in per the D-11b hybrid posture. That acceptance IS the human decision this verifier would otherwise have requested; nothing new requires human judgment.

### Gaps Summary

None. All three roadmap success criteria hold at current HEAD (`41776b0c0`) despite phases 17-19 touching overlapping files — the drift is legitimate forward work and every phase-16 must-have survived it: the SC1 close retains its single-home placement and both-exit coverage, guard 3 and GC's sanctioned A6 ordering are unedited, the consult chain and stranded counter are intact with NoRecord-only discipline, the 18-leg suite is registered Tier-1 under `SGNS_COLD_STORAGE`, the D-01 sequencing record (concurrent, never unified, no mutex) is both documented and reflected in the code, and the suite passed under this verifier's own run at HEAD.

---

_Verified: 2026-11-24T20:45:00Z_
_Verifier: gsd-verifier (regenerated canonical report; supersedes the inline-executor `passed_with_uat` report of 2026-11-18)_

