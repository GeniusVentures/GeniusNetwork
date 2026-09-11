---
phase: 02-manifest-model-cache
plan: 01
subsystem: elmruntime
tags: [elm, manifest, sha256, quicktype, mnn, filemanager, fetch-seam, sgprocessingmanager]

requires:
  - phase: 01-elm-job-model-funding
    provides: ELM job schema (model_manifest_uri/model_manifest_hash fields), sgns::ElmType, quicktype pipeline + regen conventions, test-matrix patterns
provides:
  - "Schema definitions ElmModelManifest/ElmModelArtifact/ElmModelRuntime (gnus-processing-schema.json + dedicated elm-model-manifest-schema.json generation source)"
  - "Generated manifest types in generated/elmruntime-manifest/ (self-contained quicktype output)"
  - "sgns::elmruntime::ElmRuntimeError — 11-value fail-closed error category (A26 standalone)"
  - "ElmManifest free functions: ComputeManifestHexDigest / ParseAndVerifyManifest / RoleFileName / TotalArtifactBytes + kMaxManifestBytes/kMaxArtifacts ceilings"
  - "sgns::elmruntime::FetchFn injectable seam + MakeFileManagerFetchFn production factory (D-08)"
  - "sgprocmanagerelmruntime static library target (innermost-first, committed in SGProcessingManager on dev_elmruntime)"
  - "sgprocelmruntime_manifest_test — 24-case verification matrix, all green"
affects: [02-02 (CheckElmResources consumes TotalArtifactBytes + runtime block), 02-03 (ElmModelCache consumes ParseAndVerifyManifest + FetchFn + digest-as-dir-name), Phase 3 processor (maps ElmRuntimeError at RESOURCE_RESOLUTION)]

tech-stack:
  added: []  # D-003: zero new dependencies — quicktype 23.2.6 + node 24.16.0 pre-installed, all libs pre-existing
  patterns:
    - "hash-verify-before-parse front door (SC-1): sha256 gate precedes any JSON parse call in source order"
    - "outcome category declare/define split: OUTCOME_HPP_DECLARE_ERROR_2 in header + OUTCOME_CPP_DEFINE_CATEGORY_3 in exactly one TU (macro emits non-inline externals — cannot live in a multi-TU header)"
    - "injectable FetchFn seam with a single production implementation (FileManager::LoadASync + per-call io_context drained on the calling thread)"
    - "role-to-fixed-filename mapping (manifest name is a ROLE, never a path; T-02-01-02)"
    - "SGPROC_TEST_DISCOVERY-gated per-case discovery + whole-binary add_test fallback (Phase 1 pattern, verbatim)"

key-files:
  created:
    - SuperGenius/SGProcessingManager/elm-model-manifest-schema.json
    - SuperGenius/SGProcessingManager/generated/elmruntime-manifest/{ElmModelManifest.hpp, ElmModelArtifact.hpp, ElmModelRuntime.hpp, ElmType.hpp, Generators.hpp, helper.hpp}
    - SuperGenius/SGProcessingManager/include/elmruntime/{ElmRuntimeError.hpp, ElmManifest.hpp, ElmArtifactFetcher.hpp}
    - SuperGenius/SGProcessingManager/src/elmruntime/{ElmRuntimeError.cpp, ElmManifest.cpp, ElmArtifactFetcher.cpp, CMakeLists.txt}
    - SuperGenius/SGProcessingManager/test/elmruntime/{elm_manifest_test.cpp, CMakeLists.txt}
  modified:
    - SuperGenius/SGProcessingManager/gnus-processing-schema.json
    - SuperGenius/SGProcessingManager/src/CMakeLists.txt
    - SuperGenius/SGProcessingManager/test/CMakeLists.txt

