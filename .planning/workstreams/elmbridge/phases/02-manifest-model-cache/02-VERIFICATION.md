---
phase: 02-manifest-model-cache
verified: 2026-09-11T17:30:00Z
status: passed
score: 21/21 must-haves verified
overrides_applied: 0
deferred:
  - truth: "A real MNN causal-LM bundle (Qwen-0.5B-class) passes the smoke check and loads through a published cache entry (the smoke check's real-model HAPPY path)"
    addressed_in: "Phase 4"
    evidence: "Phase 4 SC-2 / E2E-01: 'A single node with an empty cache completes an assigned ELM job... downloads a Qwen-0.5B-class MNN causal-LM as billable job work'. Phase 2's tests prove the fail-closed direction (GarbageBundleFailsRealSmokeCheck — a garbage bundle fails inside real MNN load()); the passing direction requires the real model asset that Phase 4's E2E downloads."
  - truth: "CheckElmResources is called on the ELM acquire path (call-site wiring)"
    addressed_in: "Phase 3"
    evidence: "ROADMAP Phase 2 note: 'the call site lands in Phase 3's processor integration, but the validator half ships now so P3 only wires it'; 02-02 SUMMARY 'affects: Phase 3 processor (CheckElmResources call site wiring via ExtractElmResourceRequirements)'"
---

# Phase 2: Manifest & Model Cache — Verification Report

**Phase Goal:** A node can turn a manifest `uri`+`hash` into a verified, loadable MNN model bundle on disk — fail-closed, downloaded once, safely reusable
**Verified:** 2026-09-11T17:30:00Z
**Status:** passed
**Re-verification:** No — initial verification (no prior VERIFICATION.md found)

**Scope verified:** `SuperGenius/SGProcessingManager` @ `dev_elmruntime`, commits `00bea82..c9ccff8` (9 commits, 31 files, +4,436/−2 — the 2 deletions are file-header doc-comment lines in `capability_validator.cpp`, not code). Requirements: MCHE-01, MCHE-02, MCHE-03.

---

## Goal Achievement

### Observable Truths — Plan 02-01 (Manifest layer, MCHE-01)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Manifest bytes failing sha256 vs declared hash → `MANIFEST_HASH_MISMATCH`, never parsed | ✓ VERIFIED | `src/elmruntime/ElmManifest.cpp:159-171` — computed digest compared BEFORE `nlohmann::json::parse` at `:173`; test `OneFlippedByteFailsAsHashMismatchNotParse` (elm_manifest_test.cpp:157) |
| 2 | Empty/duplicate/missing-role artifacts, non-hex64 sha256, negative size_bytes, ceilings (1 MiB / 32 artifacts) → `MANIFEST_INVALID` at the gate before any fetch | ✓ VERIFIED | `ElmManifest.cpp:141-148` (1 MiB), `:186-192` (mnn-only), `:194-207` (empty/32+), `:216-241` (duplicate/closed-role/uri/negative), `:249-257` (4 required roles); non-hex64 sha256 rejects via generated constraint → mapped `MANIFEST_INVALID` (`:174-183`); 8 matching test cases pass |
| 3 | Production fetching traverses `FileManager::LoadASync` exclusively behind `FetchFn`; no raw socket/curl/httplib under `src/elmruntime/` | ✓ VERIFIED | `ElmArtifactFetcher.cpp:53-58` (sole production fetch = `LoadASync`, `save=false` always); grep `socket\|curl\|httplib\|asio::ip::tcp` over `src/elmruntime/**` → 0 hits |
| 4 | Unit tests inject in-memory/file:// FetchFn lambdas — no network/IPFS in tests | ✓ VERIFIED | elm_manifest_test.cpp:362-405 (`file://` temp fixtures through `MakeFileManagerFetchFn`); elm_model_cache_test.cpp in-memory `TestBundle` fetcher map |
| 5 | No flag/env/code path skips hash verification — no debug bypass | ✓ VERIFIED | grep `getenv\|SGPROC_ELMSKIP\|skipVerif\|bypass` over elmruntime → only doc-comments (5 hits, all comments); gate order is unconditional in `ParseAndVerifyManifest` |
| 6 | Cache-entry dir name = computed 64-lowercase-hex digest (`ComputeManifestHexDigest`); declared hash only compared, never a path component | ✓ VERIFIED | `ElmManifest.hpp:35-41` (P2-4 contract); `ElmModelCache.cpp:563-572` recomputes and double-checks `computedHex != declaredHex`; entry dir built from `declaredHex` only after `ParseAndVerifyManifest` proved computed == declared |

