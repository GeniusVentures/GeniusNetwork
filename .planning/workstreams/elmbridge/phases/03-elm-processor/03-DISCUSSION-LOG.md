# Phase 3: ELM Processor - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-11
**Phase:** 3-ELM Processor
**Areas discussed:** VulkanInitMutex fix, Stop-string semantics, Finish-reason mapping, Fork patch shape

---

## VulkanInitMutex fix

### Lock strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated LlmLoadMutex | VulkanInitMutex guards only createLLM(); a NEW dedicated LlmLoadMutex serializes load() against other LLM loads but not the grid. Conservative; render/MNN never wait on an LLM load; two ELM items still serialize loads. | ✓ |
| Narrow to createLLM only | load() fully unlocked — concurrent LLM loads in parallel. Fastest, but requires verifying no shared mutable state in the MNN load path. | |
| Keep global, rely on cache | Current global lock across createLLM+load, relying on Phase 2's load-once-per-entry. Zero new risk but SC-5 explicitly demands other processors don't stall. | |

**User's choice:** Dedicated LlmLoadMutex
**Notes:** None.

### Load test

| Option | Description | Selected |
|--------|-------------|----------|
| Both legs, gated TU | SC-5's leg (non-ELM subtask unaffected during LLM load) + LLM-vs-LLM serialization leg without deadlock. Real MNN link. | ✓ |
| Non-ELM leg only | Only the SC-5 assertion; mutex serialization judged correct by inspection. | |
| Mock-based lock checks | Assert lock acquisition via mocks — no real MNN link, no timing assertions. | |

**User's choice:** Both legs, gated TU
**Notes:** None.

### Mutex home

| Option | Description | Selected |
|--------|-------------|----------|
| sgprocessing free fn | Free function next to VulkanInitMutex() (e.g. sgns::sgprocessing::LlmLoadMutex()) — same discovery pattern; MNN_Llm also switches to it. | ✓ |
| File-static in elm TU | Private to processing_processor_elm.cpp — smallest surface, but MNN_Llm can't share it. | |
| On the model cache | Exposed on ElmModelCache — couples cache to processor concerns. | |

**User's choice:** sgprocessing free fn
**Notes:** None.

### Old proc fate

| Option | Description | Selected |
|--------|-------------|----------|
| Migrate + delete mat. | MNN_Llm moves to the new lock discipline AND its temp-dir materializer is deleted (Pitfall 6 mandate). One discipline; leak class eliminated. | ✓ |
| Leave MNN_Llm alone | Only the ELM processor gets narrowed scope; two disciplines coexist; old processor retains its temp-dir leak. | |
| Migrate locks only | MNN_Llm migrates locks but keeps its materializer. | |

**User's choice:** Migrate + delete mat.
**Notes:** None.

## Stop-string semantics

### Stop strings

| Option | Description | Selected |
|--------|-------------|----------|
| Streambuf + USER_CANCEL | Custom streambuf scans decoded text as tokens arrive; on match trigger Llm::cancel() → unwind within a step. Prompt stop, honest counts, no wasted billed tokens. | ✓ |
| Post-hoc truncate | STACK.md's robust v1.0 suggestion: run to completion, truncate at stop string in post-processing. Zero fork surface but wasted generation + billed time. | |
| Streambuf + bound tighten | Detect match, force early return via max_new_tokens=0 nudge. Softer than USER_CANCEL — relies on mid-flight config change. | |

**User's choice:** Streambuf + USER_CANCEL
**Notes:** None.

### Scan window

| Option | Description | Selected |
|--------|-------------|----------|
| Incremental overlap | Check whether a stop string begins within the last (len-1 + slack) characters — handles multi-token matches. O(text × stops), cheap. | ✓ |
| Full rescan per token | Rescan all accumulated text every token. Simplest; O(tokens²). | |
| Periodic checkpoint | Check at boundaries/every N tokens; accepts overshoot. | |

**User's choice:** Incremental overlap
**Notes:** None.

### Output text

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude, OpenAI-style | Envelope text ends at the stop string start; stop string NOT included; count from output_tokens.size(). | ✓ |
| Include the stop string | Emit text including the stop string and count it. | |
| Configurable flag | Per-work-item stop_includes: bool setting. More schema surface. | |

**User's choice:** Exclude, OpenAI-style
**Notes:** None.

## Finish-reason mapping

### TIMEOUT map

