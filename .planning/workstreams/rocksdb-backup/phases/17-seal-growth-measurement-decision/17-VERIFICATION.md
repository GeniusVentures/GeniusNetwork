---
phase: 17-seal-growth-measurement-decision
verified: 2026-11-24T21:05:00Z
status: passed
score: 8/8 must-haves verified
covered_files:
  - .planning/workstreams/rocksdb-backup/STATE.md
  - .planning/workstreams/rocksdb-backup/notes/17-seal-growth-decision.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-01-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-01-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-02-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-02-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-03-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-03-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-UAT.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/README.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/run-capture.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/seal_growth_evidence.json
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/seal_growth_table.md
  - SuperGenius/src/crdt/graphsync_dagsyncer.hpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - SuperGenius/test/src/crdt/cold_seal_growth_test.cpp
covered_digest: "v2:sha256:bc8058d3a14bcc3db5e9d13c251d3ce016f2bdf3ad0e64b593912cf34e2f0820"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 7/8
  gaps_closed:
    - "Workload-spectrum representativeness ratified (UAT item 1: pass)"
    - "D-12 verdict ratified — VALIDATED, in-band-with-noted-limitation, no production touch (UAT item 2: pass)"
    - "Four judgment-tier prohibitions ratified on the collected deterministic evidence (UAT item 3: pass)"
    - "Floor seeding-rate window semantics confirmed acceptable — status line in-loop vs JSON total-elapsed, both generation-inclusive; decision record cites the JSON value (UAT item 4: pass)"
  gaps_remaining: []
  regressions: []
---

# Phase 17: Seal Growth Measurement & Decision Verification Report

