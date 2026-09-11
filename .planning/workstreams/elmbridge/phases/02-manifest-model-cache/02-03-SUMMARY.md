---
phase: 02-manifest-model-cache
plan: 03
subsystem: elmruntime
tags: [elm, model-cache, single-flight, lru, quarantine, pin-raii, smoke-check, mnn, sgprocessingmanager]

requires:
  - phase: 02-manifest-model-cache
    provides: plan 02-01 — ElmRuntimeError category, ParseAndVerifyManifest/ComputeManifestHexDigest/RoleFileName/TotalArtifactBytes, FetchFn + MakeFileManagerFetchFn, sgprocmanagerelmruntime target, sgprocelmruntime_manifest_test
provides:
  - "sgns::elmruntime::ElmModelCache — content-addressed model bundle cache: Acquire (single-flight publish / size-first hit), SetByteCap, Create + CreateProductionElmModelCache factories"
  - "sgns::elmruntime::ElmCachePin — move-only RAII pin (trailing-slash entry dir + hex digest + cache back-pointer); the Phase 3 handle handed to Llm::createLLM"
  - "sgns::elmruntime::SmokeCheckFn + MakeMnnLlmSmokeCheck() — SGPROC_HAS_MNN_LLM-gated loadability probe (createLLM → set_config(greedy,1) → load → 1-token response → destroy), fail-closed SMOKE_CHECK_UNAVAILABLE fallback"
  - "kDefaultElmCacheByteCap = 15 GiB (uint64_t) — D-04 default eviction cap"
  - "sgprocelmruntime_cache_test — 18-case offline lifecycle matrix (incl. gated real-MNN garbage-bundle leg), all green"
affects: [Phase 3 processor (Acquire at the ELM branch, pin dir → createLLM, quarantine/quarantine-retry mapping to RESOURCE_RESOLUTION), Phase 4 E2E (first real model load through the cache)]

tech-stack:
  added: []  # zero new dependencies (D-003): boost/uuid was already vendored — NOTE the installed layout is boost/uuid (no trailing s), matching processing_tasksplit.cpp
  patterns:
    - "single-flight via unordered_map<string, shared_future<AcquireOutcome>> with the promise ALWAYS resolved by value (P2-7 — grep-enforced zero set_exception); waiter re-enters the hit path to pin the same entry"
    - "atomic publish = stage(.tmp-<uuid>) → verify → smoke(pre-rename) → quarantine-stale-then-rename (Windows P2-2); staging RAII cleanup on every abort (Q4)"
    - "size-first hit path (D-01): stored-manifest re-verify + fs::file_size per role; zero artifact sha256 on hit"
    - "restart rebuild (D-06): regex-validated 64-hex dirs re-verified through ParseAndVerifyManifest; .tmp-* swept, .bad-* ignored forever (D-07), foreign dirs untouched"

key-files:
  created:
    - SuperGenius/SGProcessingManager/include/elmruntime/ElmSmokeCheck.hpp
    - SuperGenius/SGProcessingManager/src/elmruntime/ElmSmokeCheck.cpp
    - SuperGenius/SGProcessingManager/include/elmruntime/ElmModelCache.hpp
    - SuperGenius/SGProcessingManager/src/elmruntime/ElmModelCache.cpp
    - SuperGenius/SGProcessingManager/test/elmruntime/elm_model_cache_test.cpp
  modified:
    - SuperGenius/SGProcessingManager/src/elmruntime/CMakeLists.txt (self-gate detection + ElmSmokeCheck/ElmModelCache TUs + conditional MNN/Vulkan PRIVATE link)
    - SuperGenius/SGProcessingManager/test/elmruntime/CMakeLists.txt (sgprocelmruntime_cache_test registration, TIMEOUT 300)

