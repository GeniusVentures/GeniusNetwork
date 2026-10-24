---
phase: 08-spill-on-write-background-drainer
reviewed: 2026-10-23T23:59:00Z
commit_range: SuperGenius f26f97e56^..093e2a866 (7 commits); docs submodule 77f4fcf; GeniusWallet 44d378cd
depth: deep
files_reviewed: 15
files_reviewed_list:
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
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
  - SuperGenius/test/src/crdt/cold_storage_spill_test.cpp
  - SuperGenius/docs/evidence/cold-storage/cold-storage-ci-readiness.md
  - GeniusWallet/assets/crdt_config.json
findings:
  critical: 1
  major: 3
  minor: 3
  advisory: 6
  total: 13
status: issues_found
---

# Phase 8: Code Review Report

**Reviewed:** 2026-10-23
**Scope:** SuperGenius `f26f97e56^..093e2a866` (cold-storage stack + drainer + config gate + tests), docs submodule pointer `77f4fcf`, GeniusWallet `44d378cd`
**Depth:** deep (full-file reads of all new TUs, cross-file trace into `thirdparty/sgns-blockstore` headers, build-tree forensics on the ON build)
**Files Reviewed:** 15 (13 source/build files + 2 asset/doc files)
**Status:** issues_found

## Summary

The runtime contracts are, on the whole, faithfully implemented: the D-01 split-phase `DrainOnce` genuinely releases `cold_store_mutex_` before the remote S3 Puts (`ColdStorageManager.cpp:185-202`) and the decorator's `set()` journals locally only; D-04 journal-first ordering, the loud `UNKNOWN` failure, and the hostile-CID `invalid_argument` catch are all in place and hermetically tested; D-03/OQ3 backoff (factor 2, cap, reset-on-first-clean-cycle, partial-success-is-failure), the D-02/D-07/D-09 watermark with always-on transitions plus 60s heartbeat, the D-05/D-06 strict config gate with 0-defaults and post-normalization `warn < critical`, the D-08 atomics status under the active-accessor pattern, the D-11 flag→notify→grace→join stop wired into `ShutdownNow()` before teardown, and the D-12 first-poll reconciliation are all verifiable in the code and covered by the new suites. The security posture holds: no new log line or error string formats `accessKey`/`secretKey` (redaction by omission confirmed by scan and by the `LogSummary` test), and env still cannot activate cold storage.

However, the review found one build-correctness defect that must be fixed before this ships, plus three major functional/robustness gaps. The critical one: **the CMake wiring compiles BOTH `ColdStorageStack.cpp` and `ColdStorageStackStub.cpp` into `crdt_globaldb` when `SGNS_COLD_STORAGE=ON`** — two TUs defining the same five external symbols (an ODR violation). The ON build currently links only because the static-archive linker pulls whichever object it encounters first; on this machine's MSVC build the real TU happened to win (verified via string-literal forensics on the built test executables), but the stub precedes the real TU in the target's source list, so a different generator/linker (Ninja/lld, GCC `ar` symbol-index semantics, or any whole-archive/shared-library link) can silently bind the **stub** — an ON binary whose cold storage fails at startup with the misleading "binary built without SGNS_COLD_STORAGE" error — or die with duplicate-symbol link errors. This is exactly the silent-misbuild class the phase exists to prevent.

## Critical Issues

### CR-01: ODR violation — stub and real stack TU both compiled on `SGNS_COLD_STORAGE=ON`; correct binding left to archive-order luck

