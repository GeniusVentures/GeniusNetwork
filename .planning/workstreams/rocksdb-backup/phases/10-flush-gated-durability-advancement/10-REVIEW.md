---
phase: 10
phase_name: flush-gated-durability-advancement
reviewer: gsd-code-reviewer
date: 2026-10-27
depth: deep
scope:
  - SuperGenius@dev_blockstore 802ee7903^..e6d54fee6 (8 commits; the user-stated base 76e813710 also sweeps in phase-9 commits — the true phase-10 parent is b17643b5a, verified via git rev-parse)
  - thirdparty/sgns-blockstore@main faab7be^..451b4dd (5 commits)
  - GeniusWallet 91edc9e5 (assets/crdt_config.json)
findings_total: 12
by_severity:
  critical: 0
  major: 1
  warning: 3
  minor: 4
  info: 4
status: issues_found
---

# Phase 10 Review: Flush-Gated Durability Advancement

**Reviewed:** 2026-10-27 · **Depth:** deep (per-file + cross-module call/lock tracing)
**Commits:** SuperGenius `b17643b5a..e6d54fee6` (8), sgns-blockstore `faab7be^..451b4dd` (5), GeniusWallet `91edc9e5` (1)

## Summary

The core advancement machinery is sound: the D-03 snapshot discipline (mark EXACTLY the pre-flush Accepted set), the evidence gate (marks only on observed `pendingObjects == 0`), the accepted-never-durable fail-safe direction, the split-phase lock discipline, the ungated-boundary discipline (`ColdUploadState` enum + ODR twin in the stub), the exclusive `if/else` target_sources gating, the env-only admin password with redaction-by-omission, and the zero-`NotFound` taxonomy gate in `S3AdminClient.cpp` all check out against the code. `Base64Encode` was hand-verified correct for all input lengths; the strict 15-field stats parse is correct; `MarkUploadedDurableMany` really is one WriteBatch + one sync Write (`wo_.sync = true` set unconditionally at Impl construction).

One major defect (exception escape through the outcome contract on a malformed `admin_endpoint` port), three warnings (two `admin_mutex_` serialization gaps around `Stop()`/`UpdateStagingHealth`, one ineffective-backoff/log-accuracy defect in the enumeration-failure path), and assorted minor/info items. No credential leakage, no ungated-boundary violation, no result-guard violation in production TUs, no ODR trap.

## Findings