| Option | Description | Selected |
|--------|-------------|----------|
| TIMEOUT → error | MNN internal timeout = execution fault (our bound fired unexpectedly) → 'error' with detail field; deadline/cancel-token → 'cancelled' per Phase 1 D-03. | ✓ |
| TIMEOUT → cancelled | Requestor sees incomplete either way; treats deadline and timeout alike. | |
| Add 'timeout' value | Fifth finish_reason value — widens the RES-01 contract. | |

**User's choice:** TIMEOUT → error
**Notes:** None.

### Cancel disambiguation

| Option | Description | Selected |
|--------|-------------|----------|
| Processor decides | The processor knows why it triggered USER_CANCEL: stop-string → 'stop' with truncated text; cancel-token/deadline → 'cancelled'. Envelope reports intent, not mechanism. | ✓ |
| Fork adds substatus | Separate status/flag in LlmContext carrying the reason — more fork surface, redundant. | |
| Envelope side-field | Both report 'cancelled'; stop-string hit surfaced via a separate field. Splits one fact across two fields. | |

**User's choice:** Processor decides
**Notes:** None.

### Partial output

| Option | Description | Selected |
|--------|-------------|----------|
| Include partial | Cancelled/error envelopes carry partial text + measured counts (Phase 1 D-03). Requestor sees what the budget bought. | ✓ |
| Counts only, no text | Counts without partial text. | |
| Include if small | Size-threshold knob. | |

**User's choice:** Include partial
**Notes:** None.

### Internal errors

| Option | Description | Selected |
|--------|-------------|----------|
| Error detail field | INTERNAL_ERROR/TIMEOUT → 'error' with code + message from ElmRuntimeError/ProcessingError; subtask finalizes on the published result — terminal, not re-grabbed (Pitfall 10). | ✓ |
| ProcessingError path | Throw instead of publishing — re-grab-loop risk on persistent model faults. | |
| No detail, just enum | Least schema, least diagnosable. | |

**User's choice:** Error detail field
**Notes:** None.

## Fork patch shape

### Seed shape

| Option | Description | Selected |
|--------|-------------|----------|
| Config key + assert | Sampler reads a 'seed' key; processor passes via set_config and tests assert via dump_config() round-trip (SC-2's no-silent-no-op mechanism). Matches temperature/top_p flow. | ✓ |
| Explicit setter API | Sampler::seed(uint32_t) / Llm::setSeed() — typed but more exposure surface. | |
| Config key + getter | Both wire format and a getter for assertion — largest patch, strongest guarantee. | |

**User's choice:** Config key + assert
**Notes:** None.

### Cancel shape

| Option | Description | Selected |
|--------|-------------|----------|
| Llm::cancel() method | Public one-liner setting mContext->status = USER_CANCEL (STACK.md shape); callable from any thread; per-step polls unwind. | ✓ |
| Cancel with reason | Carries stop-string vs job-cancel into MNN — redundant given processor-decides intent. | |
| Context status setter | General setStatus on LlmContext — breaks const-getContext() encapsulation for no v1.0 need. | |

**User's choice:** Llm::cancel() method
**Notes:** None.

### Patch build

| Option | Description | Selected |
|--------|-------------|----------|
| Gated + marker | Patches in thirdparty/MNN on dev_elmruntime-compatible branch; usage guarded behind SGPROC_HAS_MNN_LLM-style gate + compile-time marker so stock MNN still builds; degraded path documented. Four-level commit chain. | ✓ |
| Hard require patch | ELM processor compiles only against patched fork; simpler code, harder pointer-drift failure. | |
| Runtime detection | Try-config/check-dump_config + symbol resolution — most resilient, most complexity. | |

**User's choice:** Gated + marker
**Notes:** None.

---

## Claude's Discretion

- Exact compile-time marker name/mechanism for fork-patch detection (follow the SGPROC_HAS_MNN_LLM CMake convention)
- Streambuf implementation details (buffer sizing, flush cadence, UTF-8 boundary handling)
- Slack margin and precise scan-loop structure for the overlap window
- Order-permutation test approach (two real gated sessions vs mock-Llm seam — must prove SC-5 isolation either way)
- Envelope builder internal structure (struct shape, serialization to output buffers)
- Unit-test structure/file layout (follow sgproc-render conformance-test pattern)
- LlmLoadMutex() declaration location (alongside VulkanInitMutex() per existing convention)
- Fork-branch name and patch-commit conventions in thirdparty/MNN

## Deferred Ideas

None — discussion stayed within phase scope.
