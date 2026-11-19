---
phase: 17-seal-growth-measurement-decision
verified: 2026-11-19T05:36:06Z
status: human_needed
score: 7/8 must-haves verified
covered_files:
  - .planning/workstreams/rocksdb-backup/STATE.md
  - .planning/workstreams/rocksdb-backup/notes/17-seal-growth-decision.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-01-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-01-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-02-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-02-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-03-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-03-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-REVIEW-DISPOSITION.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-REVIEW.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/README.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/run-capture.md
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/seal_growth_evidence.json
  - .planning/workstreams/rocksdb-backup/phases/17-seal-growth-measurement-decision/17-seal-growth-evidence/seal_growth_table.md
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - SuperGenius/test/src/crdt/cold_seal_growth_test.cpp
covered_digest: "v2:sha256:4523f1b1fdfef46c6cc865675c47a0beb0074f38db487d61bb99908fb320dae6"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Judge the workload spectrum as representative (or not) for SEAL-01's 'representative workloads' clause"
    expected: "Human confirms deep (64-node chain), wide (73 = 1+8+64, fan-out 8), mixed (41 = 32-chain + 8-fan) DAG shapes at 1/4/1/2/1 erase fractions, plus 10^6/10^7 scale points, are a defensible workload spectrum for the capacity math"
    why_human: "Representativeness is a domain judgment about real recovery-walk traffic; 17-02's flagged_assumption explicitly reserves it for human review ('never auto-resolved')"
  - test: "Ratify the D-12 verdict (VALIDATED — in-band, with noted limitation, no production touch)"
    expected: "Human accepts that SC2's 'validated (or re-tuned)' is honored by a non-interference validation under the hermetic datastore-level topology (walk_gaps=0, zero errors), with bound tightness explicitly deferred as a noted limitation per the plan's symmetric observability clause"
    why_human: "17-03's flagged_assumption reserves verdict confirmation for the human reviewer; the plan contract mechanically produced this outcome, but acceptance of the limitation posture is a judgment"
  - test: "Ratify the four judgment-tier prohibitions (read-only posture, no vendored edits, verdict-before-edit, no evidence misrepresentation)"
    expected: "Human signs off on the prohibition block; verifier collected deterministic evidence for each (see Anti-Patterns Found) but judgment-tier prohibitions are never auto-resolved per ADR-550"
    why_human: "Prohibition tiers marked verification: judgment in PLAN frontmatter require explicit human resolution"
  - test: "Spot-check the floor-leg seeding-rate presentation windows"
    expected: "Human confirms which measurement window each of the two floor seeding rates covers: run-capture status line '158706 seals/sec (6301.0 ms)' vs JSON leg.volume_10e6_floor.seeding_rate_per_sec = 143312.987 (seed_elapsed_ms 6977.735), both labeled generation-inclusive"
    why_human: "The ~10% window difference between transcript and JSON is not derivable from committed artifacts; it does not affect the decision (both ~1.4-1.6x10^5 seals/s; the decision doc cites the JSON value)"
---

# Phase 17: Seal Growth Measurement & Decision Verification Report

