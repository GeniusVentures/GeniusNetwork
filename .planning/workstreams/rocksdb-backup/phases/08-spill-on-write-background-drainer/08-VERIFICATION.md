---
phase: 08-spill-on-write-background-drainer
verified: 2026-10-24T03:35:00Z
status: passed
score: 10/10 must-haves verified
covered_files:
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp
  - SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp
  - SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp
  - SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.cpp
  - SuperGenius/src/crdt/globaldb/globaldb.hpp
  - SuperGenius/src/crdt/globaldb/globaldb.cpp
  - SuperGenius/src/crdt/globaldb/CMakeLists.txt
  - SuperGenius/test/src/crdt/cold_storage_spill_test.cpp
  - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - GeniusWallet/assets/crdt_config.json
  - SuperGenius/docs/evidence/cold-storage/cold-storage-ci-readiness.md
  - .planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-01-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-02-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-03-PLAN.md
  - .planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-01-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-02-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-03-SUMMARY.md
  - .planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-REVIEW.md
  - .planning/workstreams/rocksdb-backup/phases/08-spill-on-write-background-drainer/08-REVIEW-DISPOSITION.md
covered_digest: "v2:sha256:a3569550d68c18c2c756020f40c44fb074ba0d49a15ffd68428c4e0267bf4d69"
behavior_unverified: 0
overrides_applied: 0
---

# Phase 8: Spill-on-Write & Background Drainer Verification Report

**Phase Goal:** Every CRDT block Put passing the single IpfsDatastore seam journals to the durable local cold-store (journal-first, zero remote I/O under `dagMutex_`), and a SuperGenius-owned background drainer moves the journal to S3 with a defined backpressure policy (unbounded journal + always-on dual watermark alarm, exponential backoff), crash-restart reconciliation, and clean shutdown — all proven hermetically in the fail-closed Tier-1 lane.

**Verified:** 2026-10-24T03:35:00Z
**Status:** passed
**Re-verification:** No — initial verification (no prior `*-VERIFICATION.md` existed)

## Goal Achievement

### Observable Truths