key-decisions:
  - "Staging failures CLEAN UP; quarantine (.bad-<digest>) reserved for reuse-time mismatch (Q4 per D-02's letter) — a retried publish would collide on the .bad-<hash> name anyway"
  - "Smoke check runs pre-rename against the STAGING dir (A5): a failed probe never leaves a final-path entry; one MNN load per publish under VulkanInitMutex"
  - "Single-flight keyed by NORMALIZED declared hash (sha256: prefix stripped, lowercased); computed-digest-vs-declared still enforced by ParseAndVerifyManifest — dir name is always the computed 64-hex (P2-4)"
  - "Eviction failures tolerated and retried next pass (P2-3); over-cap-with-all-pinned tolerated (cap is a bound, not an invariant breaker) — pinned entries never removed"
  - "Boost uuid headers included as boost/uuid/* (vendored 1.85 layout has no boost/uuids/) — same include set as processing_tasksplit.cpp"
  - "Restart scan re-verifies each 64-hex dir through the full ParseAndVerifyManifest front door before adopting it (self-consistency: stored digest must match dir name); unverifiable dirs left untouched and untracked"

patterns-established:
  - "content-addressed entry == MNN LlmConfig.base_dir: <root>/<hex>/ holds elm_manifest.json + role files; the pin's trailing-slash dir string feeds createLLM directly"
  - "D-02 quarantine loop: mismatch → rename .bad-<hex> → CACHE_ENTRY_QUARANTINED → no refetch in-call → next Acquire cleanly re-downloads (no livelock: poisoned dir renamed off the load path)"

requirements-completed: [MCHE-02, MCHE-03]

coverage:
  - id: D1
    description: "SGPROC_HAS_MNN_LLM-gated smoke-check component with include isolation and fail-closed fallback (Task 1)"
    requirement: MCHE-02
    verification:
      - kind: unit
        ref: "commit 32ca4e1; sgprocmanagerelmruntime builds clean with gate TRUE; source-inspected gate-FALSE branch returns SMOKE_CHECK_UNAVAILABLE lambda; ElmSmokeCheck.hpp contains zero MNN includes"
        status: pass
  - id: D2
    description: "ElmModelCache publish/hit/single-flight/pin/quarantine/LRU/restart-scan implementation (Task 2)"
    requirement: MCHE-02
    verification:
      - kind: unit
        ref: "commit c110511; library builds clean; acceptance greps: getCacheDir only in CreateProductionElmModelCache, 0 set_exception calls, cap constant 15 GiB uint64"
        status: pass
  - id: D3
    description: "18-case offline cache lifecycle test matrix with gated real-MNN garbage-bundle leg (Task 3)"
    requirement: MCHE-03
    verification:
      - kind: unit
        ref: "commit c9ccff8; sgprocelmruntime_cache_test 18/18 PASSED (incl. GarbageBundleFailsRealSmokeCheck failing inside MNN load()); full standalone suite 18/18 binaries exit 0"
        status: pass

duration: 95min
completed: 2026-09-11
status: complete
---

# Phase 02 Plan 03: ElmModelCache (content-addressed model cache + smoke check) Summary

**The single materialization point landed: ElmModelCache composes 02-01's verified-manifest front door and FetchFn seam into a fail-closed acquire pipeline — single-flighted stage→verify→smoke→rename publish, size-first hit, RAII pins, .bad-<hex> quarantine, byte-capped LRU, and directory-scan restart rebuild — locked by an 18-case offline matrix including a real-MNN garbage-bundle probe.**

## Performance

- **Duration:** ~95 min
- **Started:** 2026-09-11T15:05Z
- **Completed:** 2026-09-11T16:40Z
- **Tasks:** 3/3
- **Files:** 7 (5 created, 2 modified), 1,974 insertions

## Exact Public API (for Phase 3 wiring)

