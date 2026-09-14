---
phase: 04-grid-integration-e2e-proof
plan: 01
subsystem: testing
tags: [json-schema, quicktype, codegen, mnn, manifest, envelope, settlement]

requires:
  - phase: 02-manifest-model-cache
    provides: closed role set, RoleFileName table, manifest verification front door
  - phase: 03-elm-processor
    provides: six-key ElmEnvelope, processor conformance fixture seam
provides:
  - ElmGeneration.stop schema property + regenerated get_stop/set_stop (boost::optional<std::vector<std::string>>)
  - embedding_file optional manifest role end-to-end (schema pattern, RoleFileName -> embeddings_bf16.bin, fixture, tests)
  - ElmEnvelope settlement stamps grab_time_usec/finish_time_usec (D-04) always emitted in JSON
  - Retired Phase 3 post-Acquire embedding injection workaround
  - SGProcessors -> sgprocmanagerelmruntime PUBLIC link closure (standalone-build blocker fixed)
affects: [04-02 worker routing, 04-04 settlement, 04-05 e2e]

tech-stack:
  added: []
  patterns:
    - "Additive envelope keys: new fields default 0 and serialize ALWAYS so downstream settlement never branches on presence"

key-files:
  created: []
  modified:
    - SuperGenius/SGProcessingManager/gnus-processing-schema.json
    - SuperGenius/SGProcessingManager/elm-model-manifest-schema.json
    - SuperGenius/SGProcessingManager/generated/ElmGeneration.hpp
    - SuperGenius/SGProcessingManager/generated/Generators.hpp
    - SuperGenius/SGProcessingManager/generated/elmruntime-manifest/ElmModelArtifact.hpp
    - SuperGenius/SGProcessingManager/include/elmruntime/ElmEnvelope.hpp
    - SuperGenius/SGProcessingManager/src/elmruntime/ElmEnvelope.cpp
    - SuperGenius/SGProcessingManager/src/elmruntime/ElmManifest.cpp
    - SuperGenius/SGProcessingManager/src/processors/CMakeLists.txt
    - SuperGenius/SGProcessingManager/test/fixtures/elm-test-model/elm_manifest.json
    - SuperGenius/SGProcessingManager/test/fixtures/README.md
    - SuperGenius/SGProcessingManager/test/elmruntime/elm_manifest_test.cpp
    - SuperGenius/SGProcessingManager/test/elmruntime/elm_envelope_test.cpp
    - SuperGenius/SGProcessingManager/test/processors/elm_processor_test.cpp

key-decisions:
  - "D-01/D-02 schema half landed: stop array (max 4, items 1-128) documented in-schema; enforcement gate lands in 04-02 CheckElmValidity (reject-at-parse, never clamp)"
  - "Pattern constraints DO survive quicktype into ClassMemberConstraints (contrary to plan's byte-identical expectation): elm-model-manifest regen carries the extended role pattern; committed as regen output, zero hand edits"
  - "Fixture manifest now declares 5 artifacts (4 required + embedding_file); the committed Phase 3 fixture's llm_model_json/embeddings entries were never valid roles and are superseded"
  - "llm.mnn.json dropped from fixture carriage entirely: MNN Llm::load never reads it (LoRA/GPTQ-only material per MNN transformers README)"

patterns-established:
  - "Additive-key envelope extension: defaults serialize always (8 base keys, 9 with error detail)"
  - "Per-role materialization: new manifest roles map to a FIXED MNN default filename via kRoleFilenames; kRequiredRoles stays minimal"

requirements-completed: [E2E-01, RES-02]

