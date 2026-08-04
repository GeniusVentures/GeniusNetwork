# Requirements: sgproc-render v2.0 — Execution Quality & Robustness

**Defined:** 2026-08-03
**Core Value:** Harden the v1.0 hand-rolled Vulkan render pipeline with production-grade execution control, structured output artifacts, capability-aware scheduling, Vulkan validation layers, and a comprehensive conformance test suite — building directly on the shipped v1.0 `RenderProcessor` foundation.

**Depends on:** v1.0 (shipped — hand-rolled Vulkan render pass execution, 24 plans across 6 phases). Only pending v1.0 item: E2E-02 (macOS/MoltenVK CI verification on gv-OSX-Large).

**Source issues:** `GeniusVentures/SGProcessingManager#12`, `#13`, `#14`, `#15`

## v2 Requirements

### Execution Contexts & Lifecycle (Phase 1, GitHub #13)

- [ ] **EXEC-01**: An `ExecutionContext` struct carries execution/attempt/pass/subtask identifiers, a cooperative cancellation token, overall and per-pass deadlines, and resource budgets (CPU, GPU, RAM/VRAM, disk, network, runtime, output-size) through `ProcessingManager` and every executor's `StartProcessing()` signature
- [ ] **EXEC-02**: A running MNN or Vulkan test job can be cancelled cooperatively without leaking Vulkan resources, MNN sessions, loaded artifacts, or pending asynchronous saves — and cancelled jobs never publish a successful result
- [ ] **EXEC-03**: Deadline and output-size budget exceedances produce distinct, typed failure states (not generic "failed") distinguishable from cancellation or runtime errors
- [ ] **EXEC-04**: Structured progress events carry pass ID, stage name, completed-work count, total-work count, and a human-readable message — replacing the current single `float` percentage
- [ ] **EXEC-05**: Checkpoint-capable processors expose a `SaveCheckpoint()`/`RestoreCheckpoint()` contract; processors without checkpoint support report that clearly (no silent "checkpointed" when nothing was saved)
- [ ] **EXEC-06**: Existing processors remain usable through a migration adapter during the `ExecutionContext` rollout — no processor is broken by the signature change before its maintainer opts in
- [ ] **EXEC-07**: Terminal states are enumerated: `completed`, `cancelled`, `timed_out`, `budget_exceeded`, `failed` — every code path that terminates a job assigns exactly one

### Structured Artifacts & Execution Manifests (Phase 2, GitHub #14)

- [ ] **ARTIFACT-01**: Each output artifact carries a typed record with: declared resource name, stable artifact ID, producing pass and output binding, data type/format/shape/dimensions/byte size/media type, content hash and chunk hashes, storage URI/CID and local-cache identity, partial/final status and sequence number, and privacy/tenant scope
- [ ] **ARTIFACT-02**: An `ExecutionManifest` struct aggregates execution/attempt/task/subtask/pass IDs, selected executor and runtime compatibility identity, model/tokenizer/adapter/shader/quantization identities (when used), input and output artifact hashes, start/end times, terminal state, error details, resource-use summary, verification/EIS metadata extension points, and worker signature input
- [ ] **ARTIFACT-03**: The manifest serializes deterministically for hashing, signing, caching, and verification — no map iteration-order or pointer-address dependency
- [ ] **ARTIFACT-04**: No newline parsing is required to discover output locations — the current `join("\n")` → protobuf string path is replaced with proper typed protobuf fields coordinated with SuperGenius
- [ ] **ARTIFACT-05**: Multi-output jobs return independently typed and hashed artifact records; final and intermediate artifacts retain their producing pass and binding identity
- [ ] **ARTIFACT-06**: Existing callers have a migration adapter until SuperGenius protobuf integration is updated — no breaking change without a transition path

### Capability-Validation Contract (Phase 3, GitHub #12)

- [ ] **CAP-01**: `ProcessingManager::CanExecute(definition)` derives job requirements from the processing definition and returns a structured result: executable (bool), unmet requirements (list with reasons), estimated resource needs, and selected executor identity
- [ ] **CAP-02**: Required pass types and executor registrations are validated — unregistered pass types return a specific "no executor registered" reason
- [ ] **CAP-03**: Model format, quantization, tokenizer/adapter compatibility, and model identity are validated for inference passes
- [ ] **CAP-04**: Vulkan/SPIR-V feature, extension, descriptor, image-format, buffer-size, and memory requirements are validated for `COMPUTE` and `RENDER` passes against the node's actual physical device capabilities
- [ ] **CAP-05**: Input/output type, format, dimensions, and estimated memory/storage needs are validated before downloading large inputs or claiming work
- [ ] **CAP-06**: The selected executor and key compatibility identities are stable (same definition → same executor) and available to the scheduler and result metadata
- [ ] **CAP-07**: CPU architecture or instruction requirements for CPU processors are validated where applicable
- [ ] **CAP-08**: Privacy or placement flags from job metadata are carried through to the capability result without duplicating SuperGenius policy enforcement

