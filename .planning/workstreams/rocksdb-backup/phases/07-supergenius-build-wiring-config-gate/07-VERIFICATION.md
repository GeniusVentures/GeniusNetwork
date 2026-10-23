---
phase: 07-supergenius-build-wiring-config-gate
verified: 2026-10-23
status: passed
method: goal-backward verification against the live tree, git history, and re-executed gates (inline verifier run; every claim re-checked, none taken from summaries alone)
requirements: INTG-01, INTG-02, TEST-01
---

# Phase 7 VERIFICATION.md

**Goal:** The integration exists and is off by default — SuperGenius and
GeniusSDK resolve sgns-blockstore through the superbuild install tree, the
`crdt_config.json` blockstore section establishes the blank=disabled /
malformed=loud contract, and the hermetic Tier-1 CI lane is in place from
day one.

## Success Criteria

| # | Criterion | Verdict | Evidence (re-verified this session) |
|---|-----------|---------|-------------------------------------|
| 1 | Both `CommonBuildParameters.cmake` files resolve sgns-blockstore via gated `find_package` (hints, miniocpp-chain order, outside PREFER_CONFIG window), link `sgns-blockstore::sgns-blockstore`, dual-RocksDB proven in one binary, OFF default + mobile FORCE-off | **PASS** (Windows fully proven; Linux/macOS = committed CI lane awaiting push — flagged, not silent) | SuperGenius block: option at :415 AFTER the PREFER_CONFIG window (:392 ON, restored :398-404), find at :442 with httplib→miniocpp order; SDK: option :336, find :363, strictly before `find_package(SuperGenius)` :506; gate counts 4/4 (option + force-off + if + message); ON proof: `windows-on-link-proof.log` — configure+build+`cold_storage_link_proof_test` 1/1 Passed; OFF log zero new finds; ON↔OFF cache re-entry green; single `rocksdb.lib` in the proof link, no version pins (`dual-rocksdb-link-evidence.md`); mobile FORCE-off present in both |
| 2 | Blank/absent section ⇒ byte-identical behavior, proven by hermetic test | **PASS** | `AbsentSectionDisables`, `EmptyObjectSectionDisables`, `OptionalOnlySectionDisables` green in the lane; no new log lines in the disabled path (code-inspected; the only new info line is enabled-gated); trailing-default threading left all 8 pre-existing `GlobalDB::New` call sites unedited; OFF configure log carries zero new finds |
| 3 | Malformed ⇒ loud precise startup failure; env vars take precedence; log-scan proves credentials never printed | **PASS** | Matrix: partial-fill errors name missing fields (post-env), unknown-key (`acess_key`) names the key, wrong-type names the key, not-an-object names the section; `EnvCredentialsSatisfyWhenIntentExists` (env wins), `EnvOnlyCredentialsWithFileIntent` (flagship D-07), `EnvEmptyStringIsUnset`, `EnvNeverActivates`; `LogSummaryContainsEndpointBucketAndNoCredentials` + structural negative gate (no log/throw format string embeds credential fields — CLEAN); throw path fires before InitDatabase and — post CR-01 fix — before joinable io threads exist |
| 4 | TEST-01: hermetic Tier-1 lane fail-closed `ctest -L Tier1 --no-tests=error`, config-gate cases first, no Docker/live endpoints | **PASS** (Windows local lane green; CI runtime on push — flagged) | Lane re-run this session: `100% tests passed, 0 tests failed out of 1` (cold_storage_config_gate_test, 17 cases), non-empty on the default OFF tree (fail-closed, non-vacuous); registration unconditional, LABELS at registration, 2==2 count gate; CI steps committed in `cmake.yml` with `--no-tests=error` + `!cancelled()`; existing fail-open lanes byte-unchanged (count 4, additions-only diff) |

## Requirements Traceability

| ID | Letter (abridged) | Status | Closed by |
|----|-------------------|--------|-----------|
| INTG-01 | Both build files resolve sgns-blockstore via find_package against the install tree, linking on all desktop platforms | **Complete** (Windows local evidence; Linux/macOS via CI on push — recorded) | 07-01 (commits `9f20ad184`, `12c39bc94`, `1a4e322`; evidence bundle in docs submodule `f0a1a02`/`4fc7a76`) |
| INTG-02 | blockstore section: blank/absent ⇒ not constructed; malformed ⇒ loud; env precedence; credentials never logged | **Complete** | 07-02 (`5c97e220e`, `d6fe9cce8`) + 07-03 matrix (`2703a75fe`, `5c596289e`) |
| TEST-01 | Hermetic Tier-1 fail-closed lane from day one | **Complete** (local proof; CI yaml committed, runtime on push) | 07-03 (`2703a75fe`, `f4e9ee31c`) |

## Cross-Phase Regression Gate

Phase-6 Tier-1 lane re-run: `ctest --test-dir thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build -C Debug -L Tier1 --no-tests=error` → **100% tests passed, 0 failed out of 13**. No cross-phase regressions.

## Code Review Gate

Deep review produced 6 findings (2 Critical, 2 Warning, 2 Info) — **all six fixed at source and re-verified** (see `07-REVIEW-DISPOSITION.md`): CR-01 ctor-throw-before-threads (was std::terminate), CR-02 wallet editor silently discarding edits, WR-01 flagship env-credential case added, WR-02 `!cancelled()` on the CI lane steps, IN-01 dead vars, IN-02 not-an-object case added.

## Flagged Items (recorded, not silently dropped)

1. **Linux/macOS ON-link proof** executes via the CI matrix only when the user pushes (no-push constraint during the phase; user_setup in 07-01/07-03). 15 phase-scoped commits across root/SuperGenius/docs/GeniusSDK/GeniusWallet await push.
2. **CI ON-lane is blocked-on-thirdparty-release-cut** (`verdict=stale`: newest release `test_tokenprice` 2026-10-05 predates the Phase-6 install trees — observed tarball listing). Follow-up: cut a thirdparty release, then wire the ON lane (instructions committed in `cold-storage-ci-readiness.md`).
3. **Pre-existing `globaldb_integration_test` failure** ("nodes did not connect" / GossipPubSub peer-repo warnings) — proven pre-existing via stash baseline (fails identically without any Phase-7 change); needs its own investigation out of this phase's scope.
4. `InMemoryS3Client`-fake-based tests: TEST-01's letter lands the lane + config-gate cases first (this phase); the fake arrives with the Phase-8+ data-plane cases — by roadmap design, not omission.

## Verdict

**Phase goal achieved.** All 3 plans summarized, all 3 requirements complete, regression gate green, review findings all fixed, Tier-1 lane fail-closed and green locally. No human-verification items required — the flagged items above are push/release-cut follow-ups, tracked in the user_setup sections and the readiness doc.