Merged from ROADMAP Phase-8 success criteria (SC1–SC5, non-negotiable) and PLAN frontmatter must-haves (deduplicated; roadmap wording kept).

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | **SC1** — Every block Put passing the seam journals block + PendingUpload into `LocalBlockStore` atomically, journal-first, local WAL only, no remote I/O inline; publish latency independent of drainer/s3d state | ✓ VERIFIED | `BlockStoreBackedIpfsDatastore::set` (`BlockStoreBackedIpfsDatastore.cpp:51-99`): journal Put under shared `cold_store_mutex_` → `has_value()` guard → `inner_->set` after. `journal_write_spills_every_put` (fake S3 holds ZERO objects after 10 puts). Behavioral: `sc1_set_latency_independent_of_drainer_state` **run this verification** — paused median 1.934 ms / p99 2.149 ms vs running median 1.972 ms / p99 2.216 ms against 300 ms injected remote latency (paused-vs-running arms, never ON-vs-OFF) |
| 2 | **SC2** — Background drainer (backup-loop pattern, own thread) with exactly one drain in flight; ops-triggered drains enqueue, never inline | ✓ VERIFIED | `ColdStorageManager` single `std::thread` + cv poll loop (`ColdStorageManager.cpp:57-91`); `RequestDrain()` is flag-store + notify only (`:122-128`). Behavioral: `ops_trigger_enqueues_never_inline` **run this verification** — passed in 79 ms at `drain_interval_ms=60000` |
| 3 | **SC3** — Crash-restart startup reconciles `GetPendingUploads` leftovers idempotently (nothing lost, nothing duplicated); shutdown drains-or-resumes cleanly with ordered joins | ✓ VERIFIED | First thread action is `DrainOnce()` (D-12, `ColdStorageManager.cpp:69-71`). Behavioral: `crash_restart_reconciles` **run this verification** (pre-loaded remote object, exactly-N distinct objects via createOnly convergence); `shutdown_grace_joins` passed in suite. Structural: `Stop()` = flag → notify → 5s grace → unconditional join; 0 `detach` matches; `StopBackupLoop();`(line 398) < `StopColdStorageManager();`(line 402) before `lifecycle_mutex_` teardown in `ShutdownNow()` |
| 4 | **SC4** — Explicit backpressure policy implemented and tested (unbounded journal + always-on dual watermark alarm + exponential backoff); consensus write path never fails due to cold-store state — s3d-down window leaves publishes succeeding | ✓ VERIFIED | Behavioral: `s3d_down_window_keeps_publishing` **run this verification** — every `set()` succeeds during fault injection, watermark crosses Warn→Critical, live log line "cold-storage watermark recovered: 0 pending" after heal. `partial_success_cycle_advances_and_backs_off` passed (successes advance while the cycle counts failed — OQ3). Backoff factor 2 / cap / reset-on-clean-cycle (`RecordFailedCycle`/`BackoffReset`); dual count watermarks with always-on transitions up AND down + 60s heartbeat (`UpdateWatermark`) |
| 5 | **SC5** — Hermetic spill tests (fake S3: journal-write, drain, crash-resume, backpressure) committed in the fail-closed Tier-1 lane | ✓ VERIFIED | `ctest -L Tier1 --no-tests=error` **run this verification**: **3/3 passed** (spill 13 cases 4.12 s + config gate 26 + link proof). All 13 `TEST_F` cases enumerated in source AND `--gtest_list_tests` of the built binary. Hermeticity grep: 0 matches for `https?://|docker|localhost|127.0.0.1`. Registration-vs-label parity 3==3; spill test registered only under `if(SGNS_COLD_STORAGE)` |
| 6 | Blank/absent blockstore config constructs nothing — disabled path byte-identical (no factory call, no wrapper) | ✓ VERIFIED | `globaldb.cpp:610-630`: `block_datastore = ipfsDataStore` default; `OpenColdStorageStack` called at exactly one site (:618) inside `if (cold_storage_options_.enabled)`; disabled path flows inner store to `GraphsyncDAGSyncer` untouched; stub returns pure passthrough bundle |
| 7 | OFF build pristine (zero sgns-blockstore symbols) + ON build links the library — exactly one factory TU per configuration | ✓ VERIFIED | **CR-01 fix verified at build level**: `CMakeLists.txt` exclusive `if/else` (`target_sources` real TUs + PRIVATE sgns-blockstore link under ON; stub under `else()`), commit `6ad3aa481`. ON `crdt_globaldb.lib` archive forensics **run this verification**: contains `ColdStorageStack.obj`/`ColdStorageManager.obj`/`BlockStoreBackedIpfsDatastore.obj`, **does NOT contain** `ColdStorageStackStub.obj`; ON vcxproj has zero stub references. Stub obj on disk (03:20:28Z) is an inert leftover from the post-fix OFF verification pass. OFF path compiles by construction (else-branch) — an OFF reconfigure was not re-run here to avoid disturbing the ON working tree |
| 8 | Journal contract edges: re-put idempotent (drained never regresses to PendingUpload), zero-length block journals, remove hot-only, hostile out-of-set CID fails loudly (never terminates) | ✓ VERIFIED | Named tests `re_put_is_idempotent`, `zero_length_block_journals`, `remove_is_hot_only`, `journal_failure_fails_put_loudly` all enumerated in the binary and green in the Tier-1 run; `catch (const std::invalid_argument&)` at `BlockStoreBackedIpfsDatastore.cpp:89-98`; `remove()` pure-forwards to inner (eviction is not CRDT deletion) |
| 9 | `blockstore.backpressure` parses strictly (absent/blank/0 = defaults; non-object/unknown-key/wrong-type/warn>=critical fail loudly naming the offender) + wallet schema parity | ✓ VERIFIED | 26-case `cold_storage_config_gate_test` green in the Tier-1 run; 5 `blockstore.backpressure` message refs in `globaldb.cpp`; `BackpressureOptions` (four uint32 knobs, 0=default) at `globaldb.hpp:85-90` with documented defaults (5000/60000/10000/100000); factory re-normalizes programmatic options and enforces warn<critical loudly. `GeniusWallet/assets/crdt_config.json` carries blank `backpressure` object with the four backup keys intact |
| 10 | Drainer never advances a record to UploadedDurable (Phase-10 boundary); status getter reads atomics under the active-accessor pattern (D-08) | ✓ VERIFIED | Grep `MarkUploadedDurable` in manager: 1 match = docblock stating it is deliberately never invoked; zero call sites; `drain_moves_journal_to_s3` asserts Accepted-only. `GetStatus()` reads three atomics (no journal scan, no lock); `GetColdStorageStatus()` declared on GlobalDB riding the lifecycle-mutex active-accessor pattern |