### Observable Truths — Plan 02-02 (Resource preflight, MCHE-01)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `required_memory_bytes` > host RAM → `UnmetRequirement{RESOURCE}` with message containing `required_memory_bytes` | ✓ VERIFIED | `capability_validator.cpp:544-553` — message `"required_memory_bytes X exceeds available host memory Y"`; test `MemoryExceeded` passes |
| 2 | Total artifact bytes > available disk → `UnmetRequirement{RESOURCE}` naming the disk shortfall | ✓ VERIFIED | `capability_validator.cpp:556-565` — `"Artifact bytes X exceed available disk space Y"`; test `DiskExceeded` passes |
| 3 | Requirement absent/0 + sufficient disk → no unmet requirements | ✓ VERIFIED | `capability_validator.cpp:544` (`requiredMemoryBytes > 0` guard); tests `GreenPathAmpleResources`, `ZeroRequirementSkipsMemoryLeg` pass |
| 4 | Query failure (field == 0) degrades to skipping that leg — never a false failure | ✓ VERIFIED | `:544` / `:557` (`snapshot.X > 0` guards, same convention as Step-4 disk); tests `DegradedMemorySkipsMemoryLeg`, `DegradedDiskSkipsDiskLeg`, `BothAxesDegradedStillGreen` pass |
| 5 | `CheckElmResources` takes plain values — no Pass, no elmruntime linkage; SGCapability links nothing new | ✓ VERIFIED | `capability_validator.hpp:98` (`uint64_t, uint64_t, callback`); `src/capability/CMakeLists.txt` untouched in phase diff (empty); extraction lives elmruntime-side in `include/elmruntime/ElmResourcePreflight.hpp:64-97` |
| 6 | `CanExecute(const sgns::Pass&, ...)` behavior byte-identical before/after | ✓ VERIFIED | `git diff 00bea82~1..c9ccff8 -- src/capability/capability_validator.cpp` → 2 deleted lines total, both file-header doc-comment (`:2-3`), zero changes inside `CanExecute`'s body |