**Phase Goal (ROADMAP):** Seal growth at representative workloads is measured and an explicit accept-hot-growth-vs-future-design decision is recorded with capacity math — measure-and-decide only; no seal spill/redesign this milestone.
**Verified:** 2026-11-19T05:36:06Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Measurement instrument exists and is green in the fail-closed lane (`cold_seal_growth_test` registered in `if(SGNS_COLD_STORAGE)` with `LABELS "Tier1"`, listed by `ctest -L Tier1 -N`) | ✓ VERIFIED | `SuperGenius/test/src/crdt/CMakeLists.txt:604-637` — `addtest(cold_seal_growth_test ...)` inside `if(SGNS_COLD_STORAGE)`, `set_tests_properties(... LABELS "Tier1")` at line 635 before `endif()`; `ctest -L Tier1 -N` lists `Test #116: cold_seal_growth_test` (17 total); **behavioral run: `ctest -R "^cold_seal_growth_test$"` → Passed, 7.96 s**; derived floors asserted in source: `EXPECT_GE(rows_per_sec, 480000.0)` (line 816), bytes band `EXPECT_GE(per_row_bytes, 46.0)` / `EXPECT_LE(per_row_bytes, 60.0)` (lines 820-821) |
| 2 | Evidence trio complete and parseable (JSON parses; carries `leg.volume_10e6_floor` / `leg.volume_10e6` / `leg.volume_10e7` with `enum_warm`+`enum_cold`+`enum_reopen_cold` / `leg.fidelity` / `leg.density` / `options`; 10^8 block carries `"extrapolated": true`) | ✓ VERIFIED | All four files present in `17-seal-growth-evidence/` (JSON 5.3 KB, table 3.4 KB, README 3.0 KB, run-capture 3.9 KB — all substantive); `ConvertFrom-Json` parse OK; top-level `meta, options, leg`; `leg` keys exactly `volume_10e6_floor, volume_10e6, volume_10e7, volume_10e8_extrapolated, fidelity, density`; `volume_10e7` carries `enum_warm, enum_cold, enum_reopen_cold` (+5 more); `volume_10e8_extrapolated.extrapolated = True` (sole `"extrapolated": true` occurrence); table renders 10^8 row as **EXTRAPOLATED** |
| 3 | Decision record exists with band-before-verdict chronology, explicit Verdict line, observability posture, D-11 numeric triggers citing JSON keys, options-considered table, four-source citation list, and NO "v1.1 recovery-suite" phrase | ✓ VERIFIED | `notes/17-seal-growth-decision.md` (72 lines added in `3b7739f`); `git log --follow` order (oldest→newest): `de04874` (band) → `20656e9` (verdict) → `3b7739f` (completion) — matches required chronology; `**Verdict: VALIDATED — in-band, with noted limitation. No production touch.**`; symmetric reduced-observability clause present in §(c) and applied in §(d); D-11 table T1-T3 each citing JSON keys; options table (accept/spill/compaction/sidecar); Sources 1-4 exactly the four ruled citations; `Select-String "v1.1 recovery-suite"` count = 0 |
| 4 | Production-touch containment: `git -C SuperGenius diff --name-only 741980f5d -- src` empty; `kForcedWalkPeerFailoverPerCid` still 8 | ✓ VERIFIED | Diff vs anchor `741980f5d` scoped to `src` → **EMPTY**; `graphsync_dagsyncer.hpp:82: static constexpr uint32_t kForcedWalkPeerFailoverPerCid{ 8 };`; vendored `thirdparty/ipfs-lite-cpp` git status CLEAN; the en-route fix `f758356fe` (Phase-16 compose flake) touched only `test/src/crdt/cold_compose_matrix_test.cpp` — test-side, outside `src` |
| 5 | STATE.md carries exactly one key-decisions bullet naming `notes/17-seal-growth-decision.md` and the evidence path | ✓ VERIFIED | `STATE.md:56` — single SEAL-01 bullet (accept ruling, 52.000 B/row, 10^8 extrapolation, evidence path, D-11 deferral, D-12 verdict); diff of `3b7739f` shows exactly one `+` line in the key-decisions list. NOTE (informational): the same commit's STATE.md diff also moves `## Current Position` cursor fields — those lines change together with frontmatter `stopped_at`/`state_head` and Session Continuity, the `state.record-session` tool signature (orchestrator-owned mechanism), not a plan-task hand-edit; the cursor value at HEAD reads "EXECUTING / Plan: 1 of 3" (stale vs 3/3 done) — orchestrator to normalize post-verification |
| 6 | SEAL-01 success criteria accounted for by visible artifacts (measurement coverage, walk-bounds validation, decision record) | ✓ VERIFIED | SC1 → evidence trio + JSON legs (volume/fidelity/density, 10^6/10^7 measured, 10^8 flagged); SC2 → D-12 band §(c) + verdict §(d) closing the Phase 15 derive-now/refine-later dependency (in-band → no re-tune required, per the plan's pre-defined outcome shape); SC3 → §(a)/(b) ACCEPT ruling with D-13 spectrum-band capacity math + D-11 triggers deferring redesign. ROADMAP SCs 1-3 each map to these artifacts |
| 7 | Citation integrity — decision-record numbers match the committed JSON | ✓ VERIFIED | Programmatic cross-check, all exact: band inputs `5.239` / `4.743`+`3.354` / `22.792`+`16.152`; T2 input `6250308.401` (doc: 6,250,308); `identity_equal=True`, `seal_keys_compared=242`, `walk.state=Completed`, `walk_gaps=0`; `derived_tier1_bytes_band = [46, 60]`; 10^8 `total_bytes=5.2e9`, `spot_check_deviation_pct=-9.062`; table↔JSON spot-match `6,797,531` = `warm_rows_per_sec_mean 6797530.976`; extrapolation arithmetic verified (52 B x 10^8 = 5.2 GB; 10^8 / 6,250,308 = 16.0 s; 10^8 / 130,306 = 767 s) |
| 8 | The workload spectrum counts as representative and the recorded verdict/trigger posture is accepted | ? HUMAN | Reserved judgment — 17-02/17-03 `flagged_assumptions` explicitly defer this to human review ("never auto-resolved"); see Human Verification Required |

**Score:** 7/8 truths verified (0 present-but-behavior-unverified — the one behavioral truth, Tier-1 lane greenness, was exercised by an actual test run)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp` | Env-knobbed probe harness (volume + fidelity + density + big legs, floors, JSON emitter) | ✓ VERIFIED | 74,872 bytes; floors at lines 816/820-821; big-leg gate `SGNS_SEAL_BIG_ENABLE` + loud `GTEST_SKIP` naming it (lines 1329-1331); knob surface matches plan (SCALE/REPEATS/SEED/DEPTH/FANOUT/MIX/BIG_SCALE) |
| `SuperGenius/test/src/crdt/CMakeLists.txt` | Registration inside `if(SGNS_COLD_STORAGE)`, LABELS Tier1 | ✓ VERIFIED | Lines 604-637; idiom-parity with sibling cold suites |
| `17-seal-growth-evidence/seal_growth_evidence.json` | Machine-readable source of record | ✓ VERIFIED | Parses; all required leg keys; meta fingerprint (host/os/build_config/generated_utc/dataset fingerprints) |
| `17-seal-growth-evidence/seal_growth_table.md` | Rendered human table, 10^8 labeled EXTRAPOLATED | ✓ VERIFIED | Volume/enumeration + fidelity + density sections; EXTRAPOLATED labeling present |
| `17-seal-growth-evidence/README.md` | Runbook (binary, build, cwd, env NAMES-only, reproduce) | ✓ VERIFIED | D-08 shape complete incl. redaction procedure |
| `17-seal-growth-evidence/run-capture.md` | Canonical run transcript | ✓ VERIFIED | Status lines + `[evidence-json]` blobs per leg |
| `notes/17-seal-growth-decision.md` | D-10 decision record | ✓ VERIFIED | Full shape per truth 3 |
| `STATE.md` | One key-decisions bullet | ✓ VERIFIED | Truth 5 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| Seeding loop | vendored `RocksdbDatastore::seal` → hot RocksDB default CF | the one sanctioned construction path | ✓ WIRED | Harness constructs via `IpfsRocksDb::create(getDB())` + vendored datastore (17-01 SUMMARY; GATE-03: `"sealed"` literal appears in source exactly twice, both inside the enumeration suffix `k.compare(k.size()-6, 6, "sealed")` — never appended to build a key) |
| Enumeration loop | `storage::rocksdb getDB()` → raw `NewIterator` streaming count | suffix comparison | ✓ WIRED | Lines 449/541; wrapper `query(prefix)` unused |
| Suite registration | `ctest -L Tier1` lane | `set_tests_properties LABELS Tier1` | ✓ WIRED | Test #116 listed; run PASSED |
| Evidence JSON | 17-03 decision doc + D-11 triggers | dotted-key citations | ✓ WIRED | 23 JSON-key citations in doc; all spot-checked values match (truth 7) |
| Committed JSON → band → verdict → (conditional) amendment | SC2 chain | commit order | ✓ WIRED | `de04874` → `20656e9`; in-band branch → no amendment; `src` diff empty |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `seal_growth_evidence.json` | `leg.*` numbers | instrumented test run (canonical run 2026-11-19T04:57-04:58Z, host MOFU) | Yes — run-capture.md transcript corroborates, per-pass rows/sec printed | ✓ FLOWING |
| `seal_growth_table.md` | rendered rows | the JSON (stated source of record) | Yes — spot-match verified | ✓ FLOWING |
| decision doc §(b)/(c)/(d), D-11 T1-T3 | thresholds & measured values | committed JSON keys | Yes — all cross-checked exact | ✓ FLOWING |
| STATE.md bullet | outcome summary | decision doc + JSON | Yes — values consistent (52.000 B/row, 5.2 GB/16 s, in-band verdict) | ✓ FLOWING |

No static-return, hardcoded-literal, or mock-terminated chains found. The 10^8 row is the one non-measured value and it is explicitly flagged `extrapolated: true` at every rendering (JSON, table, decision doc) — correct posture, not a stub.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `cold_seal_growth_test` green in the fail-closed Tier-1 lane (floor + fidelity + density ungated; big legs skip loudly) | `ctest --test-dir SuperGenius/build/Windows/Release -C Release -R "^cold_seal_growth_test$"` | `1/1 Test #116: cold_seal_growth_test — Passed, 7.96 sec` | ✓ PASS |

### Probe Execution

No phase-declared `probe-*.sh` scripts; this phase's probe is the ctest-registered instrument above (executed, PASS).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SEAL-01 | 17-01, 17-02, 17-03 | Seal growth measured at representative workloads (row counts + bytes, incl. recovery-walk ancestry density) and the explicit decision — accept hot growth vs. future design — documented with capacity math | ✓ SATISFIED (pending human ratification items below) | Truths 1-7; measurement coverage (trio), walk-bounds validation (D-12 verdict), decision record (notes/17-seal-growth-decision.md) |

Orphaned requirements: none — REQUIREMENTS.md maps only SEAL-01 to Phase 17 and all three plans claim it. Note: the REQUIREMENTS.md traceability row (line 96) and checkbox (line 53) still read "Pending"/unchecked — orchestrator-owned post-verification update, not a gap.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `cold_seal_growth_test.cpp` | — | Debt markers (TBD/FIXME/XXX) | none found | — |
| `cold_seal_growth_test.cpp` | — | Deletion/compaction calls in probe paths | none found (0 occurrences of Delete/CompactRange/DeleteRange) | Read/count/time-only posture holds (prohibition P1) |
| `cold_seal_growth_test.cpp` | 449, 541 | `"sealed"` literal | ℹ️ Info | Both occurrences inside enumeration suffix comparison only — GATE-03 discipline holds (prohibition on hand-built keys) |
| `cold_seal_growth_test.cpp` | — | RocksDB iterator status unchecked (MAJ-02) | ⚠️ Warning (advisory, open in 17-REVIEW-DISPOSITION) | Measurement-instrument hardening; does not invalidate committed evidence — the exact-count assertion (`seals == seeded N`) fires on any truncating scan, guarding the recorded numbers |
| `cold_seal_growth_test.cpp` | — | Big-leg re-run hits opaque ASSERT on pre-populated grow root (MAJ-01) | ⚠️ Warning (advisory, open) | Re-run guidance documented (README § Reproduce: delete grow root); forward fix noted in disposition |
| `17-03-SUMMARY.md` | — | Claim "Current Position untouched" vs commit `3b7739f` diff | ℹ️ Info | The commit bundles `state.record-session` tool output (frontmatter + Position cursor + Session Continuity move together — tool signature). Plan-task's own edit is the single bullet; no substantive Position content was hand-authored |

Judgment-tier prohibitions (4, from PLAN frontmatter, all `status: unverified, flagged: true`): each was verified with deterministic evidence this pass — P1 zero delete/compact calls; P2 vendored ipfs-lite-cpp CLEAN + zero `src` diff; P3 in-band verdict → no edit at all (diff empty, constant 8); P4 extrapolation flagged at every layer + all cited numbers JSON-matched. Formal human ratification requested below (per ADR-550, never auto-resolved).

### Human Verification Required

### 1. Workload-spectrum representativeness (SEAL-01 "representative workloads")

**Test:** Review the measured spectrum — DAG shapes deep (64-node chain), wide (73 = 1+8+64, fan-out 8), mixed (41 = 32-chain + 8-fan); density at 1/4/1/2/1 erase fractions; scale points 10^6/10^7 measured + 10^8 extrapolated.
**Expected:** Human judges this spectrum defensible as representative for the capacity math (or names a missing workload shape for a future re-measure).
**Why human:** Domain judgment about real recovery-walk traffic; 17-02's flagged_assumption explicitly reserves it ("never auto-resolved").

### 2. D-12 verdict ratification

**Test:** Review `notes/17-seal-growth-decision.md` §(c)/(d) — verdict VALIDATED, in-band, with noted limitation (hermetic topology exercised zero peer-failover attempts; non-interference proven, tightness deferred).
**Expected:** Human accepts this honors SC2's "validated (or re-tuned)" contract (the plan pre-defined this exact outcome shape for reduced observability) — or escalates.
**Why human:** 17-03's flagged_assumption reserves verdict confirmation for the human reviewer.

### 3. Prohibition-block ratification

**Test:** Sign off the four judgment-tier prohibitions (read-only posture; no vendored edits / no spill machinery; verdict-before-edit; no evidence misrepresentation).
**Expected:** Human ratifies — deterministic evidence collected for each this pass (see Anti-Patterns Found).
**Why human:** Judgment-tier prohibitions are never auto-resolved (ADR-550 D3); flagged `unverified-prohibition — human review recommended`.

### 4. Floor seeding-rate window spot-check (minor)

**Test:** Compare run-capture status line ("seeded 1000000 seals in 6301.0 ms (158706 seals/sec...)") vs JSON `leg.volume_10e6_floor.seeding_rate_per_sec = 143312.987` (`seed_elapsed_ms 6977.735`) — both labeled generation-inclusive.
**Expected:** Human confirms which window each measures (e.g., status line = pure seal loop; JSON = generation-inclusive window); no action needed if intentional.
**Why human:** The window semantics aren't derivable from committed artifacts; does not affect the decision (decision doc cites the JSON value; both ~1.4-1.6x10^5 seals/s).

### Gaps Summary

No gaps. All programmatically decidable must-haves verified against the actual codebase, committed evidence, and git history: the instrument is registered, listed, and behaviorally green; the evidence trio is complete, parseable, and carries the required keys with the extrapolation correctly flagged; the decision record carries the band-before-verdict chronology (proven by commit order), the explicit verdict with honest observability posture, D-11 triggers with JSON-key citations (all values cross-checked exact), the options table, and exactly the four ruled sources with the forbidden phrase absent; production containment is airtight (empty `src` diff vs anchor, constant untouched, vendored tree clean, en-route flake fix test-only); STATE.md carries exactly one correct key-decisions bullet. Status is `human_needed` solely for the reserved judgment items the plans themselves deferred to human review (representativeness, verdict ratification, prohibition ratification) plus one minor presentation spot-check.

---

_Verified: 2026-11-19T05:36:06Z_
_Verifier: the agent (gsd-verifier)_
