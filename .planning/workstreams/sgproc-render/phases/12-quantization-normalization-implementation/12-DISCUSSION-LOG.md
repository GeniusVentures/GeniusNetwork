# Phase 12: Quantization / Normalization Implementation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-12
**Phase:** 12-Quantization / Normalization Implementation
**Areas discussed:** Which hash must match cross-machine, MNN float quantization technique, IEEE-754 special-value canonicalization, SECV-01 wrong-result counter-test

---

## Which hash must match cross-machine

Codebase scouting during discussion found: `ProcessOutput.combinedHash` (`ExecutionManifest.manifestHash`) bakes in `executorIdentity` (SHA-256 of Vulkan device name/vendor/driver, `capability_types.hpp`) and `gpuMemoryUsedBytes` — both genuinely machine-specific. This explains Phase 11's render capture (`contentHashMatch: true`, `combinedHashMatch: false`) and means no output-data quantization can make `combinedHash` match cross-machine.

| Option | Description | Selected |
|--------|-------------|----------|
| ProcessingResult.hash + contentHash | Hash only actual output bytes; matches SC2's literal test and research's "cross-node-authoritative hash" framing | |
| ProcessOutput.combinedHash (manifest-level) | The literal thing ROADMAP/REQUIREMENTS wording says must match; structurally can't cross-machine | |
| All three, with executorIdentity excluded for tolerance purposes | Also modify ComputeManifestHash to compute a tolerant variant | ✓ (initial pick) |

**User's choice (initial):** "All three, with executorIdentity excluded for tolerance purposes."

**Follow-up 1 — should `gpuMemoryUsedBytes` also be excluded from a tolerant manifest hash?**

| Option | Selected |
|--------|----------|
| Yes, exclude gpuMemoryUsedBytes too | ✓ (superseded below) |
| No, only exclude executorIdentity | |
| Exclude all resource/telemetry fields | |

**Follow-up 2 — new separate field vs. redefine existing `combinedHash`?**

| Option | Selected |
|--------|----------|
| New separate field, existing combinedHash untouched | (superseded below) |
| Redefine the existing field | |

User's answer here was freeform: *"I think it's most important that a validator can compare chunk hashes and combined hashes and make sure their result is the same as another node. i.e. the chunk and combined hash in this processor for instance."* — clarifying that the real target is the processor-level chunk+combined hash (what `ProcessingValidationCore` compares for consensus), not the manifest-level field at all.

**Final confirmation:**

| Option | Selected |
|--------|----------|
| Yes, that's the scope (processor-level only, manifest untouched) | ✓ |
| Not quite — let me clarify | |

**User's final choice:** Quantization targets only the processor-level `ProcessingResult.hash` + chunk hashes. `ProcessOutput.combinedHash`/`ExecutionManifest.manifestHash` is untouched; its cross-machine mismatch is expected/acceptable. No manifest/artifact code changes in this phase.
**Notes:** The initial "exclude executorIdentity from manifest hash" direction (and the gpuMemoryUsedBytes follow-up) was explored but superseded once the user clarified the actual consensus-relevant hash lives entirely at the processor level and doesn't need manifest changes at all. Captured as D-01/D-02 in CONTEXT.md, including a flag for Phase 13 to reconcile ROADMAP/REQUIREMENTS "combined hash" wording.

---

## MNN float quantization technique

| Option | Description | Selected |
|--------|-------------|----------|
| Decimal rounding to N significant digits | std::round-based, scale/round/unscale | |
| Fixed-point scale-round-cast to integer grid | q = round(x*S)/S, deterministic, research's literal recommendation | ✓ |
| Mantissa bit-masking | Zero low-order mantissa bits directly | |

**User's choice:** Fixed-point scale-round-cast to integer grid.

**Follow-up — absolute grid vs. relative/ULP-based, given divergence appears magnitude-proportional (768 ULP but only 1.043e-7 abs)?**

| Option | Selected |
|--------|----------|
| Single absolute epsilon, scoped to this milestone's fixtures | ✓ |
| Relative/ULP-based quantization (mask mantissa bits) | |

**Follow-up — safety margin above measured maxAbsDelta (~1.043e-07)?**

| Option | Selected |
|--------|----------|
| ~10x margin → grid step ≈ 1e-6 (scale factor 2^20) | ✓ |
| ~50-100x margin → grid step ≈ 5e-6-1e-5 | |
| You decide — pick during planning/implementation | |

**Notes:** User accepted the recommendation at each step without pushback. Power-of-two scale factor chosen for exact float round-trip.

---

## IEEE-754 special-value canonicalization

**+Inf/-Inf:**

| Option | Selected |
|--------|----------|
| Keep +Inf and -Inf distinct | ✓ |
| Collapse +Inf and -Inf to one canonical value | |

**Denormals:**

| Option | Selected |
|--------|----------|
| Flush denormals to signed zero | ✓ |
| Round denormals through the normal fixed-point grid | |

**Signed zero:**

| Option | Selected |
|--------|----------|
| Collapse to one canonical zero, sign discarded | ✓ |
| Keep sign-preserving canonical zeros | |

**Canonical NaN:**

| Option | Selected |
|--------|----------|
| Standard quiet NaN, 0x7FC00000 (hardcoded literal) | ✓ |
| Use platform's native quiet_NaN() at canonicalization time | |

**Notes:** All four sub-decisions accepted the recommended option. Rationale consistently: preserve genuine divergences (distinct Inf signs) while collapsing artifacts of hardware/compiler noise (denormals, zero sign) to fixed representatives, per PITFALLS.md's "canonicalize before rounding, as an explicit first branch" guidance.

---

## SECV-01 wrong-result counter-test

| Option | Description | Selected |
|--------|-------------|----------|
| Corrupted MNN model weights | Byte-flip a copy of the model file, re-run, assert hash differs | ✓ |
| Wrong shader constant | Alter a render pass push-constant, re-run, assert hash differs | (added via follow-up) |
| Truncated/lower-precision inference run | Harder, more adversarial "plausible but wrong" test | |

**User's choice:** Corrupted MNN model weights (initially selected alone via multiSelect).

**Follow-up — cover both paths or MNN only?**

| Option | Selected |
|--------|----------|
| Cover both paths | ✓ |
| MNN only — render's quantization is lower-risk | |

**Follow-up — where should the test live?**

| Option | Selected |
|--------|----------|
| New CTest target, alongside Phase 09's conformance suites | ✓ |
| Standalone tool under tools/capture/ | |

**Follow-up — what should the test assert?**

| Option | Selected |
|--------|----------|
| Binary: hashes simply differ | ✓ |
| Also assert the divergence exceeds the quantization grid step | |

**Notes:** Ends up covering both render and MNN with a simple ASSERT_NE, running automatically in CI alongside Phase 09's existing conformance suites.

---

## Claude's Discretion

- Exact file/target names for the new SECV-01 CTest suite
- Exact mechanics of "corrupting" the MNN model file and the render shader constant (which byte(s)/constant to perturb)
- Whether the render SECV-01 case needs the `GTEST_SKIP()`-on-no-Vulkan-device pattern (almost certainly yes)

## Deferred Ideas

- Modifying `ComputeManifestHash`/`ExecutionManifest` to exclude `executorIdentity`/`gpuMemoryUsedBytes` for a cross-machine-comparable manifest-level hash — explored, then superseded (see "Which hash must match cross-machine" above)
- Truncated/lower-precision inference run as the SECV-01 mechanism — not chosen, noted as a possible harder follow-up test
- Relative/ULP-based (mantissa bit-masking) quantization — not chosen for this milestone's fixed-constant scope
