---
phase: 14-durability-gated-txpruner-eligibility
plan: 03
subsystem: transaction
tags: [txpruner, cold-storage, journal-matrix, composition, live-smoke, tier1, evidence]

# Dependency graph
requires:
  - phase: 14-01
    provides: the admission conjunct + counters + the gate-suite fixture family
  - phase: 14-02
    provides: guard 5 + the SetColdUploadStateHookForTest injector (the gate-level Unreadable driver) + step-5 seam
provides:
  - The journal-CF seeding helper (populate -> seed -> reopen against the published upload_journal CF + 2-byte codec)
  - The five-state matrix legs: NoRecord/Accepted (direct CF seeding, D-02 defer-forever), garbage adjacency (conservative decode -> Pending -> defer), Pending/Durable (from 14-01)
  - Unreadable at bridge level (real FaultController fault -> free-bridge mapping, zero overrides) and gate level (dedicated counter + exactly-one WARN observed via a counting sink + cycle completes + re-evaluation)
  - The ordering edge (deferred leader never blocks a Durable follower, same-cycle erase) and the empty edge (zero counter motion)
  - The SC3 composition crossing legs (non-erasable x Durable never erases — no widening; AND-conjunction reads both verdicts directly) + the D-C6 purity citation in the suite header
  - cold_prune_live_smoke_test — env-gated (SGNS_BLOCKSTORE_TEST_MINIO_BIN) live-stack smoke, Tier3 registration, loud-skip proven
  - The phase's SC evidence checklist (SC1-SC4) with proving ctest invocations
affects: [Phase 15 (evidence-aware serving composes with the fully proven gate), Phase 16 (Interaction-C: the post-re-check window; pruner×GC hardening), Phase 19 (the Tier-1 contract surface)]

# Actuals (#2632) — pairs with the plan's `estimate` to calibrate future estimates.
actuals:
  tokens: 16900
  tasks: 3
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns: ["journal-CF seeding three-phase flow: populate -> TeardownStack -> raw-RocksDB seed (published CF + codec) -> BuildStackOnDir reopen — legal only while the GlobalDB is closed (dir lock)", "held-journal fixture posture: the SAME hermetic fakes injected but FAULTED (S3 Put Unavailable + admin Unreachable) so the drainer's IMMEDIATE first pass (D-12 crash-restart reconciliation) moves no record — the determinism contract for every seeded/held leg", "spend-recency window keys on the SPENDER's height: an in-window candidate seeds its spender RECENTLY (after the drivers) — the inverse of RealPrune's ancient-spender-first recipe"]

key-files:
  created:
    - SuperGenius/test/src/crdt/cold_prune_live_smoke_test.cpp
  modified:
    - SuperGenius/test/src/crdt/cold_prune_gate_test.cpp
    - SuperGenius/test/src/crdt/CMakeLists.txt

key-decisions:
  - "Held-journal legs inject FAULTED hermetic fakes rather than constructing the production client against hermetic.invalid: the drainer's FIRST poll runs immediately on Start (D-12) — healthy fakes advance every Pending to Accepted within milliseconds, and the real minio-cpp client's construction is not in-process-safe against an unresolvable host (SEH 0xc0000005 observed)"
  - "The in-window (non-erasable) crossing leg seeds the spender RECENTLY: the window is maxHeight - spend_height >= N with spend_height = the spender's CRDT priority — the original no-post-spend-drivers shape left the candidate eligible because the spender was ancient"
  - "The gate-level Unreadable WARN is observed through a CountingWarnSink attached to the process-wide 'TxPruner' spdlog logger (base::createLogger registers it globally) — exactly one WARN per group per cycle, two after the re-evaluating second cycle"
  "live-leg posture: loud-skip proven by run ([SGNS_COLD_PRUNE][LIVE-SMOKE] naming the env var, runbook, and community-binary rule); live execution runbook-deferred — no MinIO community binary in this environment, LEG 1 is the deterministic stand-in per research A2/the plan's D-08c posture rule"