coverage:
  - id: D1
    description: "ElmGeneration.stop rides the job schema with documented bounds; regenerated root set exposes get_stop/set_stop"
    requirement: E2E-01
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/generated/ElmGeneration.hpp#get_stop/set_stop (quicktype 23.2.6 regen; diff verified stop-only)"
        status: pass
    human_judgment: false
  - id: D2
    description: "embedding_file optional manifest role end-to-end (schema pattern in both schemas, role table entry, fixture declaration, optionality legs)"
    requirement: RES-02
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/elmruntime/elm_manifest_test.cpp#EmbeddingFileRoleIsOptional, #RoleFileNameMapsEmbeddingFile (26/26 pass)"
        status: pass
    human_judgment: false
  - id: D3
    description: "ElmEnvelope carries D-04 settlement stamps grab_time_usec/finish_time_usec on every JSON wire form (defaults 0, error envelopes included)"
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/elmruntime/elm_envelope_test.cpp#KeySetExactOnStop, #ErrorDetailPresentOnError, #SettlementStampsRoundTrip (17/17 pass)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Phase 3 post-Acquire embedding injection workaround retired; StageRealBundle declares embedding_file and the cache materializes it verified"
    verification:
      - kind: unit
        ref: "SuperGenius/SGProcessingManager/test/processors/elm_processor_test.cpp — InjectFixtureExtras removed (grep 0 live refs); 4/4 always-run legs pass, 17 fixture legs skip per SGPROC_ELM_TEST_MODEL_DIR convention"
        status: pass
    human_judgment: true
    rationale: "Full retirement proof requires the staged ~557MB Qwen fixture (GPU-class generation legs) which no CI/automated run exercises here; always-run legs + manifest tests cover the declared-role path."

duration: 46min
completed: 2026-09-14
status: complete
---

# Phase 4 Plan 01: Schema Amendments + Envelope Stamps Summary

**Both STATE.md TODO schema escalations closed at the schema/generated layer (stop array D-01/D-02, embedding role D-03) plus D-04 settlement stamps on the envelope — zero hand-edits to generated/.**

## Performance

- **Duration:** ~46 min
- **Started:** 2026-09-14T20:10Z (approx; terminal session)
- **Completed:** 2026-09-14 (commits 0659bce..3cce339)
- **Tasks:** 3 (all auto) + 2 verification fixes
- **Files modified:** 14 (all inside SGProcessingManager)

## Accomplishments

- `ElmGeneration.stop` added to gnus-processing-schema.json (array, maxItems 4, items 1–128 chars) with the C++-gate bounds note; root quicktype set regenerated — `get_stop()`/`set_stop()` return/accept `boost::optional<std::vector<std::string>>` (the tags precedent shape, recorded per plan)
- `embedding_file` 6th optional manifest role live end-to-end: role pattern extended in BOTH schemas, `kRoleFilenames` +1 pair (→ `embeddings_bf16.bin`, MNN llmconfig.hpp:127 default), `kRequiredRoles` untouched (4), fixture manifest re-declared, Phase 3 injection workaround retired
- `ElmEnvelope` + `grab_time_usec`/`finish_time_usec` (int64_t, default 0, worker-attested settlement stamps) — `ElmEnvelopeToJson` emits both ALWAYS (six-key → eight-key wire form; error envelopes too); zero-MNN banner rule preserved
- SGProcessors standalone-build link blocker found and fixed (pre-existing since Phase 3)

## Task Commits

1. **Task 1: ElmGeneration.stop schema amendment + root-set regen** — `0659bce` (feat)
2. **Task 2: embedding_file optional manifest role + fixture retirement** — `645ee75` (feat)
3. **Task 3: ElmEnvelope settlement stamps** — `7c791f9` (feat)
4. **Verification fixes (link closure + key-count)** — `3cce339` (fix)

**Plan metadata:** SUMMARY commit follows in root repo (planning artifacts live in the GeniusNetwork root .planning/, workstream elmbridge).

## Files Created/Modified