| ID | Severity | File:Line | Description | Suggested fix |
|----|----------|-----------|-------------|---------------|
| MA-01 | major | `thirdparty/sgns-blockstore/src/S3AdminClient.cpp:244` (+ `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp:235`) | `std::stoi` port parse can throw `std::out_of_range` (port > INT_MAX, e.g. `http://127.0.0.1:9999999999`) which escapes `Init` → `OpenS3dAdminClient` → `OpenColdStorageStack` (catch handles only `std::invalid_argument`) → `GlobalDB::open` (no try/catch at globaldb.cpp:714) → uncaught exception at node startup. Violates the code's own invariant ("a construction failure is an outcome failure, never a throw escape") and the header contract (only empty endpoint throws). `stoi` also silently accepts trailing garbage (`:8001x` → 8001) and negative ports (`:-80`) | Parse the port with `std::from_chars` requiring full consumption and range [1,65535]; return `false` from `Init` on any mismatch (already maps to a TemporarilyUnavailable outcome failure). Optionally broaden the stack catch to `const std::exception &` |
| WR-01 | warning | `SuperGenius/src/crdt/globaldb/ColdStorageManager.cpp:177-231` | The `Stop()` D-04 final flush calls `admin_client_->Flush/GetUploadStats` WITHOUT `admin_mutex_`, while public `RefreshStagingStats()` (lines 530-549) uses the same client under `admin_mutex_`. `S3AdminClient` documents no concurrent-call guarantee and claims serialization "by the manager's lifecycle" — not enforced at this call site. After `thread_.join()` the drainer cannot race, but any embedder/test holding the manager can be mid-`RefreshStagingStats` while the final flush runs → concurrent `httplib::Client` use (`set_connection_timeout`/`set_read_timeout` during another thread's read) is UB. Latent today (no GlobalDB accessor exposes RefreshStagingStats) but it violates the phase's stated concurrency contract and Phase-11 exposure would activate it | Wrap the final-flush `Flush`+`GetUploadStats` calls in `std::lock_guard<std::mutex> admin_lock( admin_mutex_ );` |
| WR-02 | warning | `ColdStorageManager.cpp:477` vs `543/548` | `AdvanceDurabilityOnce` evaluates `UpdateStagingHealth(observed, true)` OUTSIDE the `admin_mutex_` scope (the lock block closes at 472) while `RefreshStagingStats` evaluates it INSIDE — two threads can run the predicate concurrently. All fields are atomics (no UB) but the compound read-modify-write of `previous_failed_uploads_` interleaves: the flat-delta baseline can regress (an older tick's store landing after a newer refresh's), so `staging_healthy_` can transiently misreport. Drift direction is conservative (tends unhealthy) but D-12's delta semantics are not actually serialized | Move the `UpdateStagingHealth( observed, true )` call inside the `admin_lock` scope, or acquire `admin_mutex_` inside `UpdateStagingHealth` |
| WR-03 | warning | `ColdStorageManager.cpp:440-444` vs `448` | When the Accepted enumeration fails, `RecordFlushFailedCycle` engages the flush backoff and logs "next attempt in {} ms", but `last_flush_attempt_` is only advanced AFTER a successful snapshot (line 448). With the stale anchor, sustained enumeration failures retry every drain tick once elapsed-since-last-attempt exceeds the 60 s cap — the engaged backoff is inert for this failure class and the alarm's timing claim misleads operators (D-07). Records stay Accepted (fail-safe), so this is pacing/log accuracy, not advancement error | Set `last_flush_attempt_ = now` in (or before) the enumeration-failure branch so the backoff anchors to the failed attempt |
| MI-01 | minor | `ColdStorageManager.cpp:498-505` (also Stop() path ~213-218) | `MarkUploadedDurableMany` returns `result<void>` and skip-and-continues vanished records, but the manager sets `marked = snapshot.size()` on success — skipped records inflate `durable_count_` (and zero `accepted_count_`) in the status atomics. Only triggerable if a snapshot record disappears between snapshot and mark (a mutex-contract violation by definition), so defensive-path accounting drift, not wrong advancement | Have the library return the verified count (`result<size_t, BlockStatus>`), or re-derive the two counters from a follow-up enumeration after the batch call |
| MI-02 | minor | `SuperGenius/src/crdt/globaldb/ColdStorageStack.cpp:262-268` | The `GetColdUploadState` bridge maps EVERY error — including a transient RocksDB `TemporarilyUnavailable` scan failure — to `ColdUploadState::NoRecord`, conflating authoritative absence ("no journal record") with "could not read". A Phase-11 GC consumer treating NoRecord as "not cold-tracked" would act on a false-absence signal during a local-store fault | Map only `StatusClass::NotFound` to `NoRecord`; surface other failures distinctly (e.g., an `Unknown` enumerator) so absence stays authoritative |
| MI-03 | minor | `sgns-blockstore/test/s3_admin_client_test.cpp:91,325`; `test/local_block_store_test.cpp:664`; `SuperGenius/test/src/crdt/cold_storage_durability_test.cpp:133,166` | Unguarded `.value()` on `policy::terminate` results in tests: `MakeClient` and the black-hole test call `opened.value()` with no `has_value()` check — a construction failure would TERMINATE the whole test binary instead of failing one test; `Encoded`, `MakeCid`, `DeriveTestKey` rely on comment-justified deterministic inputs | `ASSERT_TRUE(x.has_value())` before `.value()` in MakeClient and the black-hole test; guard or early-return in the helpers |
| MI-04 | minor | `s3_admin_client_test.cpp:105-206` (+ `test/CMakeLists.txt:92-108`) | `BlackholeListener` is Windows-only (`Start()` returns false on non-Windows, raw WinSock) while the suite registers unconditionally — `FlushReadBudgetBoundsABlockedResponse` hard-fails on Linux/macOS (consistent with the pre-existing `LoopbackHttpStub` lane, so precedent, but the bounded-read proof degrades to a failure off-Windows). Also `Stop()` closes the listening socket then joins; a WinSock `accept()` blocked in the other thread is not guaranteed to unblock on `closesocket` — the hang is currently masked because the client always connects first | `GTEST_SKIP()` on `#ifndef _WIN32` for the black-hole test (or make the listener cross-platform); call `shutdown(socket_, SD_BOTH)` before `closesocket` in `Stop()` |
| IN-01 | info | `ColdStorageManager.hpp:321` / `.cpp:560,564` | `admin_reachable_last_tick_` is written on every health update but never read anywhere (not exposed in `GetStatus`) — dead state | Expose it in `ColdStorageStatus` or drop it |
| IN-02 | info | `S3AdminClient.cpp:266-271` | `SetTimeouts` gives the FULL budget to connection AND read phases separately, so a worst-case call can block up to 2× the stated budget (Stop()'s "2 s" final flush can take ~4 s; the bounded-stop test's 10 s bound still holds) | Split the budget (e.g., connect = min(budget, 1 s), read = budget) or document the 2× worst case |
| IN-03 | info | `cold_storage_durability_test.cpp:542-560` and `:563-600` | In `shutdown_final_flush_advances` (and the failure variant) the PollUntil deadline (10 s) equals the flush floor (10 s) — on an extremely slow machine a cadence flush could fire before `Stop()`, flipping `flush_count` to 2 and failing `EXPECT_EQ(flush_count, 1u)`. Effectively deterministic at normal speeds (drain completes in ~100 ms) | Decouple: PollUntil deadline 5 s against the 10 s floor |
| IN-04 | info | `globaldb.cpp` (`LogSummary`) / `S3AdminClient.cpp:176-178` | If an operator embeds userinfo in `admin_endpoint` (`http://user:pass@host:8001`), the raw endpoint — including the secret — is echoed into `LogSummary` and into the "unsupported endpoint URL" failure string. `admin_endpoint` is documented as non-secret topology, so this is misuse-hardening only | Strip any `user:pass@` component from the endpoint before logging/echoing |

## Verified clean (checked against source, not the description)

- **No-NotFound plan gate:** zero occurrences of `StatusClass::NotFound` in `S3AdminClient.cpp`; every failure path funnels through `AdminUnavailable` (TemporarilyUnavailable). Fake faults likewise.
- **Result-guard discipline (production TUs):** every `.value()/.error()` in `ColdStorageManager.cpp`, `ColdStorageStack.cpp`, `globaldb.cpp`, `S3AdminClient.cpp`, `InMemoryS3AdminClient.cpp`, and `LocalBlockStore.cpp` (new code) is behind a `has_value()`/`if (!res)` check. Test-side exceptions listed as MI-03.
- **Credential hygiene:** `SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD` resolved env-only (unset/empty = none), never a config key, never in `LogSummary`, never in any error string; manager receives presence-only (`SetAdminPasswordPresent`); Basic auth (`":" + password`, verified base64 `OnB3` for `":pw"` on the wire in tests) rides the Authorization header only.
- **Ungated boundary:** `ColdStorageStack.hpp` gained only plain types (`ColdUploadState` enum, plain status fields) — no sgns-blockstore include/type; `GetColdUploadState` ODR twin present in `ColdStorageStackStub.cpp`; `crdt_globaldb` uses exclusive `if(SGNS_COLD_STORAGE)/else()` target_sources (phase-8 CR-01 lesson respected).
- **GetStatus:** pure relaxed-atomics read, 16 fields, no lock, no scan, no HTTP. Restart seeding (`Start()` thread lambda) does the journal scans under `cold_store_mutex_` so `GetStatus` stays scan-free.
- **Eviction gate:** `kEvictionDurabilityGate` is `static constexpr` `UploadedDurable`; no config path touches it.
- **Lock ordering:** `lifecycle_mutex_ → cold_store_mutex_` (GlobalDB accessors) has no reverse-order path; drainer takes `cold_store_mutex_` and `remote_store_mutex_` never nested in either order against each other (remote Puts per-item); admin calls hold `admin_mutex_` alone (except WR-01).
- **DrainOnce/AdvanceDurabilityOnce split-phase:** snapshot and marks under `cold_store_mutex_`; admin calls off both store mutexes; local-store access (incl. Stop() final flush and the on_flush test hook path) always under `cold_store_mutex_`.
- **MarkUploadedDurableMany:** throw-at-entry CID validation, per-item existence gate (skip-not-found), one `rocksdb::WriteBatch` + one Write on `wo_` (`sync = true` set at Impl ctor) — the single-fsync claim holds; state-machine laxity matches the pre-existing `TransitionJournal` (neither validates source state), so no divergence introduced.
- **JSON strictness parity:** `blockstore.durability` sub-object parse mirrors the backpressure branch (unknown key loud, wrong type loud, 0-means-default normalized then min≤max judged on EFFECTIVE values, RapidJSON `IsUint` bounds-checks >2^32); gate-test coverage confirms all four rules plus (e)-inheritance (durability-only never activates — wallet `"durability": {}` parity is inert).
- **CMake/link hygiene:** httplib + nlohmann_json linked `PRIVATE` in `src/CMakeLists.txt` (LINK_ONLY export posture, same as miniocpp/blake2); pimpl keeps both SDKs out of every header; `addtest` matches the repo helper; test include-dir workaround matches the spill-suite precedent; `ws2_32` Windows-gated.
- **Docs:** `docs/s3d-durability.md` process-global flush / loopback-admin-listener / Basic-auth-with-empty-username statements match the implemented wire behavior.

## Notes for the fixer

- MA-01 is the only pre-ship item: an operator typo in `admin_endpoint` must never escape as an exception — the outcome contract is the load-bearing invariant here (same class as 08-REVIEW MA-02).
- WR-01/WR-02 share a one-line shape: extend `admin_mutex_` coverage over the Stop() final-flush admin calls and the tick-path predicate evaluation. Do WR-01 before Phase 11 exposes `RefreshStagingStats` beyond the manager.
- WR-03, MI-01, MI-02 are small, isolated corrections in `ColdStorageManager.cpp` / `ColdStorageStack.cpp`.

---
_Reviewer: gsd-code-reviewer · Depth: deep · 2026-10-27_
_Do not commit — orchestrator handles commit._