### Observable Truths — Plan 02-03 (Model cache, MCHE-02/MCHE-03)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Miss: fetch → hash-verify → fetch all artifacts → sha256-verify each → materialize MNN layout + `elm_manifest.json` in `.tmp-<uuid>/` → smoke → atomic rename to `<root>/<hex>/` | ✓ VERIFIED | `ElmModelCache.cpp:499` (staging), `:539-548` (manifest fetch), `:551-561` (front-door gate), `:575-655` (artifact loop: size pre-check `:594`, sha256 `:606-620`, role-file write), `:658-676` (verbatim manifest store), `:678-690` (smoke), `:692-706` (stale-quarantine + rename); test `PublishHappyPath` verifies on-disk layout |
| 2 | Hit: stat each artifact vs declared `size_bytes`, NO sha256 re-hash; mismatch → `.bad-<hash>` rename + structured error, no auto-refetch in the call | ✓ VERIFIED | `ElmModelCache.cpp:403-487` — only the small stored manifest is re-verified; artifacts stat-only (`fs::file_size` `:428-440`); `QuarantineEntry` `:664-691` returns `CACHE_ENTRY_QUARANTINED` without retry; tests `HitNoRefetch`, `TamperQuarantineRetry` pass |
| 3 | Two threads Acquire-ing same hash → exactly ONE manifest+artifact fetch; both get valid pins to the same entry | ✓ VERIFIED | `ElmModelCache.cpp:326-344` (`inFlight_` map keyed by normalized hash, `shared_future`), `:346-360` (waiter joins then runs hit path); promise resolved BY VALUE `:391` (0 actual `set_exception` calls — 3 grep hits are all comments); test `SingleFlightSameHash` passes |
| 4 | Pinned entries never evicted; unpinned evict oldest-mtime-first to cap; `.bad-*`/`.tmp-*` excluded from accounting | ✓ VERIFIED | `ElmModelCache.cpp:736-739` (`pinCount > 0` skip), `:741-750` (LRU min `lastUse`), `:229-244` (`.tmp` swept / `.bad` skipped at scan — never tracked); tests `PinBlocksEvictionAndLruOrder`, `BadDirsIgnoredForever` pass |
| 5 | Restart: scan `<root>/`, LRU from dir mtimes, bytes from stored manifest, sweep `.tmp-*`, ignore `.bad-*`, pin counts zero, no persisted index file | ✓ VERIFIED | `ElmModelCache.cpp:214-285` (scan + `ParseAndVerifyManifest` re-verify + `state.pinCount = 0` `:279`); no index-file write anywhere in the TU; test `RestartRebuildHitsWithZeroFetches` passes |
| 6 | Artifact sha256 fail at publish → `ARTIFACT_HASH_MISMATCH`, staging removed, NO final-path entry | ✓ VERIFIED | RAII `StagingGuard` destructor `ElmModelCache.cpp:509-526` (runs on every abort); test `ArtifactHashMismatchLeavesNoEntry` asserts no entry + no `.tmp-*` remain |
| 7 | Smoke check (createLLM + load + 1-token greedy) runs pre-rename against staging; without `SGPROC_HAS_MNN_LLM` entries never usable | ✓ VERIFIED | Called at `:678-690` BEFORE rename `:698`; `ElmSmokeCheck.cpp:8` gate — entire MNN surface inside `#if defined(SGPROC_HAS_MNN_LLM)`, ungated branch `:106-118` always fails `SMOKE_CHECK_UNAVAILABLE`; `ElmSmokeCheck.hpp` contains zero MNN includes; tests `SmokeCheckFailsLeavesNoEntry` + gated `GarbageBundleFailsRealSmokeCheck` (real MNN load failure) pass |
| 8 | Acquire/pin-release terminal paths on caller's thread; `enable_shared_from_this`; future callbacks capture `weak_from_this` | ✓ VERIFIED | `ElmModelCache.hpp:88` (`class ElmModelCache : public std::enable_shared_from_this<ElmModelCache>`); `Acquire` is synchronous (no posted callbacks in v1); factory-then-wrap construction `ElmModelCache.cpp:200-206` (Pitfall 15.1 discipline) |
| 9 | `CreateProductionElmModelCache()` fails on empty `getCacheDir()` — never guesses | ✓ VERIFIED | `ElmModelCache.cpp:307-325` — empty/throwing `getCacheDir()` → `CACHE_DIR_UNSET`; only `getCacheDir()` call in the library; `Create("")` also fails closed `:186-196`; tests `EmptyRootFailsClosed` passes |

**Score:** 21/21 truths verified

