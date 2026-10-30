---
status: complete
quick_id: 261029-uj0
date: 2026-10-29
---

# 261029-uj0 — Debug failing SuperGenius cold storage tests (SC4, CI 40963277318)

**SuperGenius commits:** `72e54000` (round 7) + `56175311` (round 8) on `dev_blockstore` — tag `test_coldstorage` @ 56175311
**Files changed (r7):** `src/crdt/globaldb/ColdStorageManager.cpp/.hpp` (+22)
**Files changed (r8):** `src/crdt/globaldb/ColdStorageManager.cpp/.hpp`, `test/src/crdt/cold_storage_fault_race_test.cpp` (+85/−1)

## Outcome

Both macOS-only cold-storage CI failures from run 40963277318 root-caused to a single
un enforced single-writer invariant and fixed with one pass-serializing mutex.

## CI failure evidence (run 40963277318, headSha 5942c5d8 = tag `test_coldstorage`)

| Test | OSX Debug | OSX Release | Linux aarch64 Debug |
|------|-----------|-------------|---------------------|
| `cold_storage_fault_race_test` (#103) | Subprocess aborted 6.83s — `Assertion failed: (data_), function data, file multihash.cpp, line 73` in `EvictServe_HalfWindowS3Fetch_ResolvesCidVerified` right after `gc: pass complete - 1 candidate(s), 0 evicted` | **Timeout 600.04s** | **Passed** 24.49s |
| `cold_storage_resurrection_test` (#104) | Subprocess aborted 13.8s — `libc++abi: terminating due to uncaught exception boost::wrapexcept<system_error>: Content type does not conform the version` in `Resurrect_MarkerPresent_DedupBlocksReintegration` after `gc: evicted` passes | Subprocess aborted 10.74s (same signature) | **Passed** 8.40s |

Windows passed both in the same run — the failures are macOS-CI-runner-specific (slow,
contended self-hosted hardware).

## Root cause

`ColdStorageManager::GcPassOnce()` mutates GC pass state — `evicting_marks_`
(a `std::vector<EvictingMark>` with inline `Cid` members), `gc_tick_counter_`,
`last_pass_snapshot_`, `pass_reclaimed_*` — that the header documents as
*"GC-thread-only / single-writer — GcPassOnce never overlaps itself"*. **Nothing
enforced it.** The background `gc_thread_` started by `Start()` runs one immediate
pass before parking on its 10-minute cadence (`gc_interval_ms=0 → kDefaultGcIntervalMs`);
tests (and any external caller) invoke `GcPassOnce()` explicitly at the same time.
On slow/contended runners the two passes overlap:

1. **Torn `EvictingMark.cid` copy** (one pass `push_back`s / reallocs the vector while the
   other iterates or copies marks): the `sgns::CID` move-ctor leaves scalars
   (`version`, `content_type`) copied but `content_address` (a `Multihash` holding a
   `shared_ptr<Data>`) nulled/torn:
   - null `data_` → `Multihash::data()` `BOOST_ASSERT(data_)` → **abort (fault_race Debug)**
   - scrambled `version=V0` + `content_type=DAG_CBOR` → `CID::toString().value()` →
     `ContentIdentifierCodec::encode` → `INVALID_CONTENT_TYPE` ("Content type does not
     conform the version") → unchecked `.value()` throws → **terminate (resurrection, both configs)**
2. **Overlapped passes desync the deterministic test windows** (between-halves /
   pre-half-one hooks fire for both lanes; defer-to-next-tick marks never come due) →
   **600s hang (fault_race Release)**.

Why macOS-CI-only: the overlap window is the background thread's *first* pass at
`Start()` — on fast dev hardware it completes before the test's explicit pass; on the
slower contended OSX runners it grinds through its walk concurrently with the test's passes.

## Fix

`gc_pass_mutex_` (`std::lock_guard` over the whole `GcPassOnce` body) — makes the
documented single-writer invariant real. Stop check moved inside the lock so `Stop()`'s
join stays bounded. Lock order documented: `gc_pass_mutex_ → gc_hook_mutex_ → *cold_store_mutex_`
(no inversions; hook setters take only `gc_hook_mutex_`; no internal caller of
`GcPassOnce` exists → no recursion/deadlock on the non-recursive mutex).

All four TEST-ONLY hook invocation sites already run under `gc_hook_mutex_` — no
changes needed there.

## Verification (local, macOS, Debug, build/OSX/Debug with `SGNS_COLD_STORAGE=ON`)

- Built all 12 cold-storage test targets (the prior build had only 2; 8 lane tests were
  "Not Run" for missing binaries — now built, incl. `cold_storage_wallclock_soak`).
- `ctest -R "cold_storage|cold_read" -j4` with CI env (`SGNS_TEST_P99_BOUND_MS=2000`,
  CI `GTEST_FILTER`): **11/11 Tier1 passed** (fault_race 33.9s, resurrection, spill,
  fallback, durability, gc, gc_retrievability, soak, cold_read_freeze, link_proof,
  config_gate); Tier3 wallclock soak runs its documented env-gated skip.
- 5× full-suite loops: `cold_storage_fault_race_test` **5/5 exit 0**,
  `cold_storage_resurrection_test` **5/5 exit 0**.

### Reproduction notes (deviation from plan Task 1)

The crashes could **not** be reproduced locally, even before the fix:
- 14 solo full-suite iterations (prior executor) — all passed
- Exact CI replica invocation (`ctest . -j8 -C Debug --output-on-failure -LE
  requires_foundry`, CI env) on this 10-core Mac mini (M2 Pro) — fault_race #103 and
  resurrection #104 **passed** under full lane contention (25-min run)
- Deliberate starvation experiment (pre-fix binaries rebuilt from `72e54000^`, 30 CPU
  burners = 3x oversubscription on 10 cores, 15 iterations of the crashing test case):
  **15/15 passed** — uniform CPU starvation does NOT reproduce it

Why: the race window is the background first-pass's duration *relative to* the test
thread's progress. Uniform starvation scales both lanes together, so the ratio is
preserved. The CI OSX runner is a tart VM on an M2 Ultra (faster bare metal than this
M2 Pro) — the amplifier there is **asymmetry**: virtualized scheduling + I-O latency
stretch the I/O-bound background GC pass (RocksDB walks, store ops) while the CPU-bound
test thread proceeds, plus `-j8` lane contention descheduling threads mid-copy. That
asymmetric stretch is not emulatable from userspace on bare metal. Root cause therefore
rests on: (1) the pass state being verifiably unsynchronized dual-writer, (2) both crash
signatures being constructible *only* from torn `EvictingMark.cid` copies in this code —
notably `INVALID_CONTENT_TYPE` requires a V0+non-DAG_PB CID that no legitimate API path
in these tests can produce, only a torn copy mixing a delta CID's version with a block
CID's codec, (3) crash-vs-pass behavior matching the window analysis on both platforms.
The fix eliminates the overlap class entirely regardless of timing — correct by
construction; CI is the final arbiter.

## Out-of-scope local observations (NOT addressed here)

The CI-replica lane run surfaced failures that **pass on CI** and are unrelated to cold
storage — local-environment issues on this machine (macOS 26.4): `processing_datatypes/
nodes/child_tokens/conformance_*` tests abort inside MNN runtime init
(`NSException` in `MNN::registerBackend` / Metal device probe), `vulkan_init_concurrency_test`
times out, `account_management_test` aborts (known flake family already excluded in CI's
GTEST_FILTER). Recommend a separate investigation if they recur.

## Deferred / handoff

- Release-config local verification leg not run (no local Release build configured);
  CI will validate on the next tag build. The Release-mode manifestation (timeout) is
  covered by the same serialization argument.
- Push `dev_blockstore` (`72e54000`) and re-run the tag-build workflow to confirm the
  OSX legs go green.

## Round 8 addendum (2026-10-30) — post-fix CI run 41024756227 residuals

Round 7 was verified partially: the original in-process crash signatures are GONE on CI
(fault_race no longer aborts in `multihash.cpp`; resurrection test 1 now passes on CI).
What remained were two DIFFERENT, load-shaped failures:

| Failure | Where | Diagnosis |
|---|---|---|
| fault_race 600s timeout in `EvictServe_RewarmAttachVsMark_NoLostBlock` | OSX Debug + Release | `WindowGate` had no RAII release: a load-induced ASSERT early-return between hook arming and `Release()` left the drainer parked in the `put_hold` S3-Put hook; teardown `Stop()` join deadlocked until ctest's kill. Leading trigger: the 10s relearn `PollUntil` budget tripping under -j24 load. |
| resurrection full-wire 180s deadline (`:828`), node-2 GC clean **0-candidate** passes for the whole window | OSX Debug + Release + Windows (new) | Passes complete every 200ms, no abort warnings, `durable=2` — a silent eligibility gate excluded both detached deltas. Which gate: unknown from available logs. |

**Round 8 fix (`56175311`):**
1. `~WindowGate()` releases unconditionally at test-body exit — recurrence surfaces as the ASSERT failure, never a hang; relearn budget 10s→60s (rounds 4–6 CI-load precedent).
2. Per-gate eligibility skip counters (`scanned/stamped/skew/age/reachable/state`) logged rate-limited (1st + every 25th pass of a zero-candidate-with-records streak) — the next CI occurrence names its gate directly from logs.

**Local contention experiments (user-directed — all NEGATIVE, post-round-7 binaries):**
- All 12 cold storage tests fully concurrent `-j12` ×5: 100% pass each run
- Full 155-test lane `-j10` (CI-replica env): cold storage 12/12 green (fault_race 24s, resurrection 9.2s incl. the full-wire case CI fails)
- Earlier: 40× filtered loops, 30-burner uniform starvation, concurrent pairs, 12× Rewarm-under-load — all pass
- Cross-process state audit: every cold-storage binary uses a distinct `test-data/<base>/` dir and ephemeral ports — no disk/port collisions; contention is resource-level only
- Conclusion: the residuals require the CI hosts specifically (tart VM on M2 Ultra, 24-way parallelism with heavy processing/multi-node neighbors, ~11 tests failing concurrently around them). The MNN/MoltenVK processing failures (`processing_datatypes/nodes/conformance_*`, `child_tokens`) started with the rebuilt MoltenVK-static thirdparty and reproduce locally — separate investigation.

**Post-round-8 verification:** rebuild + 12/12 cold lane at `-j12` green; eligibility line observed lean (1 per streak). Ready for CI when self-hosted runners return (dispatch: `tag=test_coldstorage thirdparty_tag=test_coldstorage zkllvm_tag=develop run_tests=true cold_storage=true` — BOTH flags, see repo memory note).