key-decisions:
  - "A1 fallback FIRED: quicktype drops definitions unreachable from root properties, so ElmModelManifest types generate from a dedicated elm-model-manifest-schema.json via a second invocation of the same pipeline (D-05 preserved: one pipeline, zero hand edits); definitions kept in gnus-processing-schema.json as shape documentation"
  - "Fallback output isolated under generated/elmruntime-manifest/ so its helper.hpp/ElmType.hpp cannot clobber the root generated/ shared files; root set regenerates byte-identical"
  - "model_format is a pattern-constrained STRING, not an enum — sgns::ModelFormat is a live 4-member enum with 5+ consumers; the string generates get_model_format() -> const std::string& with zero collision risk (verified: git diff generated/ModelFormat.hpp EMPTY)"
  - "Error category split declare/define (Rule 1 fix): plan's single-header OUTCOME_CPP_DEFINE_CATEGORY_3 placement violates the macro's contract — moved to ElmRuntimeError.cpp per ProcessingManager.hpp:290 precedent"
  - "ResultType stored via std::optional in MakeFileManagerFetchFn (outcome::result default ctor is deleted)"
  - "Required roles = exactly {llm_config, llm_model, llm_weight, tokenizer_file} (MNN Llm::load() checks all four unconditionally); context_file optional"

patterns-established:
  - "elmruntime library layout: include/elmruntime + src/elmruntime, namespace sgns::elmruntime, STATIC lib with PUBLIC logger/sha/nlohmann/spdlog + PRIVATE AsyncIOManager"
  - "Offline production-fetch testing: file:// temp fixtures through MakeFileManagerFetchFn — no network, no IPFS"

requirements-completed: [MCHE-01]

coverage:
  - id: D1
    description: "Manifest schema definitions + quicktype regen with A1 fallback (Task 1)"
    requirement: MCHE-01
    verification:
      - kind: unit
        ref: "commit 00bea82 acceptance checks: grep ElmModelManifest in schema + generated/; git diff generated/ModelFormat.hpp empty"
        status: pass
  - id: D2
    description: "sgprocmanagerelmruntime library skeleton: error category, hash-verify-before-parse manifest gates, FetchFn + FileManager production wiring (Task 2)"
    requirement: MCHE-01
    verification:
      - kind: unit
        ref: "cmake --build ... --target sgprocmanagerelmruntime (clean); ElmManifestTest/ElmManifestFetcherTest suites"
        status: pass
  - id: D3
    description: "24-case manifest rejection matrix + offline production-fetch tests, registered with gated discovery + TIMEOUT 120 (Task 3)"
    requirement: MCHE-01
    verification:
      - kind: unit
        ref: "sgprocelmruntime_manifest_test 24/24 PASSED; full standalone suite 16/16 binaries exit 0"
        status: pass

duration: 55min
completed: 2026-09-11
status: complete
---

# Phase 02 Plan 01: Manifest Layer (elmruntime skeleton) Summary

**MCHE-01's fail-closed front door landed: manifest bytes are sha256-verified against the declared hash BEFORE parsing, semantically gated (mnn-only, closed role set, 4 required roles, DoS ceilings), and production fetch is FileManager-exclusive behind an injectable FetchFn — all locked by a 24-case test matrix.**

*(Continuation note: Task 1 was committed by a prior executor (00bea82). This run verified/fixed the Task 2 drafts, built, and committed them (0ea9f68), then executed Task 3 in full (e80dc46).)*

## Performance

- **Duration:** ~55 min (this continuation session)
- **Tasks:** 3/3 complete
- **Files:** 19 files across 3 commits (1,752 insertions)

## Accomplishments

- **A1 fallback fired and resolved** (Task 1, prior session): manifest types generate from dedicated `elm-model-manifest-schema.json` because quicktype drops definitions unreachable from root properties; root regen side-effect-free.
- **elmruntime library builds standalone** (Task 2): `sgprocmanagerelmruntime` STATIC — error category, manifest gates, FetchFn seam + `MakeFileManagerFetchFn`.
- **24-case test matrix green** (Task 3): every rejection path returns the structured `ElmRuntimeError`; offline `file://` production-fetch round-trip + `range_error` conversion proven.
- **Zero regressions:** full standalone build clean; all 16 test binaries exit 0.

## Task Commits

1. **Task 1: schema + regen (A1 fallback)** — `00bea82` (feat; prior executor)
2. **Task 2: elmruntime library skeleton** — `0ea9f68` (feat)
3. **Task 3: rejection-matrix + fetch tests** — `e80dc46` (test)

All in `SuperGenius/SGProcessingManager` on `dev_elmruntime` (innermost-first; no submodule pointer bump, per plan).

## Actual Generated Type Spellings (interface handoff for 02-03)