**File:** `SuperGenius/src/crdt/globaldb/CMakeLists.txt:14-25`
**Issue:** `ColdStorageStackStub.cpp` is listed unconditionally in `add_library(crdt_globaldb ...)`, while `ColdStorageStack.cpp`, `ColdStorageManager.cpp`, and `BlockStoreBackedIpfsDatastore.cpp` are appended under `if(SGNS_COLD_STORAGE)`. Both `ColdStorageStack.cpp` and `ColdStorageStackStub.cpp` define, with external linkage in `namespace sgns::crdt`, the same five functions: `OpenColdStorageStack`, `StartColdStorageManager`, `StopColdStorageManager`, `GetColdStorageManagerStatus`, `RequestColdStorageDrain`. There is no preprocessor guard in the stub and no `list(REMOVE_ITEM)` excluding it when ON. Both objects are demonstrably present in the ON build tree (`crdt_globaldb.dir/Debug/` contains both `ColdStorageStack.obj` and `ColdStorageStackStub.obj`). The existing comment only addresses unity-build inclusion (`SKIP_UNITY_BUILD_INCLUSION`), not archive symbol duplication.
**Why it matters:** A static archive tolerates the duplicate at `lib` time, so the failure is deferred to exe linking, where the linker pulls the first member that satisfies the undefined symbol — an implementation detail, not a contract. The stub precedes the real TU in the target's source order, so on linkers whose archive index maps each symbol to the first defining member (GNU `ar`/`ld`, `lld`), an ON build binds the **stub**: `GlobalDB::New` then fails at startup with `"binary built without SGNS_COLD_STORAGE"` on a binary that was in fact built with it — cold storage silently non-functional (the precise "silent disable trap" the stub's own error message says it exists to prevent). On toolchains that pull both members (whole-archive for shared-lib/framework packaging, or any future symbol added to only one TU), the link hard-fails with duplicate-symbol errors. The current MSVC build bound the real TU by luck, verified only for `cold_storage_config_gate_test.exe`; nothing guarantees it for other platforms/generators that Phase 8's ON lane targets (desktop Linux/macOS).
**Fix:** Compile the stub only when the gate is OFF:

```cmake
add_library(crdt_globaldb
    GlobalDbNetworkComposition.cpp
    globaldb.cpp
    pubsub_broadcaster_ext.cpp
    keypair_file_storage.cpp
)

if(SGNS_COLD_STORAGE)
    target_sources(crdt_globaldb PRIVATE
        ColdStorageStack.cpp
        ColdStorageManager.cpp
        BlockStoreBackedIpfsDatastore.cpp
    )
    target_link_libraries(crdt_globaldb PRIVATE sgns-blockstore::sgns-blockstore)
else()
    target_sources(crdt_globaldb PRIVATE ColdStorageStackStub.cpp)
endif()
```

(The `SKIP_UNITY_BUILD_INCLUSION` properties can then be dropped for the mutually exclusive pair, though keeping them for the gated TUs is harmless.)

## Major Issues

### MA-01: Config `prefix` is parsed, validated, logged — and silently ignored; the S3 key prefix is hardcoded

**File:** `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp:93-94`
**Issue:** The factory opens the remote store with `sgns::blockstore::S3BlockStoreOptions{ "v1/blocks" }` — a literal equal to the library default — and never references `options.prefix`. Meanwhile `ParseColdStorageConfig` accepts `blockstore.prefix` (`globaldb.cpp:151,229-231`), defaults it (`globaldb.cpp:302`), `LogSummary()` echoes it (`globaldb.cpp:96-101`), and the gate test asserts its round-trip (`cold_storage_config_gate_test.cpp:238-241`). Note the phase plan itself is contradictory here: `08-01-PLAN.md:114` both pins `keyPrefix v1/blocks` and instructs mapping `prefix` into `S3ClientConfig` (which has no `prefix` member — flagged in `07-01-SUMMARY.md:136-138`); the implementation took the half that silently discards user input.
**Why it matters:** An operator who sets `"prefix": "prod/eu/"` gets every cold block under `v1/blocks/` with no error, no warning — and a startup log line that actively claims the configured prefix is in effect. Data-placement policy (bucket partitioning, lifecycle rules per prefix, cross-environment isolation) is silently violated; this is a misconfiguration trap of the same genus as the P10 silent-disable the phase rejects elsewhere.
**Fix:** Either honor the field — `S3BlockStoreOptions{ options.prefix.empty() ? std::string("v1/blocks") : options.prefix }` (plus a charset sanity check, since `keyPrefix` becomes literal key bytes) — or, if v1 truly must pin `v1/blocks`, reject a non-empty `prefix` loudly at parse time ("prefix is reserved and not yet honored") so no operator can believe a lie. Also reconcile `LogSummary()`/docs with whichever behavior is chosen.

