# Roadmap: sgproc-render v2.0 — Execution Quality & Robustness

**Defined:** 2026-08-03
**Source issues:** `GeniusVentures/SGProcessingManager#12`, `#13`, `#14`, `#15` + v1.0 deferred `VALLAYER-01`

**Context:** v1.0 shipped hand-rolled Vulkan render pass execution (24 plans, 6 phases). v2.0 hardens the pipeline with production-grade execution control, structured outputs, capability-aware scheduling, VVL integration, and conformance testing. All v2 phases build on the v1.0 `RenderProcessor` foundation — no new rendering backends, no schema changes to the render pass definition itself.

## Phases

- [ ] **Phase 1: Cancellable Execution Contexts & Lifecycle** — Every processor receives a structured `ExecutionContext` with cancellation, deadlines, budgets, progress events, and terminal states; existing processors work through a migration adapter
- [ ] **Phase 2: Structured Artifacts & Execution Manifests** — Output artifacts carry typed records with hashes/provenance/identity; `ExecutionManifest` aggregates full job metadata with deterministic serialization; newline-joined output-location strings replaced with proper protobuf fields
- [ ] **Phase 3: Capability-Validation Contract** — `CanExecute()` derives job requirements from the processing definition, compares against the node's actual Vulkan/model/runtime capabilities, and returns a structured result before downloading inputs or claiming work
- [ ] **Phase 4: Vulkan Validation Layers** — VVL wired into debug builds and CI via a CMake option (`SGNS_ENABLE_VULKAN_VALIDATION`); no new vendoring; deferred from v1.0 CTX-04
- [ ] **Phase 5: Processor & Pass-Graph Conformance Test Suites** — CTest targets with executor-agnostic conformance contracts; covers schema, indexing, bindings, topology, dispatch, hashing, determinism, cancellation, budgets, capabilities, and migration adapters

## Phase Details

### Phase 1: Cancellable Execution Contexts & Lifecycle

**Goal:** Every processor receives a structured `ExecutionContext` replacing the current bare `StartProcessing()` signature, with cooperative cancellation, deadlines, resource budgets, structured progress events, checkpoint support, and enumerated terminal states — and every existing processor works through a migration adapter without being broken.