From `generated/elmruntime-manifest/ElmModelManifest.hpp` (the A1-fallback set — self-contained, do NOT mix with root `generated/` headers in one TU):

```cpp
namespace sgns {
class ElmModelManifest {
    const std::vector<ElmModelArtifact> & get_artifacts() const;
    const ElmType & get_elm_type() const;                 // reuses sgns::ElmType::CAUSAL_LM
    const std::string & get_model_format() const;         // STRING, not enum (live sgns::ModelFormat untouched)
    boost::optional<std::string> get_quantization() const;      // by value — materialize before use
    boost::optional<ElmModelRuntime> get_runtime() const;       // by value — materialize before use
    const int64_t & get_schema_version() const;           // constraint (1,1) SURVIVED codegen
};
class ElmModelArtifact {
    const std::string & get_name() const;                 // ROLE, never a path
    const std::string & get_uri() const;
    const std::string & get_sha256() const;               // pattern ^[0-9a-fA-F]{64}$ enforced at parse
    const int64_t & get_size_bytes() const;               // minimum-0 did NOT survive; C++ gate re-checks
};
class ElmModelRuntime {
    boost::optional<int64_t> get_required_memory_bytes() const; // bound did NOT survive; 02-02 gate re-checks
};
}
```

The root regen (`gnus-processing-schema.json` → `SGNSProcMain.hpp`) emitted **nothing** for the manifest definitions (unreachable from root) — `generated/ModelFormat.hpp`, `Generators.hpp`, `SGNSProcMain.hpp`, `SgnsProcessing.hpp` all byte-identical; Phase 1 types unchanged; `gnus_spec_version (1,1)` intact.

## Exact ElmManifest / FetchFn Public Signatures

`include/elmruntime/ElmManifest.hpp` — `namespace sgns::elmruntime`:

```cpp
inline constexpr size_t kMaxManifestBytes = 1024 * 1024;  // 1 MiB
inline constexpr size_t kMaxArtifacts     = 32;

std::string ComputeManifestHexDigest( const std::vector<uint8_t> &bytes );  // 64 lowercase hex; IS the cache dir name (P2-4)
outcome::result<sgns::ElmModelManifest> ParseAndVerifyManifest(
    const std::vector<uint8_t> &bytes, const std::string &declaredHash );
const char *RoleFileName( const std::string &role );  // llm_config→"llm_config.json", llm_model→"llm.mnn",
                                                      // llm_weight→"llm.mnn.weight", tokenizer_file→"tokenizer.txt",
                                                      // context_file→"context.json", unknown→nullptr
uint64_t TotalArtifactBytes( const sgns::ElmModelManifest &manifest );
```

`include/elmruntime/ElmArtifactFetcher.hpp`:

```cpp
using FetchFn = std::function<outcome::result<std::vector<uint8_t>>( const std::string &uri )>;
FetchFn MakeFileManagerFetchFn();
```

Error codes (`sgns::elmruntime::ElmRuntimeError`, 11 values): `FETCH_FAILED, MANIFEST_FETCH_FAILED, MANIFEST_HASH_MISMATCH, MANIFEST_INVALID, ARTIFACT_FETCH_FAILED, ARTIFACT_HASH_MISMATCH, ARTIFACT_SIZE_MISMATCH, CACHE_DIR_UNSET, CACHE_ENTRY_QUARANTINED, SMOKE_CHECK_FAILED, SMOKE_CHECK_UNAVAILABLE`.

## ParseAndVerifyManifest Gate Order (SC-1)

1. `bytes.size() <= kMaxManifestBytes` else `MANIFEST_INVALID`
2. declaredHash normalize: optional `sha256:` prefix, exactly 64 hex (case-insensitive) else `MANIFEST_INVALID`
3. **computed digest == declared (lowercased) else `MANIFEST_HASH_MISMATCH` — BEFORE any parse** (source order verified: hash at :138, parse at :149)
4. nlohmann parse + generated `from_json` (constraint throws → `MANIFEST_INVALID`)
5. Semantic gates (each log-then-fail): `model_format == "mnn"`; non-empty artifacts; `<= kMaxArtifacts`; unique names; names ∈ closed 5-role set; required {llm_config, llm_model, llm_weight, tokenizer_file} all present; non-empty uri; `size_bytes >= 0`

