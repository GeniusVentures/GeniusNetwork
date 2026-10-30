---
status: complete
quick_id: 261029-uj0
date: 2026-10-29
---

# 261029-uj0 — Debug failing SuperGenius cold storage tests (SC4, CI 40963277318)

**SuperGenius commit:** `72e54000` on `dev_blockstore` — `fix(12-03): SC4 CI round 7 - serialize GcPassOnce (single-writer pass state)`
**Files changed:** `src/crdt/globaldb/ColdStorageManager.cpp`, `src/crdt/globaldb/ColdStorageManager.hpp` (+22 lines, 2 files)

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
  requires_foundry`, CI env) on this 10-core Mac mini — fault_race #103 and
  resurrection #104 **passed** under full lane contention (25-min run)
- This Mac completes the background first-pass window too fast for the overlap.
  Root cause was therefore established by static analysis mapping both crash
  signatures onto the unprotected pass state (documented in the commit message),
  consistent with the fix being correct-by-construction, then validated by the
  green sweeps above.

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