### Deferred Items (not gaps — scheduled later in the milestone)

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Real-model happy path through the smoke check + cache (Qwen-0.5B-class) | Phase 4 | SC-2/E2E-01: "downloads a Qwen-0.5B-class MNN causal-LM as billable job work"; Phase 2 proves the fail-closed direction only (by design — garbage-bundle leg) |
| 2 | `CheckElmResources` call-site wiring on the acquire path | Phase 3 | ROADMAP Phase 2 note: "the call site lands in Phase 3's processor integration, but the validator half ships now so P3 only wires it" |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gnus-processing-schema.json` defs | ElmModelManifest/Artifact/Runtime | ✓ VERIFIED | :175, :202, :241 — required arrays, role pattern, hex64 pattern, `^mnn$` string (not enum), `required_memory_bytes` |
| `generated/elmruntime-manifest/*` (A1 fallback set) | Self-contained quicktype output, zero hand edits | ✓ VERIFIED | 6 files, +565 lines, all under the new subdir; root `generated/` byte-identical (phase diff on `generated/` shows only the new subdir — `ModelFormat.hpp` untouched) |
| `include/elmruntime/ElmRuntimeError.hpp` | 11-value enum + category | ✓ VERIFIED | :19-31 all 11 values; declare/define split with `OUTCOME_CPP_DEFINE_CATEGORY_3` in `ElmRuntimeError.cpp` (link-clean, builds) |
| `include/elmruntime/ElmManifest.hpp` / `ElmManifest.cpp` | Digest/parse/gates/role-map/total | ✓ VERIFIED | All four functions + 2 ceilings; substantive (gates at :141-257); consumed by cache + tests |
| `include/elmruntime/ElmArtifactFetcher.hpp` / `.cpp` | `FetchFn` + `MakeFileManagerFetchFn` | ✓ VERIFIED | :23 typedef, :35 factory; `LoadASync` + per-call `ioc->reset(); ioc->run()` drain `:66-67`; `range_error` → `FETCH_FAILED` conversion |
| `src/elmruntime/CMakeLists.txt` | `sgprocmanagerelmruntime` static lib + self-gate | ✓ VERIFIED | :23 lib target; :16-21 own `EXISTS "${MNN_INCLUDE_DIR}/llm/llm.hpp"` detection; :81-84 conditional `SGPROC_HAS_MNN_LLM` def + `MNN::MNN Vulkan::Vulkan` PRIVATE |
| `test/elmruntime/elm_manifest_test.cpp` | ≥200-line rejection matrix | ✓ VERIFIED | 405 lines committed, 24 cases, binary exit 0 |
| `include/capability/capability_types.hpp` | `availableMemoryBytes` field | ✓ VERIFIED | :65, same degraded-0 doc convention as disk; populated at `capability_validator.cpp:271` |
| `include/capability/capability_validator.hpp` + `.cpp` | `CheckElmResources` + `QueryAvailableMemoryBytes` | ✓ VERIFIED | hpp:98 declaration; cpp:124-139 both platform branches (`GlobalMemoryStatusEx`/`sysconf`), 0 on failure |
| `include/elmruntime/ElmResourcePreflight.hpp` | Extraction bridge (fallback for dropped overload) | ✓ VERIFIED | :64-97 header-only; clamps negatives; materializes by-value optionals |
| `test/capability/elm_resources_test.cpp` (+ `elm_resource_extraction_test.cpp`) | ≥120-line mock-snapshot matrix | ✓ VERIFIED | Two-TU pattern (generated-set isolation); 11 + 7 = 18 cases, binary exit 0 |
| `include/elmruntime/ElmSmokeCheck.hpp` / `.cpp` | Gated probe, include isolation, fail-closed fallback | ✓ VERIFIED | Header zero MNN includes; TU sequence VulkanInitMutex → createLLM → set_config(greedy,1) → load → response("Hello",…,1) → destroy on ALL paths |
| `include/elmruntime/ElmModelCache.hpp` / `.cpp` | Cache core ≥250 lines | ✓ VERIFIED | 839 lines; Acquire/Create/factories/pin RAII/SetByteCap all present and wired |
| `test/elmruntime/elm_model_cache_test.cpp` | ≥300-line lifecycle matrix | ✓ VERIFIED | 748 lines committed, 18 cases incl. restart/pin-evict/tmp-sweep/temp-cleanliness/single-flight/concurrency, binary exit 0 |

### Key Link Verification

| From | To | Via | Status | Evidence |
|------|----|----|--------|----------|
| schema definitions | generated types | quicktype pipeline (A1 fallback invocation) | ✓ WIRED | `ElmManifest.hpp:18` quoted include of `elmruntime-manifest/ElmModelManifest.hpp`; root set byte-identical |
| `ParseAndVerifyManifest` | `sgprocmanagersha::sha256` | one-shot EVP hash | ✓ WIRED | `ElmManifest.cpp:118` (`ComputeManifestHexDigest` body) |
| `MakeFileManagerFetchFn` | `FileManager::LoadASync` + ioc drain | per-call io_context on caller thread | ✓ WIRED | `ElmArtifactFetcher.cpp:53-67` |
| `BuildSnapshot` | `QueryAvailableMemoryBytes` | snapshot population | ✓ WIRED | `capability_validator.cpp:271` |
| `CheckElmResources` | `UnmetRequirement{RESOURCE,…}` | Step-4 idiom | ✓ WIRED | `capability_validator.cpp:548, :559` |
| `ElmModelCache::Acquire` | `ParseAndVerifyManifest`/`ComputeManifestHexDigest`/`RoleFileName` | verified-manifest front door | ✓ WIRED | `ElmModelCache.cpp:552, :566, :414/:626` |
| `Acquire` miss path | `FetchFn` (production `MakeFileManagerFetchFn`) | D-08 seam | ✓ WIRED | `ElmModelCache.cpp:540, :586`; `CreateProductionElmModelCache` `:322` |
| publish path | `SmokeCheckFn(stagingDir)` | pre-rename gate | ✓ WIRED | `ElmModelCache.cpp:679` |
| `ElmCachePin` dtor | `ElmModelCache::ReleasePin` | refcount + LRU refresh | ✓ WIRED | `ElmModelCache.cpp:165-170` → `:809-823` |

### Data-Flow Trace (Level 4)

Not applicable in the render sense — this phase is a library, not a UI. Equivalent trace performed: cache entries are populated exclusively from `FetchFn` bytes hash-verified against manifest-declared digests (`ElmModelCache.cpp:606-620`); tests inject real bytes and assert on-disk file contents, so no hardcoded/hollow data path exists. The hit path consumes the stored `elm_manifest.json` written verbatim at publish (`:658-676`) — data flows end-to-end.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Manifest matrix | run `sgprocelmruntime_manifest_test.exe` | exit=0, 24 OK, 0 FAILED | ✓ PASS |
| Resource preflight matrix | run `sgproccapability_elm_resources_test.exe` | exit=0, 18 OK, 0 FAILED | ✓ PASS |
| Cache lifecycle matrix | run `sgprocelmruntime_cache_test.exe` | exit=0, 18 OK, 0 FAILED | ✓ PASS |

(Re-executed by the verifier in its own process — not relying on the orchestrator's post-wave gate claim. Case counts match the SUMMARYs exactly: 24 / 18 / 18.)

### Probe Execution

SKIPPED — no `probe-*.sh` scripts declared in any PLAN or SUMMARY; verification is via GTest binaries (above).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MCHE-01 | 02-01, 02-02, 02-03 | Manifest hash-verified, artifacts sha256-verified, fail-closed, quarantine on failure, no bypass | ✓ SATISFIED (layer scope) | Front-door gate `ElmManifest.cpp:141-257`; per-artifact sha256 `ElmModelCache.cpp:606-620`; quarantine `:664-691`; no bypass (grep-clean). Node-level invocation wiring is Phase 3 (by roadmap design — Phase 2 ships entirely in SGProcessingManager) |
| MCHE-02 | 02-03 | Content-addressed cache `cache/<manifest-hash>/`, MNN layout, pin-while-processing, verify-before-reuse | ✓ SATISFIED | Entry layout + publish/hit/pin paths (`ElmModelCache.cpp:397-706`); production root = `getCacheDir()/elmruntime` (`:322`); `PublishHappyPath`/`HitNoRefetch`/`PinBlocksEvictionAndLruOrder` pass |
| MCHE-03 | 02-03 | Single-flight, partial-download recovery, LRU eviction, smoke check after publish | ✓ SATISFIED | Single-flight `:326-360` + `SingleFlightSameHash`; `.tmp` sweep + restart rebuild `:214-285` + `TmpOrphanSweepedAtConstruction`/`RestartRebuildHitsWithZeroFetches`; LRU `:719-806`; pre-rename smoke `:678-690` |

Orphaned requirements: none — REQUIREMENTS.md maps exactly MCHE-01/02/03 to Phase 2, and all three appear in PLAN frontmatter (`requirements:` fields).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| test/capability/elm_resource_extraction_test.cpp | 39 | "placeholder" in a doc comment | ℹ️ Info | Describes legitimate test data (any 64-hex value works — extraction never hashes); not a stub |

No TODO/FIXME/XXX/TBD/HACK markers in any phase file. No empty-return stubs. No debug bypass paths.

### Human Verification Required

None. All phase-scope success criteria are covered by executable code + passing tests. The two items beyond automated reach (real-model happy path; acquire-path call-site wiring) are explicitly scheduled Phase 3/4 work — recorded under Deferred Items, not gaps.

### Gaps Summary

No gaps. All 21 truths, 15 artifacts, and 9 key links verified against source with independently re-executed test evidence (60/60 cases, exit 0). The phase goal — turn a manifest `uri`+`hash` into a verified, loadable MNN bundle on disk, fail-closed, downloaded once, safely reusable — is achieved at the library scope the roadmap assigns to Phase 2.

### Deviations Recorded in SUMMARYs (informational — no gap, but Phase 3 must consume these)

1. **Dual generated sets (02-01 A1 fallback — HIGHEST Phase 3 relevance):** quicktype drops root-unreachable definitions, so manifest types live in `generated/elmruntime-manifest/` while the root `generated/` set (PassType, ModelConfig, etc.) is unchanged. **Both sets define `sgns::ClassMemberConstraints` and `sgns::ElmType` under per-file `#pragma once` guards — one TU including both is a class-redefinition error.** The Phase 3 processor TU (which needs Pass/processor types AND manifest/cache types) must respect the established "generated-set isolation" pattern: bridge via plain values (`ElmResourcePreflight.hpp` precedent) or split TUs (`elm_resources_test.cpp` + `elm_resource_extraction_test.cpp` precedent). `ElmModelCache`'s public API is deliberately manifest-type-free (`Acquire(uri, hash)`, pin returns a dir string), so the processor can use the cache without touching the fallback set in the same TU as Pass types.
2. **Plain-values `CheckElmResources` only (02-02 sanctioned fallback):** the manifest-typed overload was dropped (guaranteed redefinition error, per #1). Phase 3 composes `sgns::elmruntime::ExtractElmResourceRequirements(manifest)` → `CheckElmResources(uint64_t, uint64_t, cb)`.
3. **Quarantine semantics (02-03, Q4/D-02):** publish-time failures CLEAN UP staging (no `.bad-`); `.bad-<hash>` quarantine is reserved for reuse-time mismatches. Quarantining replaces prior `.bad-` evidence (keeps latest). SC-3's substance (refusal, no livelock, clean re-download) holds — `TamperQuarantineRetry` proves the loop.
4. **Exact-fit is green:** both resource legs use strict `>` (requirement == availability passes), mirroring the GPU-heap check.
5. **Negative int64 values clamp to 0 at extraction** (`ElmResourcePreflight.hpp:84-90`) — schema numeric bounds don't survive codegen.
6. **`model_format` is a string, not an enum** — deliberate collision avoidance with the live `sgns::ModelFormat`; the C++ gate enforces `== "mnn"`.

---

_Verified: 2026-09-11T17:30:00Z_
_Verifier: the agent (gsd-verifier)_