### MA-02: `OpenColdStorageStack` calls throwing library factories with no `invalid_argument` guard — programmatic config errors terminate the embedder

**File:** `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp:66-96`
**Issue:** `OpenMinioS3Client` throws `std::invalid_argument` when endpoint or bucket is empty (`S3Client.hpp:200-208`); `LocalBlockStore::Open` throws on an empty path (`LocalBlockStore.hpp:88-92`); `S3BlockStore::Open` throws on null client / empty prefix (`S3BlockStore.hpp:96-108`). The factory guards every *result* (`has_value()` before `.value()`, correctly) but wraps none of these *throws*. The file-config path cannot reach them (the parse gate requires non-empty endpoint/bucket), but the programmatic path can: `GlobalDB::New(..., ColdStorageOptions{...enabled=true, endpoint=""})` from an SDK/game embedder throws straight through `Init`/`New` with no catch anywhere on the path.
**Why it matters:** The phase's own posture is that configuration mistakes fail loudly *as errors*, never as node termination — the decorator catches `std::invalid_argument` for exactly this reason (`BlockStoreBackedIpfsDatastore.cpp:89-98`, D-04). The factory seam leaves the same taxonomy of throw uncaught one layer up, crashing the embedder process for a config typo. With CR-01 fixed the OFF-build path also routes here (stub), so this seam is the single choke point for all cold-storage startup failures.
**Fix:** Wrap the three `Open` calls in `try { ... } catch (const std::invalid_argument &e) { return outcome::failure(std::string("cold storage: invalid configuration (") + e.what() + ")"); }` — the message carries no credential material, consistent with the redaction rule.

### MA-03: `DrainOnce` phase (i) buffers the entire pending set in memory under the shared mutex — unbounded growth stalls the publisher as the journal grows

**File:** `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp:143-168`
**Issue:** Phase (i) enumerates `GetPendingUploads()` and then `Get`s **every** pending item's bytes into the `items` vector, all while holding `cold_store_mutex_`. There is no per-cycle cap. The D-01 letter is honored (the held work is local RocksDB I/O, never remote), but with the documented defaults (`critical_pending = 100000`) and an unbounded journal during a long S3 outage: (a) the drainer buffers all pending bytes in memory at once (memory spike proportional to the journal's byte size), and (b) every publisher `set()` blocks for the full fetch duration of the *entire* pending set (100k local Gets ≈ seconds per cycle), on every cycle — publisher write latency grows without bound with local cold-store accumulation, which is the failure shape D-01 exists to prevent ("writes are NEVER blocked by cold-store state" — remote was the letter, local accumulation is the spirit).
**Why it matters:** The mechanism that reports overload (the watermark) is what makes the overload worse: the deeper the backlog, the longer the publisher stalls each cycle, and the larger the memory high-water mark. A sustained outage at default thresholds turns into multi-second `set()` stalls and a potential OOM on block-heavy nodes — a robustness defect, not just a performance nit, because it degrades the *write path* the phase contract shields.
**Fix:** Bound the cycle: take the first N pending CIDs per cycle (e.g., `constexpr size_t kMaxItemsPerCycle = 256;` slice of the `GetPendingUploads()` result) — partial progress still converges (`MarkUploadedAccepted` only for remote-present outcomes, retried next cycle), backoff semantics unchanged, memory bounded, and the publisher's worst-case mutex wait becomes O(N) instead of O(pending). Optionally re-fetch bytes per item with per-item lock scopes if N stays small.

## Minor Issues

### MI-01: `RequestDrain`/`Stop` notify `wait_cv_` without holding `wait_mutex_` — lost-wakeup window delays pickup (and Stop's join) by up to the current backoff

