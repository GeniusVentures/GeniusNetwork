# Phase 06: Capability & Validation Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-03
**Phase:** 06-Capability & Validation Foundation
**Areas discussed:** CanExecute architecture, CanExecute result shape, Capability discovery, Resource validation depth, CAP vs existing validation, Validation layer source, Toggle granularity, Toggle mechanism

---

## CanExecute Architecture

| Option | Description | Selected |
|--------|-------------|----------|
| New standalone class | CapabilityValidator — own header/impl, owns all capability queries. Cleanest separation, easiest to unit-test. | ✓ |
| ProcessingManager method | Keeps capability check colocated with Process(). Simpler, but ProcessingManager grows. | |
| Executor-level method | Each executor exposes CanExecute(job). ProcessingManager aggregates. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Before download | Validate before downloading large inputs/models. | |
| Before claiming work | Validate before claiming the job from the network. | ✓ |
| Both gates | Two-phase: coarse before claiming, detailed before downloading. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Synchronous | CapabilityValidator::CanExecute(job) returns result directly. | |
| Async with callback | Matches ProcessingManager's existing async patterns. | ✓ |
| Cached + sync | Query once at startup, fast sync lookup against cached caps. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Injected | Passed to ProcessingManager constructor/factory. Enables mocking. | |
| Internal | ProcessingManager constructs its own CapabilityValidator. | ✓ |
| You decide | Claude picks based on existing patterns. | |

**User's choice:** Standalone class, before claiming work, async with callback, internally constructed.
**Notes:** Clean separation of concerns. Scheduler calls CanExecute before claiming.

---

## CanExecute Result Shape

| Option | Description | Selected |
|--------|-------------|----------|
| C++ struct only | No proto dependency in SGProcessingManager. Caller serializes for wire if needed. | ✓ |
| Protobuf message | New proto message. Cross-language, matches gRPC patterns. | |
| Both | C++ struct internally + proto for wire. Conversion layer between. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Flat list with category tags | One list of UnmetRequirement structs, each tagged with a category enum. | ✓ |
| Categorized sections | Separate fields: vulkan_issues, mnn_issues, pass_type_issues, resource_issues. | |
| You decide | Claude picks the natural structure. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal: yes + executor ID | Just executable=true plus which executor was selected. | ✓ |
| Rich: selected caps snapshot | Includes executor identity, compatibility identities, resource estimates. | |
| Full: all queried caps | Returns the full capability snapshot. Heavy but complete. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Hash of capability snapshot | Hash the Vulkan device properties + driver version + MNN backend info at startup. | ✓ |
| Explicit version fields | Executor reports its own version. Stability by convention. | |
| You decide | Claude picks the simplest mechanism. | |

**User's choice:** C++ struct only, flat list with category tags, minimal acceptance, hash-based identity.
**Notes:** CAP-06 stability via hash, not version strings. Deterministic and tamper-evident.

---

## Capability Discovery

| Option | Description | Selected |
|--------|-------------|----------|
| Startup query + cache | Query once at startup, cache snapshot. CanExecute checks against cache. | ✓ |
| Per-call query | Query fresh on every CanExecute call. | |
| Static registration | Each executor registers capabilities at compile time. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse existing | Use VkPhysicalDevice from RenderProcessor's context. No duplicate instance. | ✓ |
| Own temporary instance | Lightweight VkInstance/VkPhysicalDevice just for querying. | |
| You decide | Claude weighs tradeoffs. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Registry of known MNN processors | Each registered processor declares supported formats/quantizations at registration time. | ✓ |
| Probe MNN backends directly | Query MNN's Backend::Info for each backend type. | |
| Both: registry + probe | Registry for format claims, MNN probe for backend availability. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Startup only | Query once, cache forever. Matches stable identity requirement. | ✓ |
| Refreshable on demand | CapabilityValidator exposes a Refresh() method. | |
| Auto-refresh on change | Watch for driver/device changes and auto-refresh. | |

**User's choice:** Startup query + cache, reuse existing device, registry-based MNN, startup only.
**Notes:** No runtime refresh — matches CAP-06 stability. If hardware changes, node restarts.

---

## Resource Validation Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, for CPU processors | Check instruction sets for CPU-bound processors. | |
| No, Vulkan/MNN only | All MNN on Vulkan after Phase 01.1. No current consumer. | ✓ |
| Stub for future use | Add infrastructure but no active checks. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Critical subset | Limits that would actually cause job failure. | ✓ |
| Render-critical only | Only limits RenderProcessor actually hits. | |
| Comprehensive | All ~100 VkPhysicalDeviceLimits fields. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, estimate and check | Estimate VRAM, check against heap sizes. Prevents OOM. | ✓ |
| No, limits only | Validate hard limits, don't estimate memory consumption. | |
| Warn but don't block | Estimate and warn if close, but don't reject. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, check disk | Estimate output size, check available disk. | ✓ |
| No, Vulkan/GPU only | Disk is OS-level concern outside Vulkan's domain. | |
| You decide | Claude decides. | |

