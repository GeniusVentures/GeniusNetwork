# Phase 2: Manifest & Model Cache - Context

**Gathered:** 2026-09-10
**Status:** Ready for planning

<domain>
## Phase Boundary

A node can turn a manifest `uri`+`hash` into a verified, loadable MNN model bundle on disk — fail-closed, downloaded once, safely reusable. This phase delivers, entirely in SGProcessingManager `src/elmruntime/` (submodule-first, no SuperGenius dependency):

1. **Manifest layer** — fetch the manifest by `uri` through `FileManager`, verify its declared `hash`, parse it (quicktype regen into `generated/`), enumerate artifacts mapping onto MNN's expected on-disk bundle layout (`llm_config.json` + weights + tokenizer assets)
2. **Per-artifact fetch + verify** — every artifact fetched via `FileManager` and sha256-verified before use; fail-closed on every path (fresh download, cache reuse, partial recovery) — MCHE-01
3. **Content-addressed cache** at `<cacheDir>/elmruntime/<manifest-hash>/` with atomic publish (stage → verify → rename), pin-refcount while subtasks execute, single-flight dedup for concurrent subtasks, poison quarantine (`.bad-<hash>`), LRU eviction of unpinned entries under a fixed byte cap, partial-download recovery — MCHE-02, MCHE-03
4. **Loadability smoke check** — after materialization, `createLLM` + `load` + 1-token greedy generation must succeed before an entry is marked usable (wrong-tokenizer bundles fail as structured errors, not silent garbage)
5. **`required_memory_bytes` preflight** — manifest runtime block surfaced to the existing `CapabilityValidator` checks