```cpp
// include/elmruntime/ElmModelCache.hpp — namespace sgns::elmruntime
inline constexpr uint64_t kDefaultElmCacheByteCap = 15ULL * 1024 * 1024 * 1024; // 15 GiB (D-04)

class ElmCachePin {  // move-only RAII
public:
    ElmCachePin() = default;
    ~ElmCachePin();                       // calls cache_->ReleasePin(hashHex_)
    ElmCachePin( ElmCachePin && ) noexcept;
    ElmCachePin &operator=( ElmCachePin && ) noexcept;
    const std::string &GetDir() const;    // entry dir WITH trailing separator — feed directly to Llm::createLLM (P2-5)
    const std::string &GetHash() const;   // 64-hex manifest digest (the entry dir name)
    explicit operator bool() const;       // false after release/move
};

class ElmModelCache : public std::enable_shared_from_this<ElmModelCache> {
public:
    static outcome::result<std::shared_ptr<ElmModelCache>> Create(
        const std::string &cacheRootDir,   // "" -> CACHE_DIR_UNSET (D-03)
        FetchFn            fetch,          // D-08 seam; production = MakeFileManagerFetchFn()
        SmokeCheckFn       smokeCheck,
        uint64_t           byteCap = kDefaultElmCacheByteCap );

    static outcome::result<std::shared_ptr<ElmModelCache>> CreateProductionElmModelCache(
        SmokeCheckFn smokeCheck );         // getCacheDir()+"/elmruntime", fail-closed on empty (D-03) — the ONLY getCacheDir() call in the library

    outcome::result<ElmCachePin> Acquire( const std::string &manifestUri,
                                          const std::string &manifestHash ); // synchronous, caller's worker thread
    void SetByteCap( uint64_t byteCap );   // next eviction pass trims (RQ8)
};

// include/elmruntime/ElmSmokeCheck.hpp
using SmokeCheckFn = std::function<outcome::result<void>( const std::string &bundleDirWithTrailingSlash )>;
SmokeCheckFn MakeMnnLlmSmokeCheck();       // gated TU; ungated build -> always SMOKE_CHECK_UNAVAILABLE
```

**Phase 3 composition sketch:**
```cpp
auto cache = sgns::elmruntime::CreateProductionElmModelCache( sgns::elmruntime::MakeMnnLlmSmokeCheck() );
auto pin   = cache->Acquire( elm.get_model_manifest_uri(), elm.get_model_manifest_hash() );
if ( pin ) { MNN::Transformer::Llm::createLLM( pin.value().GetDir() ); /* pin alive for the session */ }
```

## Entry Layout

```
<cacheRootDir>/                          (production: <getCacheDir()>/elmruntime)
  <64-hex manifest digest>/              == MNN LlmConfig.base_dir (pin.GetDir())
      elm_manifest.json                  # verified manifest bytes verbatim (D-01/D-06 source)
      llm_config.json  llm.mnn  llm.mnn.weight  tokenizer.txt  [context.json]
  .tmp-<uuid>/                           # staging — swept at construction, never loaded
  .bad-<digest>/                         # quarantine — kept forever (D-07), never loaded, never counted
```

## D-01..D-08 Implementation Map

| Decision | Where |
|----------|-------|
| D-01 size-first hit | `TryHitOrPublish` hit branch: stored-manifest re-verify + `fs::file_size` vs `size_bytes` per role; **zero artifact sha256 on hit** |
| D-02 quarantine + fail | `QuarantineEntry`/`QuarantineExistingDir`: rename `.bad-<hex>` (stale quarantine removed first, P2-2), telemetry log, `CACHE_ENTRY_QUARANTINED`, no refetch in-call |
| D-03 factory fail-closed root | `CreateProductionElmModelCache`: `getCacheDir()` empty → `CACHE_DIR_UNSET`; only getCacheDir call site (grep-verified) |
| D-04 byte cap | `kDefaultElmCacheByteCap` 15 GiB + `RunEvictionPass` oldest-unpinned-first; `SetByteCap` no-op-if-lower, next pass trims |
| D-05 (02-01) | consumed — `ParseAndVerifyManifest` front door on both miss and restart paths |
| D-06 restart scan | `Create`: 64-hex regex dirs re-verified + byte-accounted + mtime-ordered; pinCount starts 0; no persisted index |
| D-07 quarantine forever | `.bad-*` ignored at scan/eviction/accounting; pre-existing quarantine never blocks re-download |
| D-08 injectable fetch | all fetches through `impl_->fetch_`; tests inject in-memory `CountingFetcher` |

## Accomplishments