**User's choice:** No CPU checks, critical Vulkan limits, estimate GPU memory, check disk space.
**Notes:** Comprehensive resource validation prevents OOM and disk-full failures mid-job.

---

## CAP vs. Existing Validation

| Option | Description | Selected |
|--------|-------------|----------|
| Sit alongside | CheckProcessValidity stays as-is. CanExecute is separate step. | ✓ |
| CanExecute subsumes it | CanExecute calls CheckProcessValidity internally. | |
| Replace it | CanExecute replaces CheckProcessValidity entirely. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Structure first | CheckProcessValidity first (cheap), then CanExecute (expensive). | ✓ |
| Capability first | CanExecute first — no point validating structure if node can't run it. | |
| You decide | Claude picks the obvious order. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Inside Process() | ProcessingManager calls CanExecute internally. Guaranteed gate. | |
| Caller's responsibility | Scheduler calls CanExecute before Process(). | ✓ |
| Both | Gate inside Process() AND expose publicly. | |

**User's choice:** Sit alongside, structure first, caller's responsibility.
**Notes:** Clean separation. Scheduler validates before claiming; Process() trusts the caller.

---

## Validation Layer Source

| Option | Description | Selected |
|--------|-------------|----------|
| SDK-provided only | No vendoring. Layers must be present on system (Vulkan SDK). | |
| Vendor binaries only | Build Vulkan-ValidationLayers as thirdparty submodule. | |
| Hybrid: SDK preferred | Use SDK layers if present, fall back to vendored. | |

**User's choice (free-text):** "Doesn't SPIRV-Tools handle validation?" — clarified that spirv-val validates SPIR-V bytecode, while validation layers validate Vulkan API usage. They're complementary.

**User's choice (free-text):** "Does vk-bootstrap not have calls for this? I would prefer not to vendor anything further in thirdparty" — clarified that vk-bootstrap enables layers but doesn't ship them.

**User's choice (free-text):** "This runs on many types of devices, I don't think we can rely on the Vulkan SDK being installed on phones. If this is a requirement to run a job, I suppose VVL is a must?" — clarified that validation layers are NOT a runtime requirement; they're a debugging tool disabled in production.

| Option | Description | Selected |
|--------|-------------|----------|
| NDK-provided (Android), SDK (desktop) | Android NDK ships layers. Desktop needs SDK. No vendoring. | |
| Build from source, ship with app | Build as part of thirdparty, bundle with app. | |
| Debug builds only, optional | Best-effort — enabled if available, silently skipped if not. | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| By name | Use vk-bootstrap's enable_validation_layers(). Standard approach. | ✓ |
| Explicit path | Load from specific path via VK_LAYER_PATH. | |
| You decide | Claude picks. | |

**User's choice:** Debug-only, best-effort. Load by name via vk-bootstrap.
**Notes:** Explicit preference against vendoring. Validation layers are a development convenience. Overrides VVAL-01's literal vendoring requirement.

---

## Toggle Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| RenderProcessor only | Only RenderProcessor's VkInstance gets the toggle. | ✓ |
| All SGProcessingManager Vulkan | Every Vulkan instance gets validation. | |
| You decide | Claude decides. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Global flag | One flag controls all. Simpler. | ✓ |
| Per-instance | Each VkInstance independently toggleable. | |
| You decide | Claude picks. | |

**User's choice:** RenderProcessor only, global flag.
**Notes:** Narrowest scope. MNN instances are untouched.

---

## Toggle Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| CMake option | -DENABLE_VULKAN_VALIDATION at build time. Debug default ON, Release OFF. | ✓ |
| Config file | Read from config JSON at startup. Toggleable without rebuild. | |
| Both | CMake default + config override. | |

| Option | Description | Selected |
|--------|-------------|----------|
| In CONTEXT.md | Decision lives here. Downstream agents read it. | ✓ |
| Separate ADR | Standalone Architecture Decision Record in docs/. | |
| Code comment + CONTEXT.md | Primary in code, reference from CONTEXT.md. | |

**User's choice:** CMake option, documented in CONTEXT.md.
**Notes:** VVAL-04 satisfied by documenting the decision here instead of a separate ADR.

---

## Claude's Discretion

- Exact `UnmetRequirement` struct field layout and category enum member names
- Exact Vulkan device limit fields to query (beyond the critical subset in D-14)
- GPU memory estimation formula
- Disk space check implementation
- CapabilityValidator's exact async callback signature
- Hash function for executor identity snapshot

## Deferred Ideas

- Vulkan validation layer vendoring — explicitly dropped in favor of best-effort (D-20)
- CPU instruction set validation (CAP-05) — skipped since all MNN processors are on Vulkan
- Runtime capability refresh — skipped in favor of startup-only snapshot
- Per-instance validation layer toggle — skipped in favor of global flag
