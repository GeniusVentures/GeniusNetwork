# Phase 4: Grid Integration & E2E Proof - Context

**Gathered:** 2026-09-14
**Status:** Ready for planning

<domain>
## Phase Boundary

A funded ELM job flows through the real single-node grid — split into per-work-item subtasks, executed on the Phase 2/3 runtime (cache + processor), published on the existing results path with escrow settling by measured wall-clock — proven by the empty-cache E2E that is this milestone's acceptance criterion. This phase delivers, spanning BOTH repos (splitter + submit wiring in SuperGenius; schema amendments + grid routing in SGProcessingManager):

1. **ELM splitter + submit wiring** (JOB-02, RES-02 transport half) — `processing_tasksplit_elm.*` (sibling of `processing_tasksplit.cpp:44`); `GeniusNode::ProcessImage` ELM branch replaces the interim `ELM_SUBMIT_UNAVAILABLE` early return (:2266-2284) with split → escrow → enqueue; `elm_subtask_map` embedded in task JSON per the Phase 1 design
2. **Grid routing to the ELM processor** — the worker path (`ProcessingCoreImpl::ProcessSubTask` → `ProcessingManager::Process/ProcessInternal`) routes ELM work items to `ElmProcessor::StartProcessingElm` with the production cache (`CreateProductionElmModelCache` has ZERO callers today) and validator; `input_uri` prompt transport resolution (fetch → promptText) lands here
3. **Schema amendments** (both STATE.md TODO escalations from Phase 3) — `stop` array on `ElmGeneration` (requestor stop strings end-to-end) + `embedding_file` optional manifest role
4. **Settlement build-out** — `grab_time_usec`/`finish_time_usec` on the envelope; `BuildPayoutOutputs` ELM branch (proportional OD-3 split, refund output, conservation); terminal-envelope publication (over-time → published terminal state, never silent re-grab)
5. **Results artifact convention** (RES-02) — ELM branch feeding the EXISTING `SaveASync` dual-save loop; always-artifact text; inline payload = envelope-minus-text
6. **Empty-cache E2E** (E2E-01) — one node, both roles, real ipfs:// fixture transport, 2 work items / 1 manifest, full refund proof, overtime leg
7. **Regression gate + anti-scope audit** (E2E-02, JOB-04) — non-ELM byte-identical across splitter/funding/validation/results; removed scope stays removed in code and schema

**Out of scope:** GCS-side aggregation UX (GCS workstream), multi-node partitioning, streaming events, `/v1` surfaces, proto changes, cross-node bit-identical generation, capability/cache advertising.

Requirements: JOB-02, JOB-04, RES-02, E2E-01, E2E-02, E2E-03.

</domain>

<decisions>
## Implementation Decisions

### Schema Amendments (both STATE.md TODO escalations — closed here)
- **D-01:** **Amend `ElmGeneration` with a `stop` array NOW** — schema + quicktype regen (zero hand-edits to `generated/`) + validator bounds + the splitter/submit wiring passes it through to the `StartProcessingElm` `stopStrings` parameter. Requestor stop strings work end-to-end in v1.0. No parse-only stub (a silently-ignored field is exactly the set_config trap Pitfall 2 warns about)
- **D-02:** **Bound the stop array** — max 4 stop strings, each 1–128 chars UTF-8, no empty strings; reject-at-parse on violation, never clamp (Phase 1 D-05 discipline). OpenAI's max-4 convention
- **D-03:** **Add `embedding_file` as a 6th OPTIONAL manifest role** — NOT added to `kRequiredRoles` (embedding-less models unaffected); materialized at `embeddings_bf16.bin` (MNN DiskEmbedding default when `llm_config.json` has no `tie_embeddings`); schema pattern update + quicktype regen + `RoleFileName` entry + cache publishes it when declared. The Phase 3 test-side post-Acquire injection workaround retires