## Files Created/Modified

- `SuperGenius/SGProcessingManager/gnus-processing-schema.json` — +3 definitions (shape documentation)
- `SuperGenius/SGProcessingManager/elm-model-manifest-schema.json` — generation source (A1 fallback)
- `SuperGenius/SGProcessingManager/generated/elmruntime-manifest/*` — 6 quicktype outputs (zero hand edits)
- `SuperGenius/SGProcessingManager/include/elmruntime/*` — 3 public headers
- `SuperGenius/SGProcessingManager/src/elmruntime/*` — 3 TUs + CMakeLists
- `SuperGenius/SGProcessingManager/src/CMakeLists.txt` — `add_subdirectory(elmruntime)` after `processors`
- `SuperGenius/SGProcessingManager/test/elmruntime/*` — 24-case test + gated CMakeLists
- `SuperGenius/SGProcessingManager/test/CMakeLists.txt` — registration

## Decisions Made

See `key-decisions` frontmatter. Highlights: A1 fallback with isolated output dir; string-not-enum `model_format`; category declare/define split; `std::optional` for `ResultType`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] `OUTCOME_CPP_DEFINE_CATEGORY_3` placed in a header by the prior draft**
- **Found during:** Task 2 review (before build)
- **Issue:** The macro emits non-inline external definitions (`make_error_code`, `Category<Enum>::toString`); in a header included by 3+ TUs it causes LNK2005 duplicate symbols. The macro's own contract (`outcome-register.hpp:88`) mandates file level in a .cpp.
- **Fix:** Split per repo precedent (`ProcessingManager.hpp:290` + `.cpp:13`): `OUTCOME_HPP_DECLARE_ERROR_2` in the header, `OUTCOME_CPP_DEFINE_CATEGORY_3` in new `src/elmruntime/ElmRuntimeError.cpp`. (Plan's acceptance criterion listed the macro "in ElmRuntimeError.hpp" — satisfied by the declare half + the dedicated TU.)
- **Files:** `include/elmruntime/ElmRuntimeError.hpp`, `src/elmruntime/ElmRuntimeError.cpp` (new)
- **Verification:** clean build + 24/24 tests
- **Committed in:** `0ea9f68`

**2. [Rule 1 — Bug] `IsValidRole` matched filenames as roles**
- **Found during:** Task 2 draft review
- **Issue:** First loop iterated all `kRoleFilenames` entries (roles AND filenames interleaved), so `"llm.mnn"` would pass the closed-role gate — exactly the path-confusion T-02-01-02 mitigates.
- **Fix:** Compare only even indexes (roles); test-locked by `UnknownRoleNameRejects` + `RoleFileName("llm.mnn") == nullptr`.
- **Committed in:** `0ea9f68`

**3. [Rule 1 — Bug] `FileManager::ResultType` default-constructed (deleted ctor)**
- **Found during:** Task 2 build
- **Issue:** C2280 — `outcome::result`'s default constructor is deleted.
- **Fix:** Hold in `std::optional<FileManager::ResultType>`; also added missing `<condition_variable>`, `<string_view>`, `<optional>` includes.
- **Committed in:** `0ea9f68`

**4. [Rule 3 — Blocking] libp2p include not propagated to test consumers**
- **Found during:** Task 3 build
- **Issue:** elmruntime's public headers include `<outcome/sgprocmgr-outcome.hpp>` → `<libp2p/outcome/outcome.hpp>`; the library target didn't expose `${libp2p_INCLUDE_DIR}` (it only resolved transitively via PRIVATE AsyncIOManager inside the library TU).
- **Fix:** PUBLIC include entry, same propagation as `sgprocmanagertypes` (`src/util/CMakeLists.txt:67`).
- **Files:** `src/elmruntime/CMakeLists.txt`
- **Committed in:** `e80dc46`

**5. [Task 3 polish] MSVC specifics in tests**
- `std::tmpnam` → `std::filesystem::temp_directory_path` (deprecated + unsafe); `std::remove(const std::string&)` ambiguity → `std::filesystem::remove(path, ec)`; added `<cctype>`/`<algorithm>`.
- **Committed in:** `e80dc46`

**Total deviations:** 5 auto-fixed (3× Rule 1, 1× Rule 3, 1× polish)
**Impact on plan:** All fixes required for correctness/buildability; no scope change.

## Issues Encountered

- **ctest "No tests were found" in this build tree** — same pre-existing condition Phase 1 documented (`01-01-SUMMARY.md`): the local standalone tree lacks root-level `enable_testing()`/`BUILD_TESTING` cache entry, so no root `CTestTestfile.cmake` is generated. Ran all 16 test binaries directly (all exit 0). The `add_test`/discovery registration is correct for CI standalone builds — not a defect introduced by this plan; recorded for continuity.

## Test Results (full record)

`sgprocelmruntime_manifest_test`: **24/24 PASSED** in 7 ms —

- ValidManifestParsesAndTotalsBytes, Sha256PrefixAndUppercaseHashNormalizes, ContextFileExtraRoleIsFine, QuantizationAndRuntimeOptionalBlocksParse
- OneFlippedByteFailsAsHashMismatchNotParse (proves verify-before-parse: truncated JSON + different-bytes hash → HASH_MISMATCH, not parse error), DeclaredHashNotHex64Rejects, DeclaredHashWithBadCharsetRejects, EmptyDeclaredHashRejects
- ModelFormatOnnxRejects, EmptyArtifactsArrayRejects, OverCeilingArtifactCountRejects, DuplicateRoleRejects, MissingRequiredRoleRejects, UnknownRoleNameRejects, ArtifactSha256NotHex64Rejects, NegativeSizeBytesRejects, EmptyUriRejects, OversizedManifestBytesReject, MalformedJsonRejectsAfterHashVerifies
- RoleFileNameMapsAllFiveRoles, DigestIs64LowercaseHex (pinned to known sha256("abc"))
- FileUriRoundTripsBytes (file:// temp fixture), NonexistentFileFailsWithFetchFailed, UnregisteredPrefixConvertsThrowToFetchFailed (bogus:// range_error → FETCH_FAILED)

Full standalone suite (run directly): **16/16 binaries exit 0** — artifact_serializer (15), capability_validator (12), capture_smoke (1), diff_utils (21), mnn_llm (2), mnn_tensor_fp4 (5), quantization (24), sgprocbase_elm_job_schema (27), **sgprocelmruntime_manifest (24)**, execution: budget (3), cancellation (2, 2 skipped-by-design), checkpoint (2), leak (2), migration (2), progress (5), timeout (3).

## User Setup Required

None — no external configuration.

## Next Phase Readiness

- **02-02** can consume `TotalArtifactBytes(manifest)` + the `runtime.required_memory_bytes` block (re-check `>= 0` — the bound did not survive codegen) for `CheckElmResources`/`QueryAvailableMemoryBytes`.
- **02-03** composes `ParseAndVerifyManifest` + `FetchFn`/`MakeFileManagerFetchFn` + `ComputeManifestHexDigest` (dir name) into `ElmModelCache`; artifact gates `ARTIFACT_HASH_MISMATCH`/`ARTIFACT_SIZE_MISMATCH` and `CACHE_DIR_UNSET`/`CACHE_ENTRY_QUARANTINED`/`SMOKE_CHECK_*` are already defined and mapped.
- Include-order caution (recorded in ElmManifest.hpp): the fallback generator set is self-contained — include via `"elmruntime-manifest/..."` quoted paths only; never mix with root `generated/` helper.hpp in one TU.
- `SGPROC_HAS_MNN_LLM` ordering (elmruntime after processors in `src/CMakeLists.txt`) is in place for 02-03's gated MNN work.

## Self-Check: PASSED

- [x] Commits `00bea82`, `0ea9f68`, `e80dc46` present on `dev_elmruntime` in SuperGenius/SGProcessingManager
- [x] All key files exist on disk
- [x] 24/24 manifest tests green; 16/16 suite binaries exit 0
- [x] Zero `.proto` diffs; zero hand edits under `generated/` (fallback output committed as generated by quicktype)
- [x] `git status` clean; scope exactly schema + fallback schema + generated fallback set + elmruntime sources/CMake/tests + two CMakeLists registrations

---
*Phase: 02-manifest-model-cache (elmbridge) — Plan 01*
*Completed: 2026-09-11*
