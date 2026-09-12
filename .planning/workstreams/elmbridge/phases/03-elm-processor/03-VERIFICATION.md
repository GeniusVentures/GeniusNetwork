---
status: passed
phase: 03-elm-processor
verified: 2026-09-11
score: 4/4
requirements_verified: [GEN-01, GEN-02, GEN-03, RES-01]
next_action: ""
next_command: ""
human_verification: []
---

# Phase 3: ELM Processor — Verification Report

**Goal:** The ELM processor executes one causal-LM work item end-to-end from a pinned cache bundle and emits a complete, work-item-tagged result envelope.

**Verdict: PASSED** — 4/4 requirements verified against the live tree; all five success criteria TRUE with evidence. Two documented seams carried to Phase 4 (stop-string schema; embedding-role schema) — both escalated in STATE.md TODOs, neither blocks this phase's goal.

## Success Criteria Audit

### SC-1: End-to-end work-item execution ✓
- The generation loop is MNN's `Llm::response()` driven by the gated processor TU (`processing_processor_elm.cpp`): chat template + tokenization + prefill + KV-cache decode + sampling + detokenization all inside the linked engine; per-work-item settings flow via `set_config` BEFORE `load` (Pitfall 3 hard ordering — verified in source: the set_config + dump_config assert block sits between the VulkanInitMutex scope and the LlmLoadMutex scope).
- Settings honored: temperature/top_p defaults (1.0/1.0), max_output_tokens presence-flag (absent → key omitted + `-1` sentinel → model's own llm_config.json default; NO 512 hard default), seed via the D-12 fork patch.
- Counts: `LlmContext::prompt_len` / `output_tokens.size()` are the authority (reconcile block reads `llm->getContext()`; `gen_seq_len` mismatch logs a warning — Pitfall 1 discipline).
- `finish_reason` ∈ {stop, max_tokens, cancelled, error} — the complete D-08..D-11 mapping table implemented including TIMEOUT→error-with-detail and CHECK_LLM_RUNNING early-return→error.
- Stop strings: `ElmStopStringStreamBuf` (16 unit legs green: exclusion, split-across-writes, earliest-match, overlap window, cancel-latch separation).
- **Real-model proof:** `sgproc_elm_processor_test.exe` with the staged Qwen fixture: 12/12 legs green — actual generations ran (209–463 byte envelopes, `finish_reason=max_tokens` observed), determinism byte-identical, cancel produced a 353-byte partial envelope.

### SC-2: Seeded determinism + no silent no-op ✓
- `SameSeedByteIdentical`: two full runs, identical envelopes (byte-equal JSON) — PASSED on the real model.
- `DifferentSeedDiffers`: PASSED (sampling RNG participates).
- `SeedLandsInDumpConfig`: direct set_config→dump_config round-trip asserted on the staged bundle — PASSED.
- Processor-side guard: the dump_config round-trip assert (5 grep hits in the TU) fails closed with `ELM_CONFIG_FAILED` on any key mismatch — the SC-2 mechanism.

### SC-3: Prompt cancellation, deliberate join, pin zero ✓
- `CancelLatency`: `finish_reason=cancelled`, TRUE abort latency (Cancel()→return, includes teardown) ≪ full baseline, partial text + measured counts present, cancel thread joined BEFORE assertions — PASSED.
- Fork patch D-13 (`Llm::cancel()`) verified in the installed header and compiled into the rebuilt MNN.lib (obj timestamps postdate the patch commit).
- Pin zero: `PinReachesZeroAfterError` (error side) green; the pin is held by value in scope (RAII on every return path) — the cancelled path releases through the same scope exit.

### SC-4: Envelope completeness ✓
- `ElmEnvelopeToJson` emits exactly work_item_id, text, prompt_tokens, completion_tokens, finish_reason, model_manifest_hash (+ nested error {code,message} only on error) — 5 matrix legs green in the unit target AND the processor-level matrix leg green.
- Provenance = `pin.GetHash()` (the cache entry's manifest digest).

### SC-5: Load isolation + order permutation + no leaks ✓
- Lock split shipped: `LlmLoadMutex()` in `vulkan_init_guard.hpp` (D-03 placement); the TU's ONLY VulkanInitMutex scope encloses createLLM; the ONLY LlmLoadMutex scope encloses load — verified in source.
- `MnnLoadNotStalledByLlmLoad` (D-02 leg 2): non-ELM MNN call completed while the ELM load was in flight — PASSED.
- `TwoLlmLoadsSerialize` (D-02 leg 1): both loads joined without deadlock — PASSED (with the documented warm-cache timing correction).
- `OrderPermutation`: per-item envelopes identical across execution orders (fresh `Llm` per work item) — PASSED.
- Zero temp-dir materializers repo-wide (grep: only the shim's own retirement comment); `mnn_llm_test` 2/2 green.

## Requirements Traceability

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| GEN-01 | End-to-end causal-LM execution with accurate counts | ✓ verified | Processor TU + 12/12 fixture legs + real generations; SC-1 audit above |
| GEN-02 | Prompt mid-generation cancellation via fork patch | ✓ verified | D-13 patch committed + rebuilt; CancelLatency green with partial counts; streambuf-poll wiring (Q1 resolution) |
| GEN-03 | Processor conventions: narrowed lock, cache as single materialization point, no leaks | ✓ verified | Two-lock discipline + zero materializers + pin RAII + order permutation + both D-02 legs |
| RES-01 | Envelope carries work_item_id/text/counts/finish_reason (+manifest hash provenance) | ✓ verified | Envelope unit 5 matrix legs + processor matrix leg; SC-4 audit |

Note: RES-01's subtaskid↔work_item_id mapping half is Phase 4's transport wiring (the phase boundary excluded grid routing); the envelope CONTENT contract is fully verified here.

## Test Suite Status

All 20 SGProcessingManager test binaries exit 0 (fixture-present run, 2026-09-11): artifact_serializer, capability_validator, sgproccapability_elm_resources, capture_smoke, sgprocelmruntime_{cache,envelope,manifest}, sgprocmanagerexec_{budget,cancellation,checkpoint,leak,migration,progress,timeout}, sgprocbase_elm_job_schema, mnn_llm, mnn_tensor_fp4, sgproc_elm_processor, diff_utils, quantization.

## Deviations & Escalations (accepted)

1. **ElmEntryPreflight bridge** (03-03): the documented cross-generated-set conflict resolved by the prescribed plain-value pattern — additive, contract intact.
2. **Embedding-role gap** (03-04, user-approved): test-side injection + Phase 4 escalation — recorded in STATE.md TODOs with the decision trail.
3. **Stop-string fixture shortfall** (03-04): model continuation didn't emit the chosen stop string; negative path asserted; truncation mechanics proven by the 16 unit legs. The stopStrings PARAMETER seam is fully wired and fixture-testable.
4. **Pre-existing submodule dirt** (03-04): unrelated to the chain; all five chain gitlinks match exactly.

## Commit Chain (five levels, innermost-first)

MNN `04855552` → thirdparty `1a0ad3e` → SGProcessingManager `7ffc911` (tip) → SuperGenius `d919363b1` → root `5de753f`.

## Verdict

Phase 3 goal achieved. Ready for phase completion and Phase 4 planning (which inherits the two schema-amendment seams recorded in STATE.md TODOs).