**Phase Goal (ROADMAP):** Seal growth at representative workloads is measured and an explicit accept-hot-growth-vs-future-design decision is recorded with capacity math — measure-and-decide only; no seal spill/redesign this milestone.
**Verified:** 2026-11-24T21:05:00Z
**Status:** passed
**Re-verification:** Yes — the prior 2026-11-19 report went stale (covered source files changed after it ran: phases 18/19 legitimately touched overlapping files); regenerated with a fresh digest against the current codebase after all four human items completed via 17-UAT.md (4/4 pass, 0 issues, commit `daece3a`, 2026-11-24).

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence (current codebase) |
|---|-------|--------|------------------------------|
| 1 | Measurement instrument exists and is green in the fail-closed lane (`cold_seal_growth_test` registered under `SGNS_COLD_STORAGE` with `LABELS "Tier1"`) | ✓ VERIFIED | `SuperGenius/test/src/crdt/CMakeLists.txt:772-814` — registration block (moved down from 604-637 by phase-18/19 suite additions above it; content unchanged) sits inside `if(SGNS_COLD_STORAGE)`, `set_tests_properties(cold_seal_growth_test PROPERTIES LABELS "Tier1")` at line 814 before `endif()`. **Behavioral run this pass (2026-11-24): `ctest -R "^cold_seal_growth_test$"` → `Test #120: cold_seal_growth_test — Passed, 8.09 sec`** (label summary Tier1; index shift #116→#120 is the 18/19 suite additions). Corroborated by the 18/18 Tier-1 local run (8.65s) and phase-19 CI capstone Tier-1 20/20 on three platforms |
| 2 | Evidence trio complete and parseable; extrapolation flagged | ✓ VERIFIED | Re-parsed this pass: `ConvertFrom-Json` OK; `leg` keys exactly `volume_10e6_floor, volume_10e6, volume_10e7, volume_10e8_extrapolated, fidelity, density`; `per_row_bytes = 52.0` at BOTH 10^6 and 10^7; `volume_10e8_extrapolated.total_bytes = 5200000000.0`, `extrapolated = True` (sole flagged block); table renders the 10^8 row as **EXTRAPOLATED** |
| 3 | Decision record with band-before-verdict chronology, explicit verdict, observability posture, D-11 numeric triggers citing JSON keys, options table, four-source citations, no forbidden phrase | ✓ VERIFIED | `notes/17-seal-growth-decision.md` — §(c) band (line 12, "recorded BEFORE the verdict — Pitfall 6"); **`Verdict: VALIDATED — in-band, with noted limitation. No production touch.`** (line 34); symmetric reduced-observability clause in §(c) applied in §(d); noted-limitation paragraph distinguishes non-interference from tightness (line 53); verdict date + commit chronology `de04874` → `20656e9`, no amendment follows (line 57); capacity table (lines 79-83: 52.0 MB / 520 MB / 5.2 GB, ≈16.0 s EXTRAPOLATED); T1-T3 trigger table each citing JSON keys (lines 93-95); options table rejects spill as deferred-to-triggers (lines 99-102); Sources are exactly the four ruled citations |
| 4 | Production-touch containment and no post-decision seal redesign | ✓ VERIFIED | `kForcedWalkPeerFailoverPerCid{ 8 }` unchanged (`graphsync_dagsyncer.hpp:83`; the 82→83 shift is phase-19's `#include <functional>` for its production-null test seam — constant and derivation comment untouched). `git -C SuperGenius diff 741980f5d -- src` is now non-empty (phases 15/16/18/19 legitimately landed: ColdStorageManager/Stack/Stub, PruneEligibility, GeniusNode, serve interrupt seams — 17 files, +712) but contains **zero seal spill/compaction/sidecar machinery**: the only `[+-]` lines matching `seal` are phase-15/16 erase-semantics comments ("the seal is retained by design" — the accepted-growth posture working as designed). Phase-17's own scoped containment (in-band verdict → zero phase-17 src edit) is unchanged in history |
| 5 | STATE.md carries exactly one key-decisions bullet naming the decision doc and evidence path | ✓ VERIFIED | `STATE.md:57` — single SEAL-01 bullet: accept ruling, 52.000 B/row at 10^6/10^7, 10^8 extrapolated 5.2 GB / ~16 s, evidence path, D-11 deferral, D-12 verdict (in-band-with-noted-limitation, zero production touch) |
| 6 | SEAL-01 success criteria accounted for by visible artifacts | ✓ VERIFIED | SC1 → evidence trio + instrument (truths 1-2); SC2 → D-12 band §(c) + verdict §(d) closing the Phase-15 derive-now/refine-later dependency (in-band → no re-tune required); SC3 → §(a)/(b) ACCEPT ruling with D-13 capacity math + D-11 triggers deferring redesign. ROADMAP SCs 1-3 each map |
| 7 | Citation integrity — decision-record numbers match the committed JSON | ✓ VERIFIED | Re-cross-checked exact this pass: `per_row_bytes` 52.0 ↔ doc "52.000 at every scale point"; `enum_warm.rows_per_s = 6250308.401` ↔ doc T2 input "6,250,308"; `total_bytes = 5.2e9` ↔ "5.2 GB"; extrapolation arithmetic holds (52 B × 10^8 = 5.2 GB; 10^8 / 6,250,308 ≈ 16.0 s) |
| 8 | Human judgment items (representativeness, D-12 ratification, prohibition ratification, floor-window semantics) | ✓ VERIFIED — RESOLVED via UAT | `17-UAT.md` frontmatter `status: complete`, Summary `total: 4 / passed: 4 / issues: 0 / pending: 0`; commit `daece3a` "test(17): complete UAT - 4 passed, 0 issues" (2026-11-24). Each of the four prior human items has a matching UAT test with recorded `result: pass` and expected-outcome language mirroring the verifier's request |

**Score:** 8/8 truths verified (0 present-but-behavior-unverified — the one behavioral truth, Tier-1 lane greenness, was exercised by an actual test run this pass)

### Downstream Consumption (goal-backward check: the decision held)

| Consumer | Expected | Status | Evidence |
|----------|----------|--------|----------|
| Phase 15 walk bounds | Probe numbers validate (or re-tune) the walk-bound defaults | ✓ HELD | D-12 verdict VALIDATED in-band → `kForcedWalkPeerFailoverPerCid = 8` stands, no re-tune; verdict records the closure of the derive-now/refine-later dependency (decision doc line 57: no constant amendment follows) |
| Phase 18 policy record | Cites the D-11 triggers as the seal-side "demands it" gate and the D-12 verdict | ✓ HELD | `notes/18-collectibility-policy-downgrade-interlock.md` cites D-11/D-12; phase-18 PLANs, CONTEXT, and 18-VERIFICATION.md all reference `17-seal-growth-decision` / D-11 / D-12 |
| Phase 19 capstone | Built on the accepted-growth posture; Tier-1 lane (including this probe) green on three platforms | ✓ HELD | Phase-19 serve-seam work touched `graphsync_dagsyncer.hpp` without altering the bound; probe green in the 20/20 three-platform Tier-1 capstone |
| No redesign trigger fired | T1/T2/T3 all far from tripping | ✓ HELD | T1: 52.0 ∈ [46, 60]; T2: 10^7 full-sweep ≈1.6 s « 10 s; T3: 5.2×10^9 « 20 GB. No post-decision seal spill/compaction/sidecar code exists in the src delta (truth 4) |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp` | Env-knobbed probe harness | ✓ VERIFIED | 74,872 bytes; **last touched by phase 17's own commit `84d87d462` (2026-11-19) — untouched by 18/19**; zero TBD/FIXME/XXX; zero Delete/CompactRange/DeleteRange calls (read/count/time-only posture holds); `"sealed"` literal appears exactly 3 times — one doc comment + the two enumeration suffix comparisons (lines 449/541), never appended to build a key |
| `SuperGenius/test/src/crdt/CMakeLists.txt` | Registration inside `if(SGNS_COLD_STORAGE)`, LABELS Tier1 | ✓ VERIFIED | Lines 772-814; block relocated but intact (truth 1) |
| `17-seal-growth-evidence/seal_growth_evidence.json` | Machine-readable source of record | ✓ VERIFIED | Parses; all leg keys; 10^8 flagged `extrapolated: true` (truth 2) |
| `17-seal-growth-evidence/seal_growth_table.md` | Rendered table, 10^8 labeled EXTRAPOLATED | ✓ VERIFIED | Present, substantive |
| `17-seal-growth-evidence/README.md` | D-08 runbook | ✓ VERIFIED | Present, substantive |
| `17-seal-growth-evidence/run-capture.md` | Canonical run transcript | ✓ VERIFIED | Present, substantive |
| `notes/17-seal-growth-decision.md` | D-10 decision record | ✓ VERIFIED | Truth 3 |
| `STATE.md` | One key-decisions bullet | ✓ VERIFIED | Truth 5 |
| `17-UAT.md` | Human-item closure record | ✓ VERIFIED | complete, 4/4, 0 issues, commit `daece3a` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| Suite registration | ctest Tier-1 lane | `set_tests_properties LABELS Tier1` | ✓ WIRED | Test #120 listed and PASSED this pass |
| Evidence JSON | decision doc + D-11 triggers | dotted-key citations | ✓ WIRED | All cited values re-matched exact (truth 7) |
| Decision doc | Phase 18 policy record / Phase 19 capstone / future redesign gate | forward pointers + citations | ✓ WIRED | Downstream Consumption table |
| Committed JSON → band → verdict → (conditional) amendment | SC2 chain | commit order | ✓ WIRED | `de04874` → `20656e9`; in-band branch → no amendment; constant still 8 at HEAD |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `seal_growth_evidence.json` | `leg.*` | instrumented test run (canonical run 2026-11-19, host MOFU) | Yes — run-capture corroborates | ✓ FLOWING |
| decision doc §(b)/(c)/(d), T1-T3 | thresholds & measured values | committed JSON keys | Yes — re-cross-checked exact | ✓ FLOWING |
| STATE.md bullet | outcome summary | decision doc + JSON | Yes — values consistent | ✓ FLOWING |

The 10^8 row remains the one non-measured value, flagged `extrapolated: true` at every rendering — correct posture, not a stub.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `cold_seal_growth_test` green in the fail-closed Tier-1 lane (floors + fidelity + density ungated; big legs skip loudly) | `ctest --test-dir SuperGenius/build/Windows/Release -C Release -R "^cold_seal_growth_test$"` | `1/1 Test #120: cold_seal_growth_test — Passed, 8.09 sec` (Tier1 label summary) | ✓ PASS |

Corroborating regression context (recorded, not re-run): 18/18 Tier-1 local run 2026-11-24 (this test 8.65s) and phase-19 CI capstone Tier-1 20/20 across Windows/macOS/Linux.

### Probe Execution

No `probe-*.sh` scripts; this phase's probe is the ctest-registered instrument above — executed this pass, PASS.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SEAL-01 | 17-01, 17-02, 17-03 (each `requirements: [SEAL-01]` — no sibling IDs) | Seal growth measured at representative workloads and the explicit accept-vs-future-design decision documented with capacity math | ✓ SATISFIED | Truths 1-8; measurement coverage (trio + instrument), walk-bounds validation (D-12 verdict), decision record (notes/17-seal-growth-decision.md with D-11 deferral) |

Orphaned requirements: none — REQUIREMENTS.md maps only SEAL-01 to Phase 17 and all three plans claim it. The traceability row (line 96) and checkbox (line 53) still read "Pending"/unchecked — orchestrator-owned post-verification update, out of this verifier's scope per instruction (STATE.md/ROADMAP.md untouched).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `cold_seal_growth_test.cpp` | — | Debt markers / deletion / compaction calls | none found (re-scanned this pass) | Read/count/time-only posture holds |
| `cold_seal_growth_test.cpp` | 449, 541 | `"sealed"` literal | ℹ️ Info | Enumeration suffix comparison only — GATE-03 discipline holds |
| `cold_seal_growth_test.cpp` | — | MAJ-01/MAJ-02 advisories (iterator status hardening; big-leg re-run guidance) | ⚠️ Warning (advisory, open in 17-REVIEW-DISPOSITION) | Instrument hardening; does not invalidate committed evidence — exact-count assertion fires on any truncating scan; README documents re-run guidance |
| `graphsync_dagsyncer.hpp` | 296+ | Phase-19 test-only interrupt seam (kInterrupt* + SetColdServeInterruptForTest) | ℹ️ Info | Production-null downstream addition; does not touch the walk bound or seals |

Judgment-tier prohibitions: the four were ratified by the human in UAT item 3 (pass) on the deterministic evidence — P1 zero delete/compact (re-confirmed this pass), P2 vendored-tree/zero-spill-machinery (re-confirmed via src-delta grep), P3 in-band verdict → no edit (constant still 8), P4 extrapolation flagged everywhere + numbers JSON-matched. ADR-550 resolution recorded in 17-UAT.md.

### Human Verification Required

None — all four prior human items resolved via 17-UAT.md (complete, 4/4 pass, 0 issues, commit `daece3a`). The human verification section is empty; `passed` is therefore valid.

### Gaps Summary

No gaps. Re-verification against the current codebase confirms every must-have: the instrument remains registered and behaviorally green (fresh PASS, 8.09s), the evidence trio still parses with the extrapolation correctly flagged, every decision-doc number still cross-checks exact against the committed JSON, the verdict-gated constant still reads 8, and the STATE.md key-decisions bullet is intact. The staleness cause is fully accounted for: phases 18/19 moved the CMake registration block (content unchanged), added a production-null test seam to the walk header (bound untouched), and left the harness itself unmodified since phase 17's own commit. Downstream consumption held — Phase 15's walk bounds stand validated, Phase 18's policy record cites D-11/D-12, and no seal-redesign code exists because no D-11 trigger fires (52.0 B/row ∈ [46,60]; ~1.6 s « 10 s; 5.2 GB « 20 GB). The four reserved human judgments were ratified 4/4 in 17-UAT.md. Goal achieved: measured, decided (accept hot growth at 52.000 B/row), triggers recorded, zero production touch.

---

_Verified: 2026-11-24T21:05:00Z_
_Verifier: the agent (gsd-verifier)_