**Score:** 10/10 truths verified (0 present-but-behavior-unverified — every behavior-dependent truth has a named passing test run in this verification)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp` | Always-compiled factory decl, zero library includes | ✓ VERIFIED | Status/Watermark/Bundle + 4 bridges; single "sgns-blockstore" match is a docblock comment, no include |
| `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp` | Real assembly: coldstore sibling dir, LocalBlockStore, OpenMinioS3Client, S3BlockStore (v1/blocks), decorator, manager | ✓ VERIFIED | All present; every library result `has_value()`-guarded; **MA-02 fix verified**: whole factory body wrapped in `try/catch(std::invalid_argument)` mapping to loud outcome failure |
| `SuperGenius/src/crdt/globaldb/ColdStorageStackStub.cpp` | OFF stub: loud rebuild message + passthrough | ✓ VERIFIED | Exact loud message naming `-DSGNS_COLD_STORAGE=ON`; null-safe no-op bridges |
| `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.hpp/.cpp` | Journal-first decorator, six virtuals | ✓ VERIFIED | 73-line header, `final : public IpfsDatastore`; journal-under-mutex → inner set; rate-limited failure logging |
| `SuperGenius/src/crdt/globaldb/ColdStorageManager.hpp/.cpp` | Drainer: Start/Stop/RequestDrain/GetStatus, split-phase DrainOnce, backoff, watermarks | ✓ VERIFIED | All present and substantive (~330 lines .cpp); destructor calls Stop() (join before members die) |
| `SuperGenius/src/crdt/globaldb/globaldb.hpp/.cpp` | BackpressureOptions, seam wiring, lifecycle, Error::COLD_STORAGE_INIT_FAILED | ✓ VERIFIED | Seam :618 enabled-only; Start :811-812; ShutdownNow :398/:402; loud COLD_STORAGE_INIT_FAILED on factory failure |
| `SuperGenius/src/crdt/globaldb/CMakeLists.txt` | Exclusive gated source lists (CR-01 fix) | ✓ VERIFIED | `if(SGNS_COLD_STORAGE)` real TUs + link, `else()` stub — exactly one factory TU compiles |
| `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp` | 13-case suite + wrappers | ✓ VERIFIED | 13 `TEST_F` (5 journal + 6 behavior + SC1 benchmark + partial-success); `LatencyInjectingS3Client`/`FlakyS3Client` present; bounded poll loops with drainer_healthy vacuous-pass guard |
| `SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp` | 26-case strict matrix | ✓ VERIFIED | 26 `TEST` cases green |
| `GeniusWallet/assets/crdt_config.json` | Blank backpressure sub-object, backup keys intact | ✓ VERIFIED | `{"backup_enabled":true,...,"blockstore":{"backpressure":{}}}` |
| `SuperGenius/docs/evidence/cold-storage/cold-storage-ci-readiness.md` | Phase-8 disposition | ✓ VERIFIED | States gated tests, local ON-lane Tier-1 evidence, ON-lane still blocked-on-thirdparty-release-cut, no cmake.yml change |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `GlobalDB::New` seam | `OpenColdStorageStack` | enabled-only call :618 | ✓ WIRED | Single call site; failure → COLD_STORAGE_INIT_FAILED |
| Factory decorator | `GraphsyncDAGSyncer` | `block_datastore` :631 | ✓ WIRED | Decorator handed to syncer when enabled; inner store when disabled |
| Decorator set() | `LocalBlockStore::Put` → `inner_->set` | journal-first under shared mutex | ✓ WIRED | D-04 ordering + failure mapping |
| `ColdStorageStack.cpp` factory | `bundle.manager` | manager construction + 4 null-safe bridges | ✓ WIRED | Bridges delegate to manager methods |
| `GlobalDB::Start()` | `StartColdStorageManager()` | beside `StartBackupLoop()` :811-812 | ✓ WIRED | Line-order verified |
| `GlobalDB::ShutdownNow()` | `StopColdStorageManager()` | after `StopBackupLoop()` (398<402), before lifecycle teardown | ✓ WIRED | Line-order gate passes |
| Shared `cold_store_mutex` | decorator set path + manager drain path | same instance via bundle | ✓ WIRED | Both hold `*cold_store_mutex_`; remote Put phase runs unlocked |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| Spill suite assertions | Journal bytes/states | real `LocalBlockStore::Open` on temp dir | ✓ real RocksDB journal | ✓ FLOWING |
| Spill suite remote | S3 objects | `InMemoryS3Client` fake (+ Latency/Flaky wrappers) | ✓ fake by design (hermeticity is the property under test) | ✓ FLOWING |
| SC1 benchmark timings | `steady_clock` per set() | live timed loop in test | ✓ real measurement | ✓ FLOWING |
| `ColdStorageStatus` | pending/watermark/healthy | drainer-maintained atomics | ✓ updated per cycle in `UpdateWatermark` | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| SC1 latency independence (paused vs running, 300 ms injected) | `cold_storage_spill_test.exe --gtest_filter=...sc1_set_latency...` | paused median 1.934 ms p99 2.149 ms \| running median 1.972 ms p99 2.216 ms — PASSED | ✓ PASS |
| SC4 s3d-down window (publishes succeed, Warn→Critical→None) | `--gtest_filter=...s3d_down_window...` | PASSED 1522 ms; recovery log observed | ✓ PASS |
| SC3 crash-restart reconciliation | `--gtest_filter=...crash_restart_reconciles` | PASSED (4/4 filter batch) | ✓ PASS |
| SC2 enqueue-never-inline | `--gtest_filter=...ops_trigger_enqueues...` | PASSED 79 ms | ✓ PASS |
| Tier-1 fail-closed lane | `ctest -L Tier1 --no-tests=error` | 100% passed, 0 failed out of 3 (spill 4.12 s) | ✓ PASS |
| CRDT regression | `ctest -R "crdt_test\|globaldb_integration_test"` | 100% passed, 0 failed out of 2 (54.97 s integration) | ✓ PASS |

### Probe Execution

No phase-declared `probe-*.sh` scripts; conventional probe discovery not applicable to this C++/ctest phase. Test-lane commands above serve as the runnable evidence.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|---------------------|----------|
| SPILL-01 | 08-01, 08-03 | Every CRDT block Put at the seam journals block + PendingUpload atomically; local WAL only; no remote I/O on the dagMutex_-held path | ✓ SATISFIED | Truths 1, 5-8; SC1 benchmark; journal-contract tests |
| SPILL-02 | 08-02, 08-03 | Background drainer to S3 with defined backpressure policy, clean shutdown, crash-restart resume | ✓ SATISFIED | Truths 2-4, 9-10; behavior suite + strict config matrix |

Orphaned requirements: none — REQUIREMENTS.md maps only SPILL-01/SPILL-02 to Phase 8; both are claimed by plans and satisfied.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| All 11 phase source/test files | — | Debt markers (TBD/FIXME/XXX) | — | None found (scan clean) |
| `ColdStorageStack.cpp` | 93 | MA-01: config `prefix` parsed/validated/echoed but S3 key prefix hardcoded `v1/blocks` (plan-mandated) | ⚠️ Warning | Operator data-placement expectations can silently diverge from the echoed log; open in 08-REVIEW-DISPOSITION (plan-locked, candidate follow-up before Phase 9 or first deployment config) |
| `ColdStorageManager.cpp` | 143-168 | MA-03: phase (i) snapshots the whole pending set under the shared mutex (no per-cycle cap) | ⚠️ Warning | Publisher worst-case mutex wait grows with journal depth during long outages; D-01 letter (no REMOTE I/O under lock) still proven — SC1 p99 ~2 ms; open in disposition |
| `ColdStorageManager.cpp` | 82-85, 99-105 | MI-01: cv notify without holding wait_mutex_ (lost-wakeup latency window) | ℹ️ Info | Latency-only; work still done on timeout re-check; open in disposition |
| `BlockStoreBackedIpfsDatastore.cpp` | 89-98 | MI-02: rate-limiter state touched in catch path without the shared mutex | ℹ️ Info | Latent (production publisher path is serialized under dagMutex_ — single writer); open in disposition |
| `ColdStorageManager.cpp` | — | MI-03/AD-01..06: sub-warn backlog failure log-invisibility, defaults duplication, status-triple granularity, inverted-cap acceptance, stale comments, doc nits | ℹ️ Info | All recorded with dispositions in 08-REVIEW-DISPOSITION.md; none blocks any phase truth |

No BLOCKER anti-patterns. CR-01 (critical, ODR) and MA-02 (major, unguarded throws) from 08-REVIEW were fixed post-review in SuperGenius commit `6ad3aa481` and their fixes are independently re-verified here (exclusive source lists + archive forensics; factory try/catch in source).

### Prohibition Verification (judgment-tier — evidence recorded per item)

| Prohibition | Evidence | Holds |
|-------------|----------|-------|
| No remote I/O on the dagMutex_-held write path | Decorator set() touches local journal only (code) + SC1 p99 ~2 ms vs 300 ms injection (behavioral) | ✓ |
| remove()/eviction never mutates cold-store data | Pure forward in code + `remove_is_hot_only` test | ✓ |
| Blank/absent config constructs nothing | Seam code :610-630 + stub passthrough + config matrix | ✓ |
| Journal failure never silently skipped (D-04) | Loud UNKNOWN mapping + `journal_failure_fails_put_loudly` test | ✓ |
| Hostile CID never terminates the node | `catch(std::invalid_argument)` + test | ✓ |
| No log line references credentials | Log-format gate: 0 matches; the 11 credential-string matches in globaldb.cpp are Phase-7 env/config *assignments*, never log arguments | ✓ |
| Ops drain never runs inline | RequestDrain = flag+notify (code) + 79 ms test | ✓ |
| Drainer never detached; teardown never precedes join | 0 detach matches; Stop() grace-then-join; destructor Stop() | ✓ |
| Malformed backpressure never silently defaults | Strict parser + 26-case matrix with exact-message assertions | ✓ |
| Drainer never writes UploadedDurable | Zero call sites (comment only) + drain test asserts Accepted-only | ✓ |
| Benchmark never compares ON-vs-OFF | Printed arms are "paused \| running" with injected 300 ms (test source + live output) | ✓ |
| No Phase-8 test touches a live endpoint/Docker/network | Hermeticity grep 0 matches; suite green in ~4 s on fakes | ✓ |
| Evidence doc claims no CI coverage the lane lacks | Phase-8 section records ON-lane as blocked-on-thirdparty-release-cut; no cmake.yml change | ✓ |

All 13 prohibitions carry mechanical (grep), structural (code-read), or behavioral (test) enforcement evidence recorded above — none rests on empty evidence.

### Human Verification Required

None. All behavior-dependent truths have named passing tests executed during this verification; the phase is entirely hermetic C++ with no visual, UX, or external-service surface.

### Gaps Summary

No gaps. All five ROADMAP success criteria and all plan must-haves are verified against the codebase with behavioral evidence executed in this verification (not SUMMARY claims). The two post-review fixes (CR-01 ODR, MA-02 unguarded throws) were independently re-verified at source and build-archive level. Eleven review findings remain open by explicit disposition (0 blocking) — most notably MA-01 (config `prefix` honored-nowhere vs `v1/blocks` hardcoded, plan-locked) and MA-03 (unbounded drain-cycle snapshot under the shared mutex) — both recorded in 08-REVIEW-DISPOSITION.md and STATE for the Phase-9+ planner to weigh; neither fails any phase-8 truth.

Note (informational): the ROADMAP cites the seam at `globaldb.cpp:329`; in the evolved file the single IpfsDatastore construction seam sits at ~:605-631 with the factory call at :618. Intent (one seam, one decorator) is unchanged.

---

_Verified: 2026-10-24T03:35:00Z_
_Verifier: the agent (gsd-verifier)_