patterns-established:
  - "Deterministic arbitrary journal-state injection against a full GlobalDB: seed only while closed, assert the pre-seed record exists and the journal is non-empty, reopen without any state-advancing capability"
  - "Env-gated live smoke with self-contained child-process spawn (platform-split CreateProcess/fork-execl) + raw-TCP health probe + production-client injection + a documented operator bucket-precondition (mc mb) probed by a tiny Put"

requirements-completed: [PRUNE-01, PRUNE-02, PRUNE-03]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "The five-state journal matrix + three PRUNE-01 edges (adjacency/empty/ordering) as executable assertions"
    requirement: PRUNE-01
    verification:
      - kind: integration
        ref: "command: ctest -R cold_prune_gate_test → all 13 legs green (SeedVariants NoRecord/Accepted/GarbageStateByte/GarbageVersionByte, UnreadableBridge, Gate_Unreadable, Ordering, Empty, LEG 1/2/3, Composition x2)"
        status: pass
    human_judgment: false
  - id: D2
    description: "SC3 composition proof: crossing legs (incl. non-erasable x Durable no-widening) + the mechanical purity gate"
    requirement: PRUNE-03
    verification:
      - kind: integration
        ref: "command: ctest -R cold_prune_gate_test → Composition_NonErasableTimesDurableNeverErases + Composition_AndConjunctionReadsBothVerdicts green"
        status: pass
      - kind: other
        ref: "command: git -C SuperGenius diff --exit-code 2af184fa1 -- PruneEligibility.{hpp,cpp} → exit 0 (re-run at phase close)"
        status: pass
    human_judgment: false
  - id: D3
    description: "D-08c live smoke: env-gated, loud-skip proven; live leg runbook-deferred with the deterministic stand-in cited"
    requirement: PRUNE-01
    verification:
      - kind: manual_procedural
        ref: "run: cold_prune_live_smoke_test.exe with SGNS_BLOCKSTORE_TEST_MINIO_BIN unset → [  SKIPPED ] with the [SGNS_COLD_PRUNE][LIVE-SMOKE] labelled message (recorded verbatim in this summary)"
        status: pass
    human_judgment: true
    rationale: "The live wire leg requires a MinIO community binary the environment does not provide; the skip posture + runbook deferral is the plan's sanctioned D-08c posture and cannot be automated-green here"
  - id: D4
    description: "D-09 Tier-1 contract + zero-regression net at phase close"
    requirement: PRUNE-01
    verification:
      - kind: integration
        ref: "command: ctest -L Tier1 → 14/14 (incl. cold_prune_gate_test #108, cold_prune_toctou_test #109, tier1_static_audit)"
        status: pass
      - kind: integration
        ref: "command: ctest -R 'prune_eligibility_test|tx_pruner_test|node_startup_test|crdt_test|globaldb_integration_test|cold_storage_fallback_test|cold_storage_durability_test|cold_storage_gc_test|cold_storage_gc_retrievability_test|cold_storage_resurrection_test' → 10/10"
        status: pass
    human_judgment: false

# Metrics
duration: 65min
completed: 2026-11-17
status: complete
---

# Phase 14 Plan 03: Five-State Matrix + SC3 Composition + Live Smoke Summary

**SC1's matrix is complete — all five journal states, three boundary edges, group semantics, and the conservative-decode safety net are executable Tier-1 assertions; SC3 is proven behaviorally (the AND never widens) and mechanically (evaluator byte-identical); the live smoke exists with an honest dev-gated posture.**

## Performance

- **Duration:** ~65 min
- **Started:** 2026-11-17T04:00Z
- **Completed:** 2026-11-17T05:20Z
- **Tasks:** 3
- **Files modified:** 3 (1 extended suite, 1 new smoke, CMake)