**File:** `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp:82-85, 99-105`
**Issue:** Both do `flag.store(true); wait_cv_.notify_all();` without acquiring `wait_mutex_`. If the store+notify lands between the drainer's predicate evaluation and its sleep registration inside `wait_for`, the notify finds no waiter and is dropped; the drainer sleeps the full `current_delay_` (default 5s, backoff up to 60s) before the timeout re-checks the predicate. The work is eventually done (predicate re-checked on timeout), so this is a latency defect, not a correctness one — but it also means `Stop()`'s "bounded grace (5s) then join" can in practice block up to `current_delay_` beyond the grace window. (The pattern is copied from the pre-existing backup loop; the repo precedent doesn't make it correct.)
**Fix:** Hold `wait_mutex_` while setting the flag, then notify: ` { std::lock_guard<std::mutex> l(wait_mutex_); drain_requested_.store(true); } wait_cv_.notify_all();` — same for `stop_flag_` in `Stop()`. Cheap, removes the window.

### MI-02: `ShouldLogJournalFailure()` runs without `cold_store_mutex_` in the `catch` path — data race on the rate-limiter state under concurrent `set()`

**File:** `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.cpp:61, 70, 89-98`
**Issue:** The non-throw failure path calls `ShouldLogJournalFailure()` under the `cold_store_mutex_` lock (line 61→70), but in the `catch (const std::invalid_argument&)` path the `lock_guard` has already been destroyed by unwinding, so line 94 mutates `last_journal_failure_log_`/`suppressed_journal_failures_` unlocked. `set()` can be invoked concurrently (multiple asio threads; the journal write itself is serialized by the shared mutex, the rate-limiter is not in this path). Formally UB; practically a garbled rate-limit counter on a hostile-CID storm.
**Fix:** Re-take the lock in the catch block (the journal is not touched there, so contention is nil), or give the rate-limiter its own tiny mutex so both paths are uniform.

### MI-03: A persistent drain failure with a small backlog is log-invisible

**File:** `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp:233-243, 257-315`
**Issue:** There is no log line for entering/holding a failure streak — only the recovery line (`:246-250`) and the watermark-driven transition/heartbeat lines. The D-09 heartbeat fires only while a watermark (Warn/Critical) is held. With defaults (`warn_pending=10000`), a total S3 outage with, say, 200 pending records backs off to the 60s cap and then cycles silently for hours: `drainer_healthy=false` in the status triple, zero log evidence. The config-gate rationale ("caught at startup, not as a confusing auth failure at first drain") shows the phase cares about this visibility class.
**Fix:** Rate-limit a failure-streak line (e.g., log when `failure_streak_` hits 1 and each doubling, mirroring the backoff curve), or fold it into the existing heartbeat by heartbeatting on `!healthy_` as well as on held watermarks.

## Advisory

### AD-01: Backpressure defaults duplicated in two TUs
**File:** `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp:33-38` vs `SuperGenius/src/crdt/globaldb/globaldb.cpp:114-118`
**Issue:** The four `kDefault*` constants (and the pair rule, and the 0-normalization) exist in both the parser and the factory. Intentional defense-in-depth, but they can drift silently. **Fix:** hoist one `constexpr` set into `ColdStorageStack.hpp` (always compiled, library-free) and consume from both.

### AD-02: Status triple cannot distinguish disabled / starting / unhealthy
**File:** `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp:47-54`
**Issue:** `drainer_healthy=false` is returned when cold storage is disabled (null manager), before the drainer's first completed cycle, and during a failure streak — three very different operational states with one observable value. The spill tests even work around the starting state (`cold_storage_spill_test.cpp:615-618`). **Fix:** consider adding an `enabled`/`started` bit (or a small state enum) to `ColdStorageStatus` in a future phase; not a Phase-8 contract violation since D-08 specifies only the triple.

### AD-03: SC1 benchmark flake surface
**File:** `SuperGenius/test/src/crdt/cold_storage_spill_test.cpp:925-950, 369-377`
**Issue:** Hard latency assertions (`p99 < 100ms`, `[0.5x, 2.0x]` median band) are machine-load sensitive; `StatsOf` guards emptiness with non-fatal `EXPECT_FALSE` and then indexes — on an already-failing path that is out-of-bounds. **Fix:** widen to environment-tolerant bands (or gate the strict bounds behind a label), and use `ASSERT_FALSE` in `StatsOf`. Only matters for test reliability, not production code.

### AD-04: `backoff_cap_ms < drain_interval_ms` accepted silently
**File:** `SuperGenius/src/crdt/globaldb/globaldb.cpp:253-282`
**Issue:** The pair rule validates only `warn < critical`; a cap below the interval floor is nonsense but accepted, and `RecordFailedCycle` (`ColdStorageManager.cpp:233-243`) then never grows the delay past the floor. Harmless-but-misleading config. **Fix:** validate `backoff_cap_ms >= drain_interval_ms` post-normalization, or clamp in the factory.

### AD-05: Stale comments at the seams
**File:** `SuperGenius/src/crdt/globaldb/ColdStorageStack.hpp:96-97` ("manager null in plan 08-01" — 08-02 fills it); library-side, `BlockStore.hpp:73-80` still says out-of-set = "not sha256" while `Cid.hpp` widened the accepted set to `{sha-256, blake2b-256}` (the widened set is why production CRDT blake2b-256 CIDs pass — worth keeping accurate since the decorator's D-04 catch depends on it). **Fix:** one-line comment updates.

### AD-06: Asset/doc nits
**File:** `GeniusWallet/assets/crdt_config.json` (no trailing newline — pre-existing), `SuperGenius/docs/evidence/cold-storage/cold-storage-ci-readiness.md` (mojibake em-dashes — UTF-8 read as ANSI somewhere in the toolchain). Cosmetic only; the blank `backpressure` sub-object itself is correct per the Phase-7 (e) rule and `BackpressureBlankObjectGivesDefaults`/`BackpressureOnlySectionDisables`.

## Contract verification matrix (for the audit trail)

| Contract item | Verdict | Evidence |
|---|---|---|
| D-01 mutex never held across remote I/O | PASS | `ColdStorageManager.cpp:143-168` (locked), `:185-202` (unlocked remote Puts), `:204-216` (re-lock); SC1 test |
| D-04 journal-first, loud failure, hostile CID caught | PASS | `BlockStoreBackedIpfsDatastore.cpp:57-110`; tests `journal_failure_fails_put_loudly`, `zero_length_block_journals` |
| D-03/OQ3 backoff incl. partial-success | PASS | `ColdStorageManager.cpp:218-252`; test `partial_success_cycle_advances_and_backs_off` |
| D-02/D-07/D-09 watermark always-on + heartbeat | PASS (MI-03 visibility gap below warn) | `ColdStorageManager.cpp:257-315`; test `s3d_down_window_keeps_publishing` |
| D-05/D-06 config strictness, 0-defaults, (e) inheritance | PASS | `globaldb.cpp:154-283`; gate matrix tests |
| D-08 atomics status, active-accessor | PASS | `ColdStorageManager.cpp:110-115`, `globaldb.cpp:779-790` |
| D-11 stop: flag→notify→grace→join, pre-teardown | PASS (MI-01 latency caveat) | `ColdStorageManager.cpp:81-97`, `globaldb.cpp:398-401` |
| D-12 first poll = reconciliation | PASS | `ColdStorageManager.cpp:56-66`; test `crash_restart_reconciles` |
| Credentials never formatted; env never activates | PASS | scan of all new TUs; `LogSummary` test, `EnvNeverActivates` |
| Blank/absent config byte-identical; OFF build library-free | PASS for OFF (stub only) — **ON build is the CR-01 defect** | `globaldb.cpp:610-628`, stub TU; `CMakeLists.txt:14-25` |
| Eviction hot-only; UploadedDurable never written | PASS | `BlockStoreBackedIpfsDatastore.cpp:135-139`; drainer marks Accepted only |
| Every library result guarded before `.value()/.error()` | PASS | all call sites in the three gated TUs |
| Coding standards (Ullman, PascalCase, trailing `_`, Doxygen) | PASS | consistent across new files |

---

_Reviewed: 2026-10-23_
_Reviewer: gsd-code-reviewer_
_Depth: deep_