### Settlement Stamps & Refund (FUND-03 build-out per 01-DESIGN-SETTLEMENT)
- **D-04:** **Stamps ride the `ElmEnvelope`** — add `grab_time_usec`/`finish_time_usec` as additive envelope fields; `ElmEnvelopeToJson` emits them. The stamps travel with the exact artifact the settlement reads via the existing `fetchOutputData` lambda in `FinalizeQueueProcessing` — one fetch, no second carriage mechanism. (Phase 3's envelope had exactly six keys; this is an additive, key-addition-compatible change)
- **D-05:** **The E2E proves the FULL refund mechanics** — escrow held = declared max; payout = sum of measured windows (proportional OD-3 split); refund output returns the remainder to the escrow source address; conservation check (Σoutputs == escrow_amount) holds. A short `max_output_tokens` ensures measured ≪ declared so the refund is non-trivially nonzero. Not unit-only, not conservation-only

### Results Artifact Convention (RES-02, Pitfall 12)
- **D-06:** **Reuse the existing `SaveASync` dual-save loop** — the ELM execution path derives its output URL the way non-ELM jobs do (FileManager `cacheDir` + `/results/`) and feeds the existing loop (:1847-1965) via an ELM branch, NOT a parallel save path. `ipfs_results_data_id` carries the artifact location back exactly as today; the gossip results channel and IPFS artifact path stay unchanged
- **D-07:** **Always-artifact — no inline text, no 4KB threshold** — the inline `SubTaskResult` payload carries the envelope WITHOUT text (work_item_id, prompt/completion token counts, finish_reason, model_manifest_hash, stamps, artifact hash); the text lives ONLY in the content-addressed artifact. One convention, no size-dependent dual behavior, no boundary case

### E2E Test Shape (E2E-01, the milestone acceptance criterion)
- **D-08:** **One GeniusNode (`is_processor=true`) plays both roles** — submit → gossip → grab → execute → publish → payout all on one node. The true single-node grid path; no two-node flake surface
- **D-09:** **Real `ipfs://` fixture transport** — the test publishes the staged fixture dir via FileManager to ipfs:// and the job JSON points at real URIs; the E2E exercises the REAL download path (empty cache → fetch → verify → generate). Not file:// shortcuts
- **D-10:** **2 work items on the SAME manifest** — proves the 1:1 splitter mapping, the `elm_subtask_map`, single-flight dedup (two subtasks, one download), and order-independence in a single run; the ~557MB model cost is paid once
- **D-11:** **Include the overtime leg** — a second E2E leg with tiny funding (e.g. `maximum_processing_hours` ≈ model-load time) drives a real deadline overrun → cancel → terminal envelope (`cancelled`/`BUDGET_EXCEEDED`) published → NOT re-grabbed. Pitfall 10's E2E verification leg ("overtime job ends terminal, not re-grabbed")

### Carried Forward (locked by roadmap/prior phases — not re-decided here)
- Splitter mapping (Phase 1 design, `01-DESIGN-SUBTASK-MAPPING`): 1 work item → 1 subtask, one notional subtask-unique chunk, `elm_subtask_map` in task JSON, envelopes key on `subtaskid` + echo `work_item_id`, uniqueness inheritance across all three id domains
- Settlement design (Phase 1, `01-DESIGN-SETTLEMENT`): sum of per-subtask windows, milli-hour truncation at PRECISION=6, cap at escrow max, proportional split with deterministic tiebreak, malformed-entry filter, terminal envelopes ride the success-shaped path `ValidateIndividualResult` accepts
- Three-clock + lock wiring (Phase 1, shipped): `DeriveElmClocks` → `SetProcessingTimeout` before `CreateSubTaskQueue` (`processing_service.cpp:727-775`); per-subtask deadline from own grab
- Validation `none` (Phase 1, shipped): `ElmValidationModeOk` defensive gate at `FinalizeQueueProcessing`; E2E must run `validation: none` (Pitfall 2 — never enable redundant validation for text)
- Rate record (Phase 1, shipped): `CreateElmRateRecordCRDTTransaction` writes the sibling `elm_rate` key — Phase 4 wires the production call site
- Processor contract (Phase 3, shipped): `StartProcessingElm(chunkhashes, promptText, stopStrings, elm, execCtx, cache, capabilityValidator)`; base `StartProcessing` fail-closed; set_config-before-load; `LlmContext` count authority; pin RAII; split locks
- Scope discipline (D-004): no capability/inventory/cache advertising, no bidding/negotiation, no requester-side selection, no worker `/v1`, no proto changes, no SuperGenius-side aggregation
- Submodule commit discipline: innermost-first across the chain (SGProcessingManager → SuperGenius → root; MNN untouched this phase)
- Test infra: `SGPROC_TEST_DISCOVERY` gating, CTest `TIMEOUT` properties (×4 margin), wait-condition patterns (no sleep-based tests), `weak_from_this` in every new timer/callback

### Claude's Discretion
- The exact ELM-branch shape inside `ProcessImage` (how the `elm_subtask_map` is written into task JSON and how `elms[]` iterate into subtasks — follow the Phase 1 design's map placement verbatim)
- How `input_uri` prompt resolution integrates: whether prompt fetch happens in `ProcessInternal`'s ELM branch or a pre-step (the processor never fetches — `promptText` arrives resolved)
- The precise overtime-leg funding value and whether it lands in the same test binary or a separate target (CTest TIMEOUT budget governs)
- The production cache's construction site (where `CreateProductionElmModelCache` gets its single call — likely ProcessingManager or ProcessingCoreImpl initialization) and its lifetime
- Unit-test structure for the splitter, settlement branch, and results-convention legs
- How inline envelope-minus-text is serialized onto `SubTaskResult` fields (chunk_hashes/result_hash usage vs payout_metadata) — follow existing conventions the validation core accepts
- Backward-compat mechanics of the schema amendments (existing manifests without `embedding_file`, existing jobs without `stop`) — both are optional adds; the researcher verifies quicktype regeneration realities

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream research (verified against `dev_elmruntime` branches)
- `.planning/workstreams/elmbridge/research/PITFALLS.md` — Pitfall 2 (validation regime — E2E must not enable redundant validation), 3 (15s lock timeout — E2E verifies the derived lock), 10 (three-clock interplay + terminal states — the overtime leg is its verification), 12 (results payload — inline vs artifact, this phase's convention), 14 (asio-thread work — verification latency), 15.1/15.2/15.3 (weak_from_this, CTest TIMEOUTs, test gating); "Looks Done But Isn't" checklist (refund path, re-grab timing, %TEMP% clean, submodule pointers); Pitfall-to-Phase mapping table (P4 verification column)
- `.planning/workstreams/elmbridge/research/ARCHITECTURE.md` — Pattern 1 (job-type sniffing at two call sites), Pattern 2 (one work item → one SubTask; subtask JSON selects the work item via ModelNode source), Pattern 4 (results ride the existing channel; requestor aggregates); Data Flow steps [1]-[9] (the exact submit→split→grab→execute→publish→payout path this phase wires); Integration Points table 1-13 (file:line anchors); Build Order steps 4-5 (this phase)
- `.planning/workstreams/elmbridge/research/FEATURES.md` — §A (job-model JSON shape), §E (result envelope table stakes), §F (funding); Anti-Features table (binding — the anti-scope audit checks against this)
- `.planning/workstreams/elmbridge/research/STACK.md` — FileManager/AsyncIOManager conventions, sgprocmanagersha

### Phase 1 design deliverables (this phase implements them)
- `.planning/workstreams/elmbridge/phases/01-elm-job-model-funding/01-DESIGN-SUBTASK-MAPPING.md` — the 1:1 mapping, notional chunk, `elm_subtask_map` placement, result keying, uniqueness inheritance — the splitter's contract
- `.planning/workstreams/elmbridge/phases/01-elm-job-model-funding/01-DESIGN-SETTLEMENT.md` — §1 measurement stamps (now on the envelope per D-04), §2 billing arithmetic, §3 BuildPayoutOutputs ELM branch (OD-3 proportional split, refund output, conservation), §4 terminal states, §5 phase boundary table (Phase 4 rows)

### Planning artifacts
- `.planning/workstreams/elmbridge/REQUIREMENTS.md` — JOB-02, JOB-04, RES-02, E2E-01..03 definitions; Out of Scope list (binding)
- `.planning/workstreams/elmbridge/ROADMAP.md` — Phase 4 success criteria (SC-1..SC-5) and note (two-repo span, validation:none, test gating)
- `.planning/workstreams/elmbridge/STATE.md` — TODOs (the two schema-amendment seams — closed by D-01..D-03 here), decisions D-001..D-004, D-P3-1/D-P3-2
- `.planning/workstreams/elmbridge/phases/01-elm-job-model-funding/01-CONTEXT.md` — Phase 1 decisions the splitter/settlement consume (D-01..D-13)
- `.planning/workstreams/elmbridge/phases/02-manifest-model-cache/02-CONTEXT.md` — cache contract (Acquire/pin/single-flight; D-01 size-first hit, D-03 cache root)
- `.planning/workstreams/elmbridge/phases/03-elm-processor/03-CONTEXT.md` — processor contract this phase routes to (StartProcessingElm seams, D-01..D-14)
- `.planning/workstreams/elmbridge/phases/03-elm-processor/03-VERIFICATION.md` — shipped state, the two escalated seams, five-level commit chain baseline
- `.planning/workstreams/elmbridge/phases/03-elm-processor/03-04-SUMMARY.md` — fixture provenance (ModelScope Qwen2.5-0.5B-Instruct-MNN, ~557MB, six files hash-recorded), `SGPROC_ELM_TEST_MODEL_DIR` convention

### Code anchors (verified in live tree, 2026-09-14)
- `SuperGenius/src/account/GeniusNode.cpp:2258-2387` — `ProcessImage` with the interim ELM rejection block this phase replaces; the non-ELM splitter loop (SC-4 byte-identical baseline); `GetElmProcessCost` (:2441)
- `SuperGenius/src/processing/processing_tasksplit.cpp:44-96` — the chunk-based splitter precedent (UUID minting, chunk id format) the ELM splitter siblings
- `SuperGenius/src/processing/processing_clocks_elm.cpp` + `processing_service.cpp:727-775` — shipped three-clock derivation and SetProcessingTimeout wiring (FUND-02, done)
- `SuperGenius/src/processing/impl/processing_core_impl.cpp:67-160` — `ProcessSubTask`: whole-job re-parse, `GetModelNodeFromJson` per-unit selection, the Process() call whose ELM routing this phase adds
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.cpp:335-460` — `FinalizeQueueProcessing`: `ElmValidationModeOk` gate, `fetchOutputData` lambda (the settlement's stamp read path), `ValidateResults` call
- `SuperGenius/src/account/TransactionManager.cpp:1104-1202` — `BuildPayoutOutputs` (even-split baseline; the ELM branch's home), `PayEscrow` (:1205), refund-output target `escrow_tx->GetSrcAddress()`
- `SuperGenius/src/account/GeniusNode.cpp:3267+` — `CreateElmRateRecordCRDTTransaction` (shipped; needs its production call site wired at ELM escrow hold)
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` — factory registration (:453-463), `ProcessInternal` (:1489; deadline timer, cancel token, manifest assembly), output-save loop (:1847-1965, the loop D-06 reuses), `GetCidForProc` (:2008; non-ELM parity gate), `GetElmMaximumProcessingHours` (:751), `CheckElmValidity` (:590-750)
- `SuperGenius/SGProcessingManager/src/processors/processing_processor_elm.cpp:100-140` — `StartProcessingElm` signature and the fail-closed base entry
- `SuperGenius/SGProcessingManager/src/elmruntime/ElmModelCache.cpp:295` — `CreateProductionElmModelCache` (zero callers today; this phase's wiring point)
- `SuperGenius/SGProcessingManager/src/elmruntime/ElmManifest.cpp:36-50` — `kRoleFilenames`/`kRequiredRoles` (the closed role set D-03 extends)
- `SuperGenius/SGProcessingManager/include/elmruntime/ElmEnvelope.hpp` — the six-key envelope D-04 extends
- `SuperGenius/SGProcessingManager/gnus-processing-schema.json:76-160` — `elms`/`Elm`/`ElmGeneration`/`ElmFunding`/`ElmModelArtifact` definitions (D-01..D-03 amendment sites)
- `SuperGenius/test/src/account/elm_cost_clocks_test.cpp` — Phase 1 test precedent (node fixture, ELM job JSON builder, submit-rejection leg that flips to acceptance)
- `SuperGenius/test/src/processing_multi/processing_multi_test.cpp` — multi-node test fixture topology (startup, config, teardown patterns)
- `SuperGenius/SGProcessingManager/test/fixtures/README.md` — fixture staging procedure + provenance table

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`ElmProcessor` + `StartProcessingElm`** (Phase 3) — the complete execution unit awaiting grid routing; parameter seams (promptText, stopStrings, cache, validator) map 1:1 onto this phase's wiring
- **`ElmModelCache::CreateProductionElmModelCache`** (Phase 2) — production cache factory (FileManager fetcher, cacheDir root, fail-closed) with zero callers — this phase provides the call site
- **`DeriveElmClocks` + `SetProcessingTimeout` wiring** (Phase 1) — shipped; the E2E verifies rather than builds
- **`ElmValidationModeOk`** (Phase 1) — shipped defensive gate at finalization
- **`CreateElmRateRecordCRDTTransaction`** (Phase 1) — shipped; needs the production call at ELM escrow hold
- **Quicktype pipeline** (`gnus-processing-schema.json` → `generated/`) — both amendments ride it; zero hand-edits
- **`SaveASync` dual-save loop** (:1847-1965) — the results path D-06 feeds rather than forks
- **`fetchOutputData` lambda** (`FinalizeQueueProcessing`) — the settlement's existing artifact-read mechanism; stamps ride the envelope so this reads them unchanged
- **Staged Qwen fixture + `SGPROC_ELM_TEST_MODEL_DIR`** — the E2E's model source with hash-recorded provenance
- **Multi-node test fixtures** — node construction/config/teardown patterns the single-node E2E adapts

### Established Patterns
- **Job-type JSON sniffing at exactly two call sites** (splitter + cost) — `ProcessImage`'s ELM branch follows it; the non-ELM path stays byte-identical (SC-4)
- **Submodule-first landing** — schema amendments + routing land in SGProcessingManager; SuperGenius consumes after pointer bump; innermost-first commits (three levels this phase: SGProcessingManager → SuperGenius → root)
- **Quicktype getters return `boost::optional<T>` by value** — materialize into named locals (the Phase 1 UB rule applies to every new read site)
- **Worker-thread discipline** — model download/hash/generation never on asio handlers; `weak_from_this` in every new timer/callback
- **Gated test targets** — `SGPROC_TEST_DISCOVERY` + CTest `TIMEOUT` (×4 margin) + wait-condition assertions

### Integration Points
- **`GeniusNode::ProcessImage` ELM branch** (:2266-2284) — replace the interim rejection with: split → `elm_subtask_map` → `GetElmProcessCost` → balance check → `HoldEscrow` + rate record → `EnqueueTask`
- **New `processing_tasksplit_elm.*`** — sibling of the chunk splitter; 1:1 mapping per the Phase 1 design
- **`ProcessingCoreImpl::ProcessSubTask` / `ProcessInternal` ELM routing** — resolve `input_uri` → promptText, construct the `sgns::Elm`, route to `StartProcessingElm` with the production cache + validator
- **Envelope + results** — stamps on the envelope; envelope-minus-text inline; full envelope as the content-addressed artifact through the existing save loop
- **`BuildPayoutOutputs` ELM branch** — proportional split from measured windows; refund output to `escrow_tx->GetSrcAddress()`; conservation preserved
- **Terminal-envelope publication** — over-time/cancelled subtasks publish success-shaped envelopes the validation core accepts (no re-grab)

</code_context>

<specifics>
## Specific Ideas

- D-04 deliberately closes the gap between `01-DESIGN-SETTLEMENT` §1 ("stamps ride the result envelope artifact") and Phase 3's shipped six-key envelope — the researcher should treat the design doc's stamp table as authoritative and the envelope extension as the carriage
- D-07 supersedes Pitfall 12's original "cap inline text at ~4KB with graceful switch" — always-artifact is simpler and the 0.5B-class fixture's envelopes make the artifact fetch cheap; the PITFALLS recovery table already assumed artifact-by-default in P4
- D-10's two-work-items-one-manifest shape is chosen so single-flight (Phase 2 SC-4) gets its first grid-level proof — two subtasks, exactly one download, both pin and load the same entry
- The E2E's refund leg (D-05) is the "Funding: Often escrows maximum but settles full amount" checkbox from PITFALLS' Looks-Done-But-Isn't list — verify refund with a short actual run, not just conservation
- The anti-scope audit (SC-5) checks against FEATURES.md's Anti-Features table: no bidding, no capability advertising, no `/v1`, no proto changes, no SuperGenius-side aggregation — grep-level plus review-level

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 4-Grid Integration & E2E Proof*
*Context gathered: 2026-09-14*