### Vulkan Validation Layers (Phase 4, VALLAYER-01, deferred from v1.0 CTX-04)

- [ ] **VVL-01**: Vulkan Validation Layers (VVL) are wired into debug builds (`CMAKE_BUILD_TYPE=Debug`) for both `RenderProcessor`'s independent `VkInstance`/`VkDevice` and the test suite's Vulkan contexts — not product Release builds
- [ ] **VVL-02**: VVL is conditionally enabled via a CMake option (`SGNS_ENABLE_VULKAN_VALIDATION`, default `OFF`), gated on `Vulkan-Headers` availability (already vendored) — no new `thirdparty/` submodule required
- [ ] **VVL-03**: CI debug builds exercise VVL-enabled Vulkan contexts and surface validation errors as test failures; Release and non-debug CI builds never load VVL
- [ ] **VVL-04**: The VVL decision is documented as an explicit architectural choice (deferred from v1.0 CTX-04) with rationale for debug-only scope

### Conformance Test Suites (Phase 5, GitHub #15)

- [ ] **CONF-01**: CTest targets register from the standalone SGProcessingManager build and execute when consumed by `SuperGenius/develop` — no manual test registration required
- [ ] **CONF-02**: Each registered executor (MNN inference, Vulkan compute, Vulkan render) runs the same core conformance contract — executor-agnostic test cases with executor-specific fixtures
- [ ] **CONF-03**: Schema parsing and pass-specific validation tests cover valid/invalid/edge-case definitions
- [ ] **CONF-04**: Pass/input indexing and optional-field safety tests cover the concrete index-mismatch and model-only-assumption bugs fixed in v1.0
- [ ] **CONF-05**: Named multi-input, multi-output, and intermediate binding tests exercise the full binding-resolution path
- [ ] **CONF-06**: Pass-graph topology tests cover linear, branching, merging, disabled, invalid, and cyclic graphs
- [ ] **CONF-07**: Executor selection tests verify correct dispatch by pass type and backend
- [ ] **CONF-08**: Output hashing, artifact metadata, persistence, and deterministic serialization tests (Phase 2's ARTIFACT-03)
- [ ] **CONF-09**: Cancellation, deadline, budget, progress, partial-result, and cleanup behavior tests (Phase 1's EXEC-01..07)
- [ ] **CONF-10**: Capability acceptance and rejection tests (Phase 3's CAP-01..08)
- [ ] **CONF-11**: Backward-compatibility adapter tests ensure migration adapters (EXEC-06, ARTIFACT-06) don't regress
- [ ] **CONF-12**: Native Vulkan and MoltenVK run equivalent compute/render fixtures where CI hardware permits; unsupported environments skip with an explicit reason
- [ ] **CONF-13**: Tests use small deterministic fixtures — no downloading large public models during normal CI
- [ ] **CONF-14**: The full existing v1.0 test suite (52 tests across 5 targets) passes with zero regressions

## Out of Scope for v2.0

Explicitly excluded. Carried forward from v1.0 deferred list.

- **MPASS-01**: Multi-pass/post-processing shader chains
- **MRT-01**: Multiple render targets (MRT)
- **INTEROP-01**: Compute/inference ↔ render interop (MNN-tensor-to-Vulkan-buffer bridging)
- **INST-01**: Instancing support
- **TEXIN-01**: Texture sampling from external input
- **BLEND-01**: Alpha blending/transparency
- **XNODE-01**: Cross-node tolerance/redundancy-based verification

## Traceability

| Requirement | GitHub Issue | Phase | Depends On |
|------------|-------------|-------|------------|
| EXEC-01..07 | #13 | 1 | — (foundational) |
| ARTIFACT-01..06 | #14 | 2 | EXEC-01 (execution IDs for manifest) |
| CAP-01..08 | #12 | 3 | EXEC-01 (structured context), v1.0 #11 (dispatch by pass type, shipped) |
| VVL-01..04 | v1.0 CTX-04 | 4 | — (independent) |
| CONF-01..14 | #15 | 5 | EXEC-01..07, ARTIFACT-01..06, CAP-01..08, VVL-01..04 |