**Out of scope (Phase 3+):** the ELM processor itself, session lifecycle, `VulkanInitMutex` scope fix (P3 — though P2's load-once-per-entry bounds its damage), splitter, submit wiring, E2E. The processor's private temp-dir materializer is *deleted* in Phase 3 when the processor retargets the cache path — P2 builds the cache that replaces it.

**Locked by roadmap SC-1..SC-5:** hash-verify everything before use with no debug bypass; atomic publish + smoke-check-before-usable; quarantine prevents livelock; exactly-one-download under concurrency (single-flight), pinned entries never evicted mid-use; `%TEMP%` stays clean across runs.

Requirements: MCHE-01, MCHE-02, MCHE-03.

</domain>

<decisions>
## Implementation Decisions

### Reuse Verification (cache-hit path)
- **D-01:** **Size-first fast path** — on a cache hit, stat every artifact and compare against the manifest's declared `size_bytes` (instant). No sha256 re-hash on hit; content integrity is guaranteed by the publish-time gate (an entry at its final path is complete-and-verified by construction) on trusted local disk. This is Pitfall 8's recommendation — a full 300-500MB re-hash per subtask is the cost trap. If the cache dir is ever shared/external, full re-verification becomes mandatory (deferred — v1.0 is local-disk only)
- **D-02:** **Quarantine + fail acquire on mismatch** — a size (or any verification) mismatch at reuse time renames the entry to `.bad-<hash>`, fails the acquire as a structured `RESOURCE_RESOLUTION` error, and the SAME acquire retried re-downloads cleanly. No auto-refetch inside the failing call (the subtask's funding clock keeps running during a re-download it has no visibility into — the caller decides whether to retry); no outright delete (loses forensic evidence)

### Cache Root & Disk Policy
- **D-03:** **Reuse `FileManager::getCacheDir()`** — the cache nests as `<cacheDir>/elmruntime/<manifest-hash>/`, consistent with the existing `results/` convention (`ProcessingManager.cpp:1931` uses the same root). Zero new configuration surface for the cache *location*. Fail closed if the cache dir is unset/empty — never guess a default
- **D-04:** **Fixed byte cap for eviction** — LRU eviction of unpinned entries triggers when the cache's total bytes exceed a configurable cap (sane default in the 10-20GB range — planner picks the exact default). Manifest `size_bytes` makes the arithmetic trivial and deterministic. No free-space-threshold axis in v1.0

### Manifest Schema
- **D-05:** **Quicktype regen** — the manifest shape (`schema_version`, `elm_type`, `model_format`, `quantization`, `artifacts[]` with `name`/`uri`/`sha256`/`size_bytes`, `runtime` block) joins `gnus-processing-schema.json` and regenerates into `generated/` — the same pipeline and zero-hand-edits norm (SCHEMA-01..05) as the Phase 1 ELM job block (`Elm`/`ElmGeneration`/`ElmFunding` already live there). One schema authority; constraint checking comes free. The manifest's own bytes are hash-pinned by the work item's `model_manifest_hash`, so schema evolution rides the same content-addressing as everything else

### Eviction State, Quarantine & Testing
- **D-06:** **Directory-scan rebuild on restart** — LRU order and entry state are reconstructed at startup by scanning `cache/<hash>/` dirs (order from directory mtimes); pin counts start at zero (pins are meaningless across restarts). A populated disk cache survives restarts; the Phase 4 empty-cache E2E still works because it starts with no entries. No persisted index file (index-vs-disk drift is a new bug class for no v1.0 benefit)
- **D-07:** **`.bad-<hash>` quarantine dirs are kept forever** — they are forensic evidence; the log line at quarantine time is the telemetry event (PITFALLS asks for quarantine logging). They are ignored by cache-size accounting and never block re-download (different path). No auto-clean policy in v1.0
- **D-08:** **Injectable fetch interface for tests** — `ElmArtifactFetcher` (and manifest fetch) takes an injectable fetch abstraction (a function returning bytes for a URI); production wires `FileManager::LoadASync` exclusively (never raw sockets/curl — issue #17 mandate), tests inject in-memory or `file://`-backed lambdas. FileManager remains the only production fetcher; unit tests never need IPFS

### Carried Forward (locked by roadmap/research — not re-decided here)
- Atomic publish (download to `cache/.tmp-<uuid>/` staging, verify sha256 of every artifact, same-filesystem `rename()` into place) — publish-time gate is THE correctness mechanism (Pitfall 8)
- Single-flight per manifest hash: per-node map `manifest-hash → in-flight download (shared_future)`; second concurrent subtask awaits the first download (SC-4: exactly one download, both pin and load the same entry)
- Smoke check gates usability: `createLLM` + `load()` + 1-token greedy generation before an entry is marked usable (Pitfall 7 — converts wrong-tokenizer bundles into structured errors)
- Hashing and filesystem-heavy work runs on worker threads, never in asio handlers; asio handlers only coordinate (Pitfall 14)
- Every new timer/callback captures `weak_from_this` — the async-timer UAF pattern is this project's recurring crash class (Pitfall 15.1)
- Manifest artifacts map onto MNN's expected bundle layout — the cache produces a *loadable directory*, not a file store (Pitfall 7)
- New test targets respect `SGPROC_TEST_DISCOVERY` gating and CTest `TIMEOUT` properties (Pitfall 15.2/15.3)

### Claude's Discretion
- Exact default byte cap value (10-20GB suggested) and its configuration mechanism (existing config surface vs a new setting — prefer whatever the repo's established config pattern is)
- The exact quicktype spelling of manifest types (Phase 1 learned quicktype names enums from properties — record actual generated names in the plan, don't assume)
- Internal structure of the single-flight map, pin-refcount RAII handle, and quarantine rename mechanics
- The precise staging-directory naming and cleanup discipline for partial downloads
- Unit-test structure/file layout under `test/elmruntime/`
- Whether the smoke check runs inside the acquire path or as a post-publish step (it must complete before the entry is marked usable — placement is free)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream research (verified against `dev_elmruntime` branches)
- `.planning/workstreams/elmbridge/research/SUMMARY.md` — Phase 2 section: deliverables list, stack (zero new deps), verification legs
- `.planning/workstreams/elmbridge/research/PITFALLS.md` — Pitfall 5 (VulkanInitMutex / load-once-per-entry bounds lock frequency), 6 (temp-dir leak, cache owns session lifecycle, atomic layout + pinning), 7 (bundle-vs-blob, MNN expected layout, smoke check), 8 (TOCTOU, publish-time gate, single-flight, quarantine, size-first fast path), 13 (`required_memory_bytes` surfaced for capability gate), 14 (worker-thread hashing rule), 15.1 (`weak_from_this` discipline)
- `.planning/workstreams/elmbridge/research/ARCHITECTURE.md` — `src/elmruntime/` project structure, Pattern 3 (self-fetching processor + content-addressed cache), data flow step [5] (cache acquire path), state management (cache pin/in-flight dedup)
- `.planning/workstreams/elmbridge/research/FEATURES.md` — sections B (manifest resolution) and C (content-addressed cache): the full feature table this phase implements
- `.planning/workstreams/elmbridge/research/STACK.md` — MNN LLM API surface, `sgprocmanagersha`, `FileManager`, `std::filesystem` conventions

### Upstream design notes
- `SuperGenius/.planning/notes/ELM-bridging-gaps.md` — manifest JSON shape draft (§"What the model manifest contains"), cache keying `cache/<model-manifest-hash>/`, local-caching flow, artifacts[]/runtime block definitions

### Planning artifacts
- `.planning/workstreams/elmbridge/REQUIREMENTS.md` — MCHE-01..03 definitions; Out of Scope list (binding)
- `.planning/workstreams/elmbridge/ROADMAP.md` — Phase 2 success criteria (SC-1..SC-5) and notes
- `.planning/workstreams/elmbridge/phases/01-elm-job-model-funding/01-CONTEXT.md` — Phase 1 decisions D-01..D-13 (schema shape the cache consumes; D-04 default-fill; D-05 reject-at-parse)
- `.planning/workstreams/elmbridge/phases/01-elm-job-model-funding/01-01-SUMMARY.md` — generated-type spellings and quicktype codegen realities (bounds dropped for optional fields; getters return `boost::optional` by value — materialize into named locals; enum naming from properties)

### Code anchors (verified)
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1931` — `FileManager::GetInstance().getCacheDir()` precedent (results/ dual-save); D-03's cache root
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_mnn_llm.cpp` — the temp-dir materializer being replaced (`MaterializeModelToTempDir`, timestamp-named, never cleaned); `VulkanInitMutex` held across `createLLM`+`load` (Pitfall 5); `ResolveMaxNewTokens` precedent
- `SuperGenius/SGProcessingManager/src/capability/capability_validator.cpp` — existing capability snapshot/check machinery the `required_memory_bytes` preflight feeds
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json` + `generated/` — the quicktype pipeline D-05 extends
- `SuperGenius/SGProcessingManager/generated/Elm.hpp` — Phase 1's `model_manifest_uri`/`model_manifest_hash` fields this phase consumes
- `SuperGenius/SGProcessingManager/src/util/sha256.hpp` — `sgns::sgprocmanagersha` hashing utilities (optional ~30-line incremental EVP helper for hash-while-download per STACK.md)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`FileManager` (AsyncIOManager singleton)** — all artifact I/O (`ipfs://`/`https://`/`file://`); `getCacheDir()` provides the cache root (D-03); `LoadASync` is the production fetcher behind the injectable interface (D-08)
- **Quicktype pipeline** (`gnus-processing-schema.json` → `generated/`) — D-05 extends it with the manifest shape; `CheckConstraint` and the enum/validation conventions carry over from Phase 1
- **`sgns::sgprocmanagersha` (OpenSSL EVP)** — sha256 for manifest + artifact verification; optionally extended with an incremental hash-while-download helper
- **`CapabilityValidator`** — existing local preflight machinery; manifest `runtime.required_memory_bytes` feeds it (no new advertising — local check only, ELM-03)
- **Phase 1 generated types** — `sgns::Elm` carries `model_manifest_uri`/`model_manifest_hash` per work item; the cache keys on that hash

### Established Patterns
- **Submodule-first landing** — everything this phase ships is inside SGProcessingManager; SuperGenius consumes it later via pointer bump (innermost-first commit discipline: SGProcessingManager → SuperGenius → root)
- **Zero hand-edits to `generated/`** (SCHEMA-01..05) — quicktype regen only
- **Quicktype getters return `boost::optional<T>` by value** — materialize into named locals before dereferencing (Phase 1's UB lesson, recorded in 01-01-SUMMARY)
- **Worker-thread discipline** — hashing/fs-heavy work on workers; asio handlers coordinate only (Pitfall 14)
- **`SGPROC_TEST_DISCOVERY` gating** — new test targets must respect the standalone-build gate or the parent SuperGenius build breaks

### Integration Points
- **Acquire path**: ELM processor (Phase 3) calls `ElmModelCache::Acquire(manifest_uri, manifest_hash)` → hit (size-verify per D-01, pin, return path) | miss (single-flight fetch → staging → sha256 verify → rename → smoke check → usable)
- **`GetCidForProc` ELM branch** (Phase 3/4 wiring) routes manifest resolution through the cache instead of the single-buffer path
- **Quarantine naming** `.bad-<hash>` sits beside `cache/<hash>/` under `<cacheDir>/elmruntime/` — excluded from accounting, never loaded

</code_context>

<specifics>
## Specific Ideas

- Pitfall 8's corollary is adopted as design: verify **sizes first** — a size mismatch is an instant quarantine without hashing 300MB
- The cache directory doubles as `LlmConfig.base_dir` — one directory serves as both cache key and loadable MNN bundle (STACK.md insight); the cache layer's job is producing a *loadable directory*, not storing files
- Shared/external cache dirs are a future mode where D-01's size-only check becomes insufficient — full re-verification becomes mandatory there (deferred with the multi-node work)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 2-Manifest & Model Cache*
*Context gathered: 2026-09-10*