- **SC-2:** bundles materialize in MNN layout via stage→verify→smoke→rename; the loadability probe (real MNN createLLM/load/1-token greedy) runs pre-rename — the gated test proves garbage dies inside `Llm::load()` with `SMOKE_CHECK_FAILED` (MNN's own error: "magic number is wrong" on the fake tokenizer)
- **SC-3:** truncate llm.mnn → `CACHE_ENTRY_QUARANTINED` → `.bad-<hex>` exists → retry acquires cleanly re-downloads → `.bad-` retained
- **SC-4:** latch-barriered two-thread race on the same hash: exactly 5 fetch calls total (1 manifest + 4 artifacts), both pins' `GetDir()` equal; different hashes proceed independently
- **SC-5:** orphaned `.tmp-` swept at construction; pinned entry survives cap pressure, released+oldest evicted on the next pass; `%TEMP%` untouched by cache code (TempDirCleanliness snapshots the temp dir)
- **Zero new dependencies; zero proto/generated/processors diffs** (grep-verified); the processor's temp-dir materializer untouched (Phase 3 deletes it)

## Task Commits

Each task committed atomically (inside `SuperGenius/SGProcessingManager` on `dev_elmruntime`):

1. **Task 1: smoke-check component (gated TU)** — `32ca4e1` (feat)
2. **Task 2: ElmModelCache implementation** — `c110511` (feat)
3. **Task 3: 18-case cache lifecycle matrix** — `c9ccff8` (test)

## Files Created/Modified

- `include/elmruntime/ElmSmokeCheck.hpp` — **new**: `SmokeCheckFn` + `MakeMnnLlmSmokeCheck`, zero MNN includes
- `src/elmruntime/ElmSmokeCheck.cpp` — **new**: gated probe (VulkanInitMutex → createLLM → set_config(greedy,1) → load → response("Hello",…,1) → destroy on all paths); ungated fail-closed stub
- `include/elmruntime/ElmModelCache.hpp` — **new**: cache + pin + factories + cap constant
- `src/elmruntime/ElmModelCache.cpp` — **new**: single-flight map, publish/hit/quarantine paths, eviction, restart scan
- `test/elmruntime/elm_model_cache_test.cpp` — **new**: 18-case matrix
- `src/elmruntime/CMakeLists.txt` — self-gate detection, both TUs, conditional `MNN::MNN Vulkan::Vulkan` PRIVATE
- `test/elmruntime/CMakeLists.txt` — `sgprocelmruntime_cache_test` registration (TIMEOUT 300, gated discovery)

## Decisions Made

See key-decisions frontmatter. Highlights: Q4 staging-cleanup resolution; A5 pre-rename smoke; normalized-declared-hash single-flight keys; restart-scan re-verification through the full front door; boost/uuid (not boost/uuids) include layout.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Boost uuid include path**
- **Found during:** Task 2 (first compile)
- **Issue:** Plan/RESEARCH specified `boost/uuids/*` headers (the A24 analog's namespace), but the vendored boost 1.85 install exposes `boost/uuid/*` — `boost/uuids/random_generator.hpp` does not exist
- **Fix:** Switched to `boost/uuid/random_generator.hpp` + `uuid.hpp` + `uuid_generators.hpp` + `uuid_io.hpp` — the exact include set `SuperGenius/src/processing/processing_tasksplit.cpp` uses; namespace `boost::uuids` is unchanged
- **Files modified:** `src/elmruntime/ElmModelCache.cpp`
- **Verification:** clean build; single-flight tests exercise the UUID staging names
- **Committed in:** `c110511`

**2. [Rule 1 - Bug] Test fixture never copied artifact URIs into the bundle**
- **Found during:** Task 3 (first run — 15/18 failed with `FETCH_FAILED` on artifact URIs)
- **Issue:** `BuildBundle` populated a local `artifacts` map but only assigned the manifest URI into `bundle.artifacts`, so the counting fetcher served nothing else
- **Fix:** `bundle.artifacts = artifacts;` before adding the manifest URI (diagnosed via a temporary map-dump printf, removed after)
- **Files modified:** `test/elmruntime/elm_model_cache_test.cpp`
- **Verification:** 18/18 green
- **Committed in:** `c9ccff8` (fixed before final commit)

**3. [Rule 1 - Bug] Hash-mismatch test tripped the size check first**
- **Found during:** Task 3
- **Issue:** The tampered model payload had a different length than the original, so the acquire failed with `ARTIFACT_SIZE_MISMATCH` (from the pre-hash size check) instead of the intended `ARTIFACT_HASH_MISMATCH`
- **Fix:** Tampered payload constructed as `std::string(original.size(), 'X')` — same size, different bytes
- **Files modified:** `test/elmruntime/elm_model_cache_test.cpp`
- **Verification:** `ARTIFACT_HASH_MISMATCH` asserted and reached
- **Committed in:** `c9ccff8`

---

**Total deviations:** 3 auto-fixed (2× Rule 1, 1× Rule 3)
**Impact on plan:** All fixes necessary for buildability/test correctness. No scope creep; no architectural changes.

## Issues Encountered

- **ctest registration gap (pre-existing):** `ctest --test-dir build/Windows/Release` reports "No tests were found" — same as 02-01/02-02; `test/elmruntime/` generates gtest-discovery cmake fragments but no `CTestTestfile.cmake` in this build tree layout. Tests were run as direct binaries (the established 02-01/02-02 pattern); the whole-binary `add_test` + `set_tests_properties(TIMEOUT 300)` registrations are in place for trees where ctest traversal works
- **One flaky-ish heuristic:** an initial full-suite sweep mis-flagged `sgprocmanagerexec_cancellation_test` as failing because its output contains "SKIPPED" (2 GPU-dependent tests skip on this host); exit-code-based re-run confirms 18/18 binaries exit 0

## Open Questions Q2/Q4 Resolutions (recorded per plan)

- **Q2 (real-model tests):** cache tests use injectable stubs only; the gated leg runs the REAL `MakeMnnLlmSmokeCheck()` against a valid-hash garbage bundle and asserts structured `SMOKE_CHECK_FAILED` from inside MNN's `load()` — proving the end-to-end probe wiring without a real model. First real model load = Phase 4 E2E
- **Q4 (staging cleanup vs quarantine):** staging failures clean up (RAII guard, no `.tmp-*` residue asserted in every failure test); quarantine reserved for reuse-time mismatch per D-02's letter — also avoids `.bad-<hash>` name collisions on retried publishes

## Verification Results

| Check | Result |
|-------|--------|
| `sgprocmanagerelmruntime` build (Release, gate TRUE) | clean, 0 errors, 0 new warnings |
| `sgprocelmruntime_cache_test` build | clean |
| `sgprocelmruntime_cache_test` direct run | **18/18 PASSED** (exit 0) |
| Gated real-MNN leg | PASSED — fails inside `Llm::load()` (tokenizer magic-number error from MNN), structured `SMOKE_CHECK_FAILED`, no final-path entry |
| `sgprocelmruntime_manifest_test` (02-01 regression) | 24/24 PASSED |
| `sgproccapability_elm_resources_test` (02-02 regression) | 18/18 PASSED |
| Full standalone suite (all test binaries) | **18/18 exit 0** |
| Scope: files changed across the 3 commits | exactly the 7 planned files |
| Zero `.proto`/`generated/`/`processors`/`processingbase`/`capability` diffs | verified via `git diff --name-only` grep (0 matches) |
| `getCacheDir()` in elmruntime | only in `CreateProductionElmModelCache` (grep) |
| `set_exception(` real calls in ElmModelCache.cpp | 0 (grep) |
| Gate-FALSE compile correctness | source inspection: all MNN references inside `#if defined(SGPROC_HAS_MNN_LLM)` |
| Submodule pointer at GeniusNetwork root | NOT bumped (verified: root `git status` clean for SuperGenius) |

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **For Phase 3 (processor):** the full acquire pipeline is callable as sketched above — `CreateProductionElmModelCache(MakeMnnLlmSmokeCheck())` at node init, `Acquire(uri, hash)` at the ELM branch, hold the pin for the session's lifetime, `GetDir()` feeds `createLLM` directly. Map `ElmRuntimeError` → `ProcessingErrorStage::RESOURCE_RESOLUTION` at the processor boundary; compose `ExtractElmResourceRequirements` + `CheckElmResources` (02-02) before Acquire
- **Temp-dir materializer deletion** (`MaterializeModelToTempDir`) is Phase 3's — untouched here
- **Generated-set isolation rule** still applies: `ElmModelCache.cpp` includes the manifest generated set; do not add root-generated includes to that TU
- No blockers

## Self-Check: PASSED

- All 3 task commits exist on `dev_elmruntime`: 32ca4e1, c110511, c9ccff8 (verified via `git log`)
- All 5 created files exist on disk; the 2 modified files tracked (verified via `git status` clean + `git diff --name-only 9f60a3a..HEAD` matching exactly the planned 7)
- All acceptance criteria re-verified post-commit (see Verification Results)

---
*Phase: 02-manifest-model-cache*
*Plan: 03*
*Completed: 2026-09-11*
