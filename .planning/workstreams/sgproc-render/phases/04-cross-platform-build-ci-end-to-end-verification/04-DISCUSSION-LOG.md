# Phase 4: Cross-Platform Build, CI & End-to-End Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-31
**Phase:** 4-Cross-Platform Build, CI & End-to-End Verification
**Areas discussed:** GPU CI tiers, Software ICD, E2E-01 scope, CI wiring, GPU probing behavior

---

## GPU CI tiers (hardware-dependent tier scope)

| Option | Description | Selected |
|--------|-------------|----------|
| Assume/verify self-hosted GPUs | Treat existing self-hosted runners as GPU-capable; discover gaps during Phase 4 | |
| New dedicated GPU-runner label | Provision/require a distinct "real-GPU" labeled runner per platform | |
| Hardware-independent only in CI | Only wire the software-ICD tier; real-GPU determinism tier stays manual/local | |
| (free text) | User: runners are "a mixed bag" — sg-ubuntu-linux (modern AMD CPUs), SG-WIN11 (modern AMD/Intel), gv-OSX-Large (Tart VM on a high-end Mac), sg-arm-linux (recent ARM Minisforum box). "I don't think we should assume GPU availability." | ✓ (led to GPU-probe approach, see below) |

**User's choice:** None of the three literal options — free text redirected toward runtime GPU probing (formalized in the "GPU probing" round below).
**Notes:** Concrete runner hardware detail captured directly into CONTEXT.md's `<specifics>` section as load-bearing grounding for D-32/D-34.

---

## Software ICD (hardware-independent tier dependency choice)

| Option | Description | Selected |
|--------|-------------|----------|
| Mesa lavapipe (llvmpipe) | System package on Linux (mesa-vulkan-drivers), no new vendoring | |
| SwiftShader | Cross-platform but needs building/vendoring, no system package | |
| lavapipe (Linux/Win) + SwiftShader (Mac) | Hybrid, presented as clarifying follow-up | |
| SwiftShader everywhere | Single dependency, more vendoring cost | |
| Linux/Windows only, skip macOS software tier | Partial coverage | |
| **Skip software ICD entirely — GPU probing instead** | User: "Rather than trying to handle software at all, we will just use GPU probing to decide whether to do the test for now." | ✓ |

**User's choice:** Drop the software-ICD tier; use runtime GPU probing uniformly (D-31/D-32).
**Notes:** User asked clarifying questions first ("lavapipe on all platforms? works with MoltenVK? no new thirdparty packages?") — answered inline (lavapipe is Linux-only, no macOS build; MoltenVK and lavapipe are mutually exclusive, not stackable) before the user chose to sidestep the whole tradeoff.

---

## E2E-01 scope ("actual distributed processing pipeline")

| Option | Description | Selected |
|--------|-------------|----------|
| Single-node round trip | Real render job through ProcessingManager::Process() on one node | ✓ |
| Multi-node network test | Genuine IPFS/pubsub dispatch to a separate worker node | |

**User's choice:** Single-node round trip.
**Notes:** User: "I'm pretty sure we already have existing processing tests, those just post mnn posenet, so we would do a similar test for a render." Confirmed via codebase scout: `processing_schema_test.cpp:210`'s `PosenetJobTest` (real job-definition fixture pattern) and `processing_dispatch_test.cpp`'s existing `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` (from Phase 3) are the patterns to mirror/reuse. Also confirmed: no working multi-node test harness exists today (`processing_nodes_test.cpp`'s network cases are `DISABLED_*`; pubsub-based tests are commented out of the build).

---

## CI wiring

| Option | Description | Selected |
|--------|-------------|----------|
| Extend existing cmake.yml | Add steps into the existing per-platform matrix jobs | ✓ |
| New dedicated workflow file | Separate render-verification.yml scoped to Linux/Windows/macOS only | |

**User's choice:** Extend existing cmake.yml.
**Notes:** None.

---

## GPU probing behavior (follow-up to GPU CI tiers)

| Option | Description | Selected |
|--------|-------------|----------|
| Probe at runtime, skip gracefully if absent | vkEnumeratePhysicalDevices check; skip with clear CI annotation if no usable device | ✓ |
| Hard-require GPU, fail CI if absent | Treat missing GPU as a CI failure to fix | |

**User's choice:** Probe at runtime, skip gracefully if absent.
**Notes:** Applies uniformly across all platforms, explicitly including macOS (Tart VM GPU/Metal passthrough not assumed just because the host is "high-end").

---

## Claude's Discretion

- Exact CI step/job naming, GPU-probe implementation detail (CMake/CTest helper vs. inline script), CTest label/tag scheme for gating.
- Whether E2E-01's render job test is a new test case or a promotion/relabeling of the existing Phase 3 `RenderPassSameNodeRepeatedExecutionProducesBitExactHash` test.

## Deferred Ideas

- Software Vulkan ICD tier (lavapipe/SwiftShader) — explicitly dropped in favor of GPU-probe gating; revisit if a future milestone needs guaranteed CI coverage on GPU-less runners.
- Multi-node distributed dispatch test for E2E-01 — scoped down to single-node since no working multi-node harness exists; revisit if `processing_nodes_test.cpp`'s disabled cases or `processing_multi_test` get resurrected.
