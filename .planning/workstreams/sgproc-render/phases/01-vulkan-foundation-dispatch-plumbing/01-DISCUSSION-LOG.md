# Phase 1: Vulkan Foundation & Dispatch Plumbing - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-29
**Phase:** 1-Vulkan Foundation & Dispatch Plumbing
**Areas discussed:** Vulkan bootstrap approach, Device selection policy, Concurrent-init lock scope, RenderProcessor context lifecycle

---

## Vulkan Bootstrap Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Adopt vk-bootstrap (Recommended) | MIT-licensed helper automating instance/device/queue creation, handles VK_KHR_portability_subset/MoltenVK dance. One new small thirdparty submodule. | |
| Hand-roll instance/device creation | Zero new vendoring — write the boilerplate directly against Vulkan-Headers/Loader. More code to write/audit, especially MoltenVK portability-subset edge case. | |

**User's choice:** "Ask me again in the planning phase" (free text) — explicitly deferred to `/gsd-plan-phase`, not decided now.
**Notes:** User wants more information before locking this in. Captured as D-01 in CONTEXT.md with instruction for planner/researcher to surface the trade-off explicitly.

---

## Device Selection Policy (CTX-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Discrete GPU > integrated > CPU, tie-break by VRAM (Recommended) | Standard Vulkan sample pattern; rejects CPU/software in production per issue #7's no-software-fallback constraint; ties broken by largest device-local heap. | ✓ |
| Prioritize queue-family capability first | Score by single queue family supporting both graphics+compute first, then type/VRAM as tie-breakers. | |
| You decide | Let planner/researcher work out the exact scoring function, as long as documented and deterministic. | |

**User's choice:** Discrete GPU > integrated > CPU, tie-break by VRAM (recommended option)
**Notes:** None additional.

---

## Concurrent-Init Lock Scope (CTX-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — fix all 3 MNN sites now (Recommended) | Matches CTX-02 as written and research's reconciled recommendation. Migrate MNN_Image's mutex plus add guarding to MNN_String/MNN_Volume, all sharing one process-wide VulkanInitGuard alongside RenderProcessor's init path. | ✓ |
| Narrow it — only share the lock between MNN_Image and RenderProcessor | Leaves MNN_String/MNN_Volume's pre-existing unguarded Vulkan init as-is. Smaller blast radius but doesn't fully satisfy CTX-02's literal wording. | |

**User's choice:** Yes — fix all 3 MNN sites now (recommended option)
**Notes:** Codebase check during discussion confirmed only `MNN_Image` currently has a mutex; `MNN_String`/`MNN_Volume` have none. User confirmed the wider scope (touching 2 existing production files) is acceptable.

---

## RenderProcessor Context Lifecycle

| Option | Description | Selected |
|--------|-------------|----------|
| Lazy — on first render-type job (Recommended) | Avoids holding GPU resources idle on nodes that spend most of their time on MNN inference/retrain and never see a render job. | ✓ |
| Eager — at ProcessingManager/node startup | Context always resident once node starts. Simpler lifecycle, but every node pays the resource cost even without a render job. | |

**User's choice:** Lazy — on first render-type job (recommended option)
**Notes:** None additional.

---

## Claude's Discretion

- Exact shape/naming of the shared synchronization primitive (e.g. `VulkanInitGuard`) and how `MNN_String`/`MNN_Volume` are refactored to use it
- Exact form of the `ParseBlockSize()` type-guard fix (DISP-01)
- Exact shape of the new `PassType`-keyed dispatch map (DISP-02)

## Deferred Ideas

None raised outside phase scope. Vulkan bootstrap approach (vk-bootstrap vs. hand-rolled) was deferred to the planning step of this same phase, not to a future phase.