**Depends on:** Nothing (foundational v2 phase — builds on v1.0's shipped `ProcessingManager::Process()` dispatch)

**Requirements:** EXEC-01, EXEC-02, EXEC-03, EXEC-04, EXEC-05, EXEC-06, EXEC-07

**Success Criteria:**
1. A running MNN or Vulkan test job can be cancelled cooperatively without leaking Vulkan resources, MNN sessions, loaded artifacts, or pending async saves — cancelled jobs never publish a successful result.
2. Deadline-exceeded and output-size-budget-exceeded jobs produce distinct typed failure states distinguishable from cancellation and runtime errors.
3. Structured progress events carry pass ID, stage name, completed/total work counts, and a human-readable message — replacing the current single float percentage.
4. Checkpoint-capable processors expose `SaveCheckpoint()`/`RestoreCheckpoint()`; non-checkpoint-capable processors report that clearly rather than silently claiming they checkpointed.
5. All existing MNN and Vulkan processors remain usable through a migration adapter — no processor is broken by the `ExecutionContext` signature change before its maintainer opts in.

**Plans:** TBD

### Phase 2: Structured Artifacts & Execution Manifests

**Goal:** Replace `ProcessingResult`'s loose (hash, name→bytes, location-strings) shape with typed per-artifact records and a deterministic `ExecutionManifest` — coordinated with SuperGenius for proper protobuf fields instead of newline-joined strings.

**Depends on:** Phase 1 (needs `ExecutionContext` identifiers for manifest fields: execution/attempt/task/subtask/pass IDs, terminal state, resource-use summary)

**Requirements:** ARTIFACT-01, ARTIFACT-02, ARTIFACT-03, ARTIFACT-04, ARTIFACT-05, ARTIFACT-06

**Success Criteria:**
1. Multi-output jobs return independently typed and hashed artifact records — each carrying resource name, stable ID, producing pass/binding, type/format/shape, content and chunk hashes, storage URI/CID, partial/final status, and privacy scope.
2. `ExecutionManifest` aggregates full job metadata and serializes deterministically — no map iteration-order or pointer-address dependency — producing the same bytes for the same logical manifest regardless of how it was constructed in memory.
3. No newline parsing is required to discover output locations — the current `join("\n")` → protobuf string path is replaced with proper typed protobuf fields coordinated with SuperGenius.
4. Existing callers work through a migration adapter during the protobuf transition — no breaking change without a transition path.

**Plans:** TBD

### Phase 3: Capability-Validation Contract

**Goal:** `ProcessingManager::CanExecute(definition)` derives job requirements from the processing definition, compares against the node's actual Vulkan physical-device capabilities, model/runtime availability, and resource constraints, and returns a structured result — so a node can reject unexecutable jobs before downloading large inputs or claiming work.

**Depends on:** Phase 1 (needs `ExecutionContext` for structured validation context); v1.0 #11 (dispatch by pass type — already shipped)

**Requirements:** CAP-01, CAP-02, CAP-03, CAP-04, CAP-05, CAP-06, CAP-07, CAP-08

**Success Criteria:**
1. `CanExecute()` returns a structured result with: executable (bool), unmet requirements (list with specific reasons), estimated resource needs, and selected executor identity.
2. A render pass definition requiring a Vulkan feature the node's physical device doesn't support returns a specific "VK feature X not available" reason — not a generic "unsupported."
3. The selected executor identity is stable — same definition always maps to the same executor — and is available to the scheduler and result metadata.
4. Unsupported Vulkan, model, quantization, input-format, or executor requirements each return distinct, specific reasons — never a catch-all "validation failed."

**Plans:** TBD

### Phase 4: Vulkan Validation Layers

**Goal:** Vulkan Validation Layers are wired into debug builds and CI, gated behind a CMake option, with zero new `thirdparty/` vendoring — closing the explicit deferred decision from v1.0 CTX-04.

**Depends on:** Nothing (independent — can run concurrently with any phase)

**Requirements:** VVL-01, VVL-02, VVL-03, VVL-04

**Success Criteria:**
1. Debug builds (`CMAKE_BUILD_TYPE=Debug`) load and enable VVL for `RenderProcessor`'s independent `VkInstance`/`VkDevice` and test-suite Vulkan contexts — Release builds never load VVL.
2. VVL enablement is a single CMake option (`SGNS_ENABLE_VULKAN_VALIDATION`, default `OFF`) — no manual environment-variable or layer-path configuration required.
3. CI debug builds surface VVL errors as test failures; Release and non-debug CI builds never load VVL.
4. The decision and its rationale (debug-only, no new vendoring, deferred from v1.0) are documented in an ADR or the phase's CONTEXT.md.

**Plans:** TBD

### Phase 5: Processor & Pass-Graph Conformance Test Suites

**Goal:** A comprehensive, executor-agnostic conformance test suite with CTest targets verifies the full SGProcessingManager execution contract — schema, dispatch, bindings, topology, hashing, determinism, cancellation, budgets, capabilities, and migration adapters — with zero regressions to the existing 52-test v1.0 suite.

**Depends on:** Phases 1–4 (tests the contracts those phases introduce)

**Requirements:** CONF-01, CONF-02, CONF-03, CONF-04, CONF-05, CONF-06, CONF-07, CONF-08, CONF-09, CONF-10, CONF-11, CONF-12, CONF-13, CONF-14

**Success Criteria:**
1. CTest targets register from the standalone SGProcessingManager build and execute when consumed by `SuperGenius/develop`.
2. Each registered executor (MNN inference, Vulkan compute, Vulkan render) runs the same core conformance contract — executor-agnostic test cases with executor-specific fixtures.
3. Concrete regression tests cover the index-mismatch, model-only-assumption, output-buffer-zero-fallback, and unsupported-pass-fallthrough bugs fixed in v1.0.
4. Pass-graph topology tests cover linear, branching, merging, disabled, invalid, and cyclic graphs.
5. Native Vulkan and MoltenVK run equivalent compute/render fixtures where CI hardware permits; unsupported environments skip with an explicit reason — no silent test disappearance.
6. The full existing v1.0 test suite (52 tests across 5 targets) passes with zero regressions.
7. All tests use small deterministic fixtures — no downloading large public models during normal CI.

**Plans:** TBD

## Execution Order

Phases execute in numeric order: 1 → 2 → 3 → 4 → 5.

**Parallelism notes:**
- Phase 4 (VVL) has no dependencies and can run concurrently with any phase.
- Phase 2 (Artifacts) and Phase 3 (Capabilities) both depend on Phase 1 but not on each other — they can be developed concurrently after Phase 1 lands.
- Phase 5 (Conformance) requires all other phases to land first (it tests their contracts).

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|---------------|--------|-----------|
| 1. Execution Contexts & Lifecycle | 0/TBD | Not started | - |
| 2. Structured Artifacts & Manifests | 0/TBD | Not started | - |
| 3. Capability-Validation Contract | 0/TBD | Not started | - |
| 4. Vulkan Validation Layers | 0/TBD | Not started | - |
| 5. Conformance Test Suites | 0/TBD | Not started | - |