## Accomplishments
- **Journal-CF seeding machinery (D-08a):** populate → TeardownStack → raw-RocksDB seed (published `upload_journal` CF, the verbatim 2-byte codec, `LocalBlockStore::MakeKey`-identical keys) → `BuildStackOnDir` reopen — with the lock discipline documented (seed only while the GlobalDB is closed) and pre-seed hygiene asserts (target record exists, journal non-empty).
- **The determinism contract that made the matrix possible:** the drainer's FIRST poll runs immediately on Start (D-12 crash-restart reconciliation) — healthy fakes advance everything to Accepted within milliseconds, and the real client's construction AVs on the unresolvable host. The held legs therefore inject the SAME hermetic fakes FAULTED (S3 Put→Unavailable, admin→Unreachable): drain and flush both fail, seeded bytes hold deterministically.
- **Matrix + edges green:** NoRecord/Accepted defer via direct seeding (D-02: re-evaluated next cycle, cycle completes — never permanent-stop); both garbage variants decode Pending and defer (never Durable, never the Unreadable counter — Pitfall 5a); Unreadable proven at bridge level (real `FaultKind::Unavailable` → free-bridge mapping, zero overrides) and gate level (dedicated counter, exactly-one WARN observed via a counting sink, cycle completes, re-evaluates); ordering (deferred leader, same-cycle Durable follower); empty (zero counter motion).
- **SC3 crossing legs:** non-erasable × Durable → not erased, NO cold-counter motion (the gate cannot widen admission — the in-window shape seeds the spender RECENTLY, the inverse of RealPrune's ancient-spender recipe); the AND-conjunction leg reads BOTH verdicts in-test (direct `PruneEligibility::Evaluate` + journal state) for an admitted group. The D-C6 purity contract is quoted verbatim in the suite header; the git gate exits 0 at phase close.
- **D-08c live smoke:** `cold_prune_live_smoke_test` — env-gated on `SGNS_BLOCKSTORE_TEST_MINIO_BIN`, self-contained MinIO child-process spawn + TCP health probe + PRODUCTION S3 client injection (the real wire) + A7-ruling fake admin; bucket precondition probed by a tiny Put with the exact `mc mb` runbook in the failure text. Registered LABELS "Tier3" (never Tier-1 — Pitfall 6 parity held, `tier1_static_audit` green).
- **D-09 sealed:** Tier-1 lane 14/14 green including both new deterministic suites; ten-suite regression net 10/10 green.

## Task Commits

1. **Tasks 1+2: matrix + edges + Unreadable legs + composition crossing legs** - `35f7188a2` (test, SuperGenius)
2. **Task 3: live smoke + Tier-1 contract evidence** - `095c8c502` (test, SuperGenius)

**Plan metadata:** root pointer bump + this summary (docs(14-03), GeniusNetwork)

## SC Evidence Checklist (the phase's close-out)

| SC | Requirement | Evidence | Proving invocation |
|----|-------------|----------|--------------------|
| SC1 (5-state fail-closed matrix + counters + WARN + edges) | PRUNE-01 | LEG 1 (Durable→erase), LEG 2 + SeedVariants/NoRecord,Acepted,Garbage×2 (defer-as-counter, re-evaluated, never permanent-stop), Gate_Unreadable (dedicated counter + 1 WARN + cycle completes), UnreadableBridge (real fault→bridge), Ordering, Empty | `ctest -C Release -R cold_prune_gate_test` — 13/13 green |
| SC2 (TOCTOU: commit-time evidence re-check, red-first) | PRUNE-02 | 14-02's red evidence (erased=1, value destroyed, marker staged — guard-less) → green (refused, value survives, counter grows, errors==0) on both DurableToAccepted/DurableToNoRecord | `ctest -C Release -R cold_prune_toctou_test` — 2/2 green |
| SC3 (composition AND, no widening, evaluator pure) | PRUNE-03 | Crossing legs: erasable×Durable→erased (LEG 1), erasable×Pending→deferred (LEG 2), NON-erasable×Durable→no erase + zero counter motion, no-cold×erasable→erased (LEG 3); AND-conjunction reads both verdicts directly; `git diff --exit-code 2af184fa1` on PruneEligibility.{hpp,cpp} exits 0 | `ctest -R cold_prune_gate_test` + the purity git gate (exit 0) |
| SC4 (vacuous branch; Light-only activation untouched) | PRUNE-01/03 | LEG 3 (cold-disabled erases byte-identically, both counters zero, HasColdStorage()==false); `NodeType::Light` factory check untouched (diff shows no TxPruner::New change); no new config knob | `ctest -R cold_prune_gate_test` (Gate_ColdDisabledNodeVacuousBranch) |

## D-08c Posture Record (live smoke)

- **Loud-skip PROVEN by run** (env unset): `[  SKIPPED ] ColdPruneLiveSmokeTest.LiveStack_RealDrainerTransitionsPassTheGate` with the labelled message `[SGNS_COLD_PRUNE][LIVE-SMOKE] MinIO binary not provided (set SGNS_BLOCKSTORE_TEST_MINIO_BIN; COMMUNITY build — never the license-gated minio.exe; runbook: thirdparty/sgns-blockstore/docs/testing-tiers.md). Deterministic stand-in: cold_prune_gate_test LEG 1 (Tier-1, real drainer transitions over injected clients).` — never a silent pass.
- **Live execution: runbook-deferred** — no MinIO community binary in this environment (`minio` not on PATH, env gate unset), exactly the v1.1 TEST-03 precedent. The deterministic stand-in (LEG 1: real drainer + real AdvanceDurabilityOnce over injected clients) is Tier-1 green. When a developer sets the gate + creates the bucket (`mc mb` per the runbook in the file header), the live leg runs the production S3 client against the real wire and asserts erased≥1 with zero counters and the marker present.

## Self-Check: PASSED

- Builds exit 0 (suite + smoke)
- `ctest -R cold_prune_gate_test`: 13/13 legs green (15.08s in the Tier-1 lane run)
- `ctest -L Tier1`: 14/14 green incl. both new suites + tier1_static_audit
- Ten-suite regression net: 10/10 green (prune_eligibility, tx_pruner, node_startup, crdt_test[crdt_erase], globaldb_integration_test[globaldb_erase], cold_storage_fallback, cold_storage_durability, cold_storage_gc, cold_storage_gc_retrievability, cold_storage_resurrection)
- Purity gate at phase close: exit 0; no thirdparty/sgns-blockstore modifications; seeding only against the published CF while closed; no push (local on dev_coldstorage_additions per v1.1 D-03)

## Deviations from Plan

**[Rule 1 - Bug] Held-journal legs needed faulted fakes, not a bare production endpoint** — Found during: Task 1 | Issue: the plan's PHASE C "reopen with nothing advancing" is defeated by the drainer's IMMEDIATE first pass (D-12 crash-restart reconciliation): healthy hermetic fakes advance every Pending→Accepted in milliseconds, and constructing the production client against "hermetic.invalid" crashes in-process (SEH 0xc0000005) | Fix: inject the SAME hermetic fakes FAULTED (S3 Put→Unavailable, admin→Unreachable) — drain and flush both fail, seeded bytes hold deterministically; documented as the fixture's determinism contract | Files: cold_prune_gate_test.cpp | Verification: all seeded legs green incl. the reopened-state asserts | Commit: 35f7188a2

**[Rule 1 - Bug] In-window crossing shape corrected** — Found during: Task 2 | Issue: the "no drivers after the spend" shape left the candidate ELIGIBLE — the window keys on the spender's CRDT height (maxHeight − spend_height ≥ N), and the ancient spender satisfied it | Fix: seed the spender RECENTLY (after the height-raising drivers), the inverse of RealPrune's recipe — spend_height == maxHeight, window unsatisfied | Files: cold_prune_gate_test.cpp | Verification: direct-Evaluate block asserts ineligible + zero block reports; crossing leg green | Commit: 35f7188a2

**Total deviations:** 2 auto-fixed (test-shape bugs). **Impact:** none on production code — both are fixture-determinism fixes inside the test binary.

## Issues Encountered

None blocking. Environment note: no MinIO community binary available — D-08c live leg runbook-deferred (recorded above; the plan's sanctioned posture).

## Next Phase Readiness

Phase 14 is complete — all three plans summarized, Tier-1 contract sealed, zero regressions. Phase 15 (evidence-aware serving + the walk fix) builds directly on the proven gate: prune markers now decide serve-vs-refuse with the admission semantics fully evidenced.