- `gnus-processing-schema.json` — stop property + role-pattern extension
- `elm-model-manifest-schema.json` — role-pattern extension
- `generated/ElmGeneration.hpp`, `generated/Generators.hpp` — regen (stop)
- `generated/elmruntime-manifest/ElmModelArtifact.hpp` — regen (pattern carries embedding_file into ClassMemberConstraints)
- `include/elmruntime/ElmEnvelope.hpp` / `src/elmruntime/ElmEnvelope.cpp` — stamps + always-emit
- `src/elmruntime/ElmManifest.cpp` — kRoleFilenames +1 pair
- `src/processors/CMakeLists.txt` — SGProcessors PUBLIC link += sgprocmanagerelmruntime
- `test/fixtures/elm-test-model/elm_manifest.json` — 5 declared artifacts (invalid entries superseded)
- `test/fixtures/README.md` — Known-gap section → D-03 resolved note
- `test/elmruntime/elm_manifest_test.cpp` — +2 legs (optionality, RoleFileName mapping)
- `test/elmruntime/elm_envelope_test.cpp` — eight-key exact set, error 9-key, stamps round-trip
- `test/processors/elm_processor_test.cpp` — StageRealBundle declares embedding_file; injection retired; key-count 8/9

## Decisions Made

- Getter shape recorded: `boost::optional<std::vector<std::string>> get_stop() const` (matches the tags precedent / plan expectation A4)
- Committed fixture's `llm_model_json`/`embeddings` entries replaced by one valid `embedding_file` role (plan text said "sixth artifact"; the committed fixture actually had two INVALID role names — 5 declared artifacts is the correct end state)
- `llm.mnn.json` no longer declared/injected: MNN `Llm::load` never reads it (LoRA/GPTQ-only per MNN transformers README); verified by grep over llm.cpp

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Build config] SGProcessors missing elmruntime link closure**
- **Found during:** Plan-level verification (full standalone build)
- **Issue:** `processing_processor_elm.cpp` references `sgns::elmruntime` symbols but `SGProcessors` link set lacked `sgprocmanagerelmruntime`; only test/processors linked it explicitly, so `sgprocbase_elm_job_schema_test` (ProcessingBase consumer) failed LNK2019. Reproduced at Phase 3 baseline 7ffc911 — pre-existing; full standalone build had never been run end-to-end
- **Fix:** `target_link_libraries(SGProcessors PUBLIC ... sgprocmanagerelmruntime)` (no cycle: elmruntime links only util libs + MNN/Vulkan PRIVATE)
- **Files modified:** `src/processors/CMakeLists.txt`
- **Verification:** full standalone build 0 errors; `sgprocbase_elm_job_schema_test` 27/27 pass
- **Committed in:** `3cce339`

**2. [Rule 1 - Test assertion] EnvelopeFieldsOnFinishReasons key counts**
- **Found during:** Task 3 verification (processor test run)
- **Issue:** Phase 3 leg asserted the old 6/7-key envelope; D-04 additive stamps make it 8/9
- **Fix:** updated counts + added `grab_time_usec`/`finish_time_usec` presence asserts
- **Files modified:** `test/processors/elm_processor_test.cpp`
- **Verification:** 4/4 always-run legs pass
- **Committed in:** `3cce339`

**3. [Recorded, not a defect] Manifest-set regen NOT byte-identical**
- Plan expected pattern constraints to be codegen-invisible; they DO survive into `ClassMemberConstraints` (the `name_constraint` pattern string extends). Committed as pure regen output — zero hand edits. Root-set regen diff was stop-only as expected.

---

**Total deviations:** 2 auto-fixed (1×Rule 3, 1×Rule 1) + 1 expectation correction recorded
**Impact on plan:** All fixes required for the plan's own "standalone build green" verification; no scope creep.

## Issues Encountered

- CRLF churn: quicktype emits LF; `core.autocrlf` working-copy warnings on regen. Unrelated generated files showed ZERO content diff (`git diff` empty) — only content-changed files staged; unrelated files left restored. No unrelated drift committed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 04-02 builds directly on this: regenerated `get_stop()` surface for the CheckElmValidity bounds gate, envelope stamps for the worker to set (grab before fetch, finish at assembly), and the fixture/cache paths proven by tests
- Fixture legs still need `SGPROC_ELM_TEST_MODEL_DIR` staged for full generation coverage (unchanged convention)
- SuperGenius pointer bump to these commits belongs to the later grid-integration plans (04-03/04-05 chain), not this plan

---
*Phase: 04-grid-integration-e2e-proof*
*Completed: 2026-09-14*
