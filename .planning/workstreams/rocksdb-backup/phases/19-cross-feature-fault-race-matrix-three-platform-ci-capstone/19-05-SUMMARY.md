---
plan: 19-05
phase: 19-cross-feature-fault-race-matrix-three-platform-ci-capstone
completed: 2026-11-25
requirements: [TEST-02, TEST-03]
status: complete
---

# Plan 19-05 Summary: The Capstone Closed — Tier-1 Fail-Closed Lane in the Dispatch Instrument + the Three-Platform Both-Lanes Evidence (D1–D8)

## What Was Built

The dispatch instrument is contract-complete and the capstone record is closed. `build-release-tags.yml` now carries BOTH additive **Tier-1 fail-closed lane** steps (non-Linux + Linux, `ctest -L Tier1 --no-tests=error`, RUN_TESTS-gated) — every `cold_storage=true, run_tests=true` dispatch exercises the labeled lane, and an empty selection fails rather than passing vacuously. The rulings doc `notes/19-cross-feature-fault-race-three-platform-capstone.md` renders the complete record: the X1..X11 matrix table (TEST-02's artifact), the NON-cold-only quarantine table Q1–Q7, the D-14 portability runbook, the D-11 both-lanes reading, the B1/B2 push-topology ruling, the X11 promotion record, and the closing evidence. The refreshed `19-FRESH-CLONE-CHECKLIST.md` Status reads **COMPLETE** with the per-platform run links.

**The closing evidence (D-15/D-16 — one green dispatch per platform, both lanes):**

| Platform | Run | Full-suite lane | Tier-1 fail-closed lane |
|----------|-----|-----------------|-------------------------|
| Windows-Release | D3 (45257655488) | **169/169 GREEN** | **20/20 GREEN** |
| Linux-x86_64 + aarch64 (Release) | D3 (45257655488) | **GREEN** | **GREEN** |
| OSX-Release | D7 (45489840538) | **171/171 GREEN** | **20/20 GREEN** |
| *(confirming, final HEAD `41776b0c0`)* OSX-Release + OSX-Debug | D8 (45504484532) | cold 100% green | **20/20 GREEN both configs** |

## Key Changes

### CI (one file, additive only)

- `SuperGenius/.github/workflows/build-release-tags.yml`: the two Tier-1 fail-closed lane steps mirroring `cmake.yml:691-707`/`:797-806`, placed after the existing Run tests steps; no existing step touched; `cmake.yml` **zero-diff** (B2 held — verified at close-out).

### Docs

- `notes/19-cross-feature-fault-race-three-platform-capstone.md`: the rulings-chain doc (matrix table, quarantine table, runbook, both-lanes reading, B1/B2, X11 promotion) + the dispatch trail D1–D8 + **THE CLOSING EVIDENCE TABLE**.
- `19-FRESH-CLONE-CHECKLIST.md`: Status PENDING → **COMPLETE (2026-11-25)**; push-state table filled (SuperGenius `41776b0c0` pushed with tag `test_coldstorage`; thirdparty `da17826` pushed; MoltenVK assets regenerated via the user's rebuild run 45297525343); the checkpoint rulings recorded as final (B2 stands; X11 one-green met).

## The Dispatch Trail (every cold find fixed forward — zero quarantined cold failures)

The evidence did not come free: eight dispatches, each triaged to a root cause.

1. **D1 (45235774034):** the GNU/lld link find (single-pass linkers never pulled `buffer.cpp.o` — latent since 16-02) → ctor inlined into `buffer.hpp` (`9804dbf8f`); the X11 macOS vacuous-pass find → the direct B-consult teeth.
2. **D2 (45252321451):** the OFF-build stub find — four Phase-16 forwardings landed without `ColdStorageStackStub.cpp` twins → `583734cba`.
3. **D3 (45257655488):** **Windows + Linux closing evidence obtained**; the X11 real production gap (topic-agnostic queued peer-queue push + consult-only-on-cold-miss merges) → the `HandleRootCIDBlock` evidence guard (`0e22c1cd3`); iOS MoltenVK install-skip → thirdparty `da17826` (REMOVE-before-install).
4. **D4 (45308718527):** **X11 promoted** (one-green on all three platforms — the re-ruled bar); the Interleave park-arm race → the mid-pass seam `SetGcMidPassHookForTest` (`4f7281b1f`).
5. **D5 (45349343985):** first all-green OSX Debug; InteractionC/Race park races → all parks moved to the mid-pass seam (`ebd8c80b8`).
6. **D6 (45467222690):** OSX Tier-1 20/20 (the last capstone row); the UNPARKED Converge quiescence race → terminal-fact gate + two-arm acceptance (`6e8b1610c`).
7. **D7 (45489840538):** **OSX-Release fully green (both lanes)**; the downgrade-e2e t0 keys-capture race → `PollUntil(pending==0 && durable>=4)` before the snapshot (`41776b0c0`).
8. **D8 (45504484532):** **the closing dispatch** — zero cold failures, Tier-1 20/20 both OSX configs, `Resurrect_FullWire` passed (the load-class ruling validated); only non-cold transverse suites failed (`multi_account` SEGFAULT — the D4-documented transverse; `transaction_sync` 50 s deadline expiries — green on develop Nov-19 and green D5–D7 on this branch).

## Verification Results (close-out gates)

- Run links in the notes evidence section: **5** (≥3 required).
- Platform rows with both-lanes outcomes: **28** matches (≥3 required).
- Checklist Status line: reads **COMPLETE** with run IDs + parameters.
- `ci(19-05)`/`fix(19-05)` commits in the SuperGenius log: **10** (≥1 required).
- Tier-1 lane steps in `build-release-tags.yml`: **2** (both present).
- `cmake.yml`: **zero-diff** (B2 posture held).
- No exclusion matching any `cold_*` test name added anywhere in the phase (the D-12 letter held through all eight dispatches).

## Deviations from Plan

**[Rule 1 — the dispatch count]:** the plan's checkpoint imagined one dispatch; the evidence took eight (D1–D8) because each cold-labeled failure was fix-forwarded in scope per the plan's own rule — never quarantined, never excluded. The one-green-per-platform bar was met as ruled (Windows D3, Linux D3, OSX D7), with D8 as the confirming run at the final HEAD. X11's promotion bar was re-ruled at the checkpoint to ONE green (2026-11-20) and was met at D4 with zero X11 failures thereafter.

**[Local-environment finding (recorded, not a deviation):]** the dev box's Cloudflare WARP tunnel breaks local two-node libp2p loopback dials — surfaced when the local Tier-1 rerun failed exactly the two wire-delivery gates while both were green pre-WARP and green on CI at the same HEAD. Ruled environmental; the runbook's CloudflareWARP entry is the documented home.

## Phase 19 Goal Verification (goal-backward)

**Goal:** *"The composed v1.2 system — erase × serve × recovery — is disproof-proven under induced failure at every phase boundary, and recovery-walk suites run green on all three platform CI lanes with cold storage ON."*

1. **SC1 — the matrix:** X1..X11 landed (19-01..19-04), red-first, barrier-driven, env-knob reproducibility on every nondeterministic case; the matrix table renders once in the notes doc (TEST-02's artifact) with the suite header pointing at it. **MET.**
2. **SC2 — three-platform green:** Windows D3 both-lanes, Linux D3 both-lanes, OSX D7 both-lanes, all `run_tests=true, cold_storage=true` fresh-clone dispatch builds with the Tier-1 lane listing `cold_cross_feature_fault_race_test`; D8 confirms at the final HEAD. **MET.**
3. **SC3 — the portability list:** the D-14 runbook (CloudflareWARP adapter = environmental, distinct per-node base paths, poll predicates, gtest filter grammar + env vars + caps + crash-report pointers + dispatch toggles) lives in the notes doc §(c). **MET.**

**TEST-02 discharged** (the matrix artifact + red signatures citable by location); **TEST-03 discharged** (the fail-closed lane green on all three platforms, membership proven from dispatch evidence).
