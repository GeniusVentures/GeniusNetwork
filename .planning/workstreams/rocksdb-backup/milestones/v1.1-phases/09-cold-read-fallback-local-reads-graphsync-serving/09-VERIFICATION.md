---
phase: 09-cold-read-fallback-local-reads-graphsync-serving
verified: 2026-10-27
verifier: inline (Copilot runtime)
goal: >-
  Cold data is readable — hot-store misses resolve through Local→S3 with CID-verify and
  re-cache for both local reads and graphsync serving, the miss-taxonomy is honest
  (transport failure is never authoritative absence), and the responder is never blocked inline
requirements: [READ-01, READ-02]
status: passed
score: 5/5 must-haves verified
human_verification: []
---

# Phase 9 Verification

Method: goal-backward verification — each success criterion checked against the landed code and the green Tier-1 lane (HEAD `SuperGenius@b17643b5a`, build `build/Windows/Debug`, SGNS_COLD_STORAGE=ON), cross-referenced with plan SUMMARYs and REQUIREMENTS.md.

## Success Criteria

### SC1 — Local read chain with honest taxonomy ✅
- **Chain:** `ColdReadService::Get` implements Local→S3 (D-01/D-02), both tiers CID-verified by the library (never bypassed), re-cache via the decorator `set()` before return (D-04); wired into `GetNodeWithoutRequest` and `getNode` (pre-peer, outside `dagMutex_`).
- **No-NotFound-escape:** `SC1_NoNotFoundEscape_S3Unavailable` proves a scripted s3d Unavailable classifies `TemporarilyUnavailable` at BOTH the `ColdReadStatus` and `MapColdReadStatus` layers — never `CID_NOT_FOUND`. `D03_DefinitiveAbsenceIsTheOnlyNotFound` proves absence-everywhere is the only NotFound.
- **Evidence:** `cold_storage_fallback_test` green (21 cases).

### SC2 — Async cold-serve, bounded executor, never-blocked responder ✅
- **Executor:** single dedicated worker (never io_/pubsub context), queue bound 64 with non-blocking overflow, per-CID coalescing (`D07_RewarmCoalescesDuplicateEnqueues` — exactly one fetch under duplicates), 4 s budget (≪ 20 s requester budget / 180 s stream ladder), 5 s shutdown grace.
- **Responder:** `ColdServeDagService` delegates and enqueues only — waits on nothing (source-inspected + `SC2_HotServeUnderSaturatedSlowQueue` < 50 ms with 16 queued 500 ms misses; `SC2_HotServeUnderOutageFailFastQueueChurning` < 50 ms under a faulted, churning outage; `SC2_TimeToWarmWithinBudgetAt500MsLatency` < 4 s).
- **Lifecycle:** Stop slots into `ShutdownNow` after the drainer, before lifecycle-mutex teardown (Phase-8 D-10/D-11 ordering).

### SC3 — Honest BlockStatus mapping at the seam ✅
- **No peer blame:** `SC3_NoPeerBlameMappingSafetyNet` (no cold input maps to `PEER_BLACKLISTED`/`TIMED_OUT`) + scoped structural audit: zero `RecordCIDFailure`/`BlackListPeer` references in the cold-read sources.
- **Corrupt attribution:** `SC3_CorruptAttributesRemoteTier` (byte-flip) and `SC3_CorruptAttributesLocalTier` (FaultController) + `SC3_LocalCorruptServesGoodS3Copy`; `SC3_UnauthorizedSurfacesOwnClass`; exhaustive 4×2 mapping table.
- **HasBlock cold-aware:** gated local-only cold-dir check (D-08/D-09) — the "retrievable before deadline" half is honored by the fetch paths per the D-08 ruling (CONTEXT locked decision; a remote lookup from HasBlock would re-open the freeze hazard).

### SC4 — Dedicated rehydrate path, silent ✅
- **Bytes only:** `SC4_RehydrateSilence_BytesOnlyNoMarkers` (exactly one `set`, zero marker writes) and `SC4_PreSealedBlockGainsNoMarker`; zero pubsub/`AddRoute`/heads by construction (09-RESEARCH §2.3 call-site audit).
- **Scope ruling (documented, not a gap):** SC4's "resolved marker" half is explicitly a Phase-11 GC-02 eviction-unit obligation — sealing an unprocessed crash-window block would make its delta permanently unmergeable (§2.4 ruling; CONTEXT OQ1 resolution; carried in 09-02's success criteria).

### SC5 — Hermetic Tier-1 lane ✅
- `ctest -L Tier1 --no-tests=error`: 5/5 green (config-gate, link-proof, spill, fallback, freeze). Registration/label parity 5==5. No Docker, no live endpoints; fake S3 + FaultController/latency injection throughout.

## Requirements Traceability

| Requirement | Plans | Status |
|-------------|-------|--------|
| READ-01 | 09-01 (chain + taxonomy) + 09-03 (fault-injected proof) | Complete — checkbox + traceability rows updated |
| READ-02 | 09-02 (executor + wrapper + SC2 measurements) + 09-03 (freeze regression) | Complete |

## Environment caveats

- Windows local evidence; Linux/macOS lanes run via CI on push (same posture as Phases 7/8 — the ON-lane CI step is committed; runtime evidence accrues on push).
- The OFF (default) build compiles the stub twin and the ungated surfaces; its byte-identical bar is enforced by the null-hook structure (`D06_NullHookNoOpReturnsHotErrorUnchanged`) and the config-gate test in the lane.

## Verdict

**PASSED — 5/5 success criteria verified; READ-01/READ-02 complete; no human-verification items.**
