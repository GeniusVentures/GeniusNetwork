# Architecture Research

**Domain:** ELM (Expert Language Model) job execution integrated into the existing SuperGenius processing grid + SGProcessingManager runtime
**Researched:** 2026-09-09
**Confidence:** HIGH (all integration points verified by direct source inspection of `dev_elmruntime` branches, both repos)

## Standard Architecture

### System Overview

The ELM feature is **not a new architecture** — it is a new *job shape* flowing through the existing single-node processing pipeline. Every box below already exists except the three shaded components (ELM job parsing/splitting, model cache/manifest resolver, ELM processor family).

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      REQUESTOR (GCS-style, out of scope here)            │
│   Builds job JSON: job_type="elm_processing", elms[], funding{}          │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ GeniusNode::ProcessImage(jsondata)
┌───────────────────────────────▼──────────────────────────────────────────┐
│                    SuperGenius NODE (GeniusNode.cpp)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │ ELM job      │  │ GetProcess   │  │ HoldEscrow / │  │ TaskQueue   │ │
│  │ router (NEW) │→ │ Cost (MOD)   │→ │ CRDT escrow  │→ │ EnqueueTask │ │
│  └──────┬───────┘  └──────────────┘  └──────────────┘  └──────┬──────┘ │
│         │                                                      │        │
│  ┌──────▼─────────────────┐                                    │        │
│  │ ELM task splitter      │  (replaces chunk loop for          │        │
│  │ elms[] → 1 SubTask ea. │   elm_processing jobs)  (NEW)      │        │
│  └──────┬─────────────────┘                                    │        │
│         │            Task{json_data = full job, results_channel,        │
│         │                       escrow_path}                         │        │
│  ┌──────▼───────────────────────────────────────────────────┐        │
│  │ CRDT → pubsub CID → graphsync (DAG syncer) — UNCHANGED  │        │
│  └──────┬───────────────────────────────────────────────────┘        │
└─────────┼────────────────────────────────────────────────────────────┘
          │ ProcessingSubTaskQueueChannelPubSub (queue gossip)
┌─────────▼────────────────────────────────────────────────────────────┐
│                PROCESSING NODE (processing_node.cpp)                 │
│  SubTaskQueueManager::GrabSubTask → ProcessingEngine (detached      │
│  thread) → ProcessingCoreImpl::ProcessSubTask                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ ProcessingCoreImpl::ProcessSubTask (processing_core_impl.cpp) │  │
│  │  1. task_queue_->GetTask(subTask.ipfsblock()) → Task          │  │
│  │  2. ProcessingManager::Create(task.json_data())  ← WHOLE JOB  │  │
│  │  3. GetModelNodeFromJson(subTask.json_data())    ← SUBTASK    │  │
│  │  4. manager->Process(ioc, chunk_hashes, model, out_locs)      │  │
│  └───────────────┬───────────────────────────────────────────────┘  │
│                  │ ProcessingManager::ProcessInternal               │
│  ┌───────────────▼───────────────────────────────────────────────┐  │
│  │           SGProcessingManager (submodule, dev_elmruntime)     │  │
│  │  ┌────────────┐ ┌───────────────┐ ┌────────────────────────┐ │  │
│  │  │GetCidForProc│ │ELM manifest  │ │ ELM processor family   │ │  │
│  │  │(FileManager │→│resolver+model│→│ (NEW; extends existing │ │  │
│  │  │IPFS fetch) │ │cache (NEW)   │ │ MNN_Llm precedent)     │ │  │
│  │  └────────────┘ └───────────────┘ └───────────┬────────────┘ │  │
│  │  ProcessingResult → output save (FileManager  │              │  │
│  │  SaveASync → ipfs:// + local results/ cache)  │              │  │
│  └───────────────────────────────────────────────┼──────────────┘  │
│                                                  │ SubTaskResult   │
│  SubTaskQueueAccessorImpl::CompleteSubTask ←─────┘                 │
│  → ValidateIndividualResult → Publish(RESULT_CHANNEL_ID_<task>)   │
└─────────┬────────────────────────────────────────────────────────────┘
          │ GossipPubSubTopic (results channel)
┌─────────▼────────────────────────────────────────────────────────────┐
│  OnResultChannelMessage → OnResultReceived → CompleteTask →         │
│  AsyncPayEscrow (escrow payout by result-count, unchanged)          │
│  GCS aggregates by work_item_id — NO SuperGenius-side aggregation  │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `GeniusNode::ProcessImage` | Job entry point: create `ProcessingManager`, cost, escrow, split, enqueue | `SuperGenius/src/account/GeniusNode.cpp:2257` — **modified** (job_type branch) |
| `ProcessTaskSplitter::SplitTask` | Chunk-based subtask creation (N chunks per input node) | `SuperGenius/src/processing/processing_tasksplit.cpp:44` — **precedent only**; ELM adds a sibling path, does not modify it |
| `ProcessingCoreImpl::ProcessSubTask` | Worker side: re-create manager from whole-task JSON, resolve per-subtask ModelNode, run | `SuperGenius/src/processing/impl/processing_core_impl.cpp:67` — likely **unchanged** (JSON shape does the routing) |
| `ProcessingManager::Create` / `Init` | Parse `Task.json_data` into `SgnsProcessing` schema; register processor factories; validate | `SGProcessingManager/src/processingbase/ProcessingManager.cpp:419,429` — **extended** (ELM pass/work-item schema branch) |
| `GetCidForProc` / `GetSubCidForProc` | Fetch model + input buffers via `FileManager::LoadASync` (AsyncIOManager, IPFS/file/http) | `ProcessingManager.cpp:1802,2057` — **extended** for multi-artifact model bundles |
| Model cache + manifest resolver (NEW) | Content-addressed `cache/<manifest-hash>/`, sha256 verify, pin, dedup, evict | New SGProcessingManager component (issue #17 mandate: node-side runtime owns it) |
| ELM processor family (NEW) | Tokenizer + chat template, prefill, autoregressive generation, sampling, stop conditions, detokenization, token counts, cancellation | New processor(s) following `MNN_Llm` + `RenderProcessor` precedents |
| `ProcessingEngine::ProcessSubTask` | Worker thread, sets `subtaskid`/`node_address` on result, `CompleteSubTask`, re-grab | `SuperGenius/src/processing/processing_engine.cpp:84` — **unchanged** |
| `SubTaskQueueAccessorImpl` | Results channel (`RESULT_CHANNEL_ID_<task_id>+netver`), validation, publish, re-broadcast | `processing_subtask_queue_accessor_impl.cpp:84,480` — **unchanged** |
| Escrow (`HoldEscrow`/`AsyncPayEscrow`) | Fund hold at submit; payout per accepted subtask result on completion | `GeniusNode.cpp:2320`, `TransactionManager.cpp:1073,1205` — **unchanged mechanics**, only the amount computation changes |
| `GetProcessCost` / `TokenAmount` | Byte-count → FLOP → minions cost (CoinGecko price) | `GeniusNode.cpp:2388`, `TokenAmount.cpp:65` — **branch point** for hourly ELM pricing |

## Recommended Project Structure

New code lives in **both repos**, split by the existing ownership boundary. Build order matters because SuperGenius consumes SGProcessingManager as a submodule (verified: `SuperGenius/.gitmodules` → `../SGProcessingManager.git`; `processing_service` links `ProcessingBase`, `MNN::MNN`, `AsyncIOManager` — `SuperGenius/src/processing/CMakeLists.txt:61`).

```
SGProcessingManager/                          # submodule repo — BUILD FIRST
├── generated/                                # quicktype-regenerated schema (ELM pass fields)
├── src/
│   ├── processors/
│   │   ├── processing_processor_elm.cpp/.hpp # NEW — causal-LM executor (wraps MNN::Transformer::Llm
│   │   │                                     #   or successor), generation settings, stop, counts
│   │   └── processing_processor_mnn_llm.cpp  # precedent: existing minimal LLM pass (maxNewTokens)
│   └── elmruntime/                           # NEW directory — model lifecycle
│       ├── elm_manifest.cpp/.hpp             # manifest load + hash verify + artifact list
│       ├── elm_model_cache.cpp/.hpp          # cache/<manifest-hash>/, pin, dedup, evict, verify
│       └── elm_artifact_fetcher.cpp/.hpp     # FileManager (AsyncIOManager) per-artifact fetch+sha256
└── test/
    ├── elmruntime/                           # manifest/cache unit tests (bad hash, partial, evict)
    └── processors/                           # ELM processor conformance (follows sgproc-render pattern)

SuperGenius/                                  # parent repo — CONSUMES SUBMODULE
├── src/processing/
│   ├── processing_tasksplit_elm.cpp/.hpp     # NEW — elms[] → one SubTask per work item
│   └── (existing files unchanged unless routing requires it)
├── src/account/
│   └── GeniusNode.cpp                        # MODIFIED — ProcessImage job_type branch + cost branch
└── test/
    └── processing/                           # splitter tests + single-node E2E (empty-cache proof)
```

### Structure Rationale

- **`src/elmruntime/` as its own SGProcessingManager directory:** mirrors how `capability/`, `artifacts/`, `execution/`, `datasplitter/` each own one concern; model lifecycle (manifest/cache/fetch) is orthogonal to any single processor and must be reusable if a second ELM type arrives. Issue #17's mandate — SGProcessingManager owns manifests, cache, LM execution, with AsyncIOManager `FileManager` for all artifact I/O — pins this side of the boundary.
- **`processing_tasksplit_elm.*` as a sibling, not a modification:** the existing `SplitTask` is chunk-coupled (its `numchunks` loop and `CHUNK_%d_%d` ids are meaningless for one-shot generation work items); forcing ELM through it would corrupt validation semantics (`ValidateIndividualResult` matches `chunkstoprocess` ids against `chunk_hashes`).
- **Quicktype regeneration, not hand-edits:** sgproc-render Phase 2 set the norm (SCHEMA-01..05: zero hand-edits). ELM work items become schema fields (see Data Flow), so `generated/` gets regenerated from the updated JSON schema.

## Architectural Patterns

### Pattern 1: Job-type routing via `Task.json_data`, not proto changes

**What:** The ELM job (including `elms[]`, manifest pointers, generation settings, `funding`) rides entirely inside `SGProcessing::Task.json_data` (proto `bytes json_data = 2`, `SGProcessing.proto:12`). No new protobuf messages, no new ownership protocol. The Task/SubTask/SubTaskResult wire contract is untouched.

**When to use:** always, per the corrected architecture in `ELM-bridging-gaps.md` — "No protobuf changes are required for the main ELM job definition."

**Trade-offs:** routing becomes JSON-shape sniffing (`job_type == "elm_processing"`) at exactly two points — the splitter call-site in `ProcessImage` and the cost call-site in `GetProcessCost`. Slightly implicit, but zero wire-compat risk (constraint: "Proposed proto/API changes must not break existing builds").

**Example:**
```cpp
// GeniusNode::ProcessImage — proposed branch (SuperGenius side)
json jobroot = json::parse( jsondata );
bool isElm   = jobroot.value( "job_type", "" ) == "elm_processing";
if ( isElm )
{
    processing::ProcessTaskSplitterELM elmSplitter;
    elmSplitter.SplitTask( task, subTasks, /*elms array from*/ jobroot.at( "elms" ),
                           pubsub_->GetHost()->getId().toBase58() );
    funds = GetElmProcessCost( jobroot.at( "funding" ) ); // $0.0003/h × max hours
}
else
{
    /* existing chunk-based path, byte-for-byte unchanged */
}
```

### Pattern 2: One work item → one SubTask; subtask JSON selects the work item

**What:** The existing two-JSON split already carries "whole job" and "this unit of work" separately:
- `Task.json_data` = full job (every ELM work item) — worker re-creates the whole `ProcessingManager` from it (`processing_core_impl.cpp:91`).
- `SubTask.json_data` = a `ModelNode` JSON selecting the input for this unit (`GetModelNodeFromJson`, `processing_core_impl.cpp:98` → `ProcessingManager.cpp:2120`).

The ELM splitter exploits this: subtask N's `json_data` carries the Nth work item's model-node reference (its `source` = `input:<work_item_id>`), while `subtaskid` remains the unique result key. Chunks degrade to one notional chunk per subtask (`n_subchunks=1`, single `chunkid`) so `ValidateIndividualResult` and `chunk_hashes` bookkeeping work unmodified.

**When to use:** whenever a job type has independent, non-splittable work items.

**Trade-offs:** chunk semantics are vestigial for ELM (one chunk = one result hash). Acceptable — validation only needs a deterministic 1:1 hash mapping, which a single chunk provides.

### Pattern 3: Self-fetching processor + content-addressed model cache (node side)

**What:** There is direct precedent for a processor that materializes its own model at execution time: `MNN_Llm::StartProcessing` (`processing_processor_mnn_llm.cpp:122`) receives the model bytes fetched upstream by `GetCidForProc` → `FileManager::LoadASync`, writes them to a temp dir, and creates an `MNN::Transformer::Llm` from it. The ELM processor family extends this in two ways:

1. **Multi-artifact bundles** (model + tokenizer + chat template + config), each sha256-verified — resolved by a new manifest layer (`elmruntime/`), not by the single-buffer `mainbuffers->first` path.
2. **Persistent content-addressed cache** `cache/<model-manifest-hash>/` with pin-while-processing, verify-before-reuse, dedup, eviction, partial-download recovery — the temp-dir approach (`MaterializeModelToTempDir`) is per-execution and throws the model away; the cache is the missing piece.

**When to use:** any processor whose "model" is bigger/dynamic enough that re-fetching per subtask is wasteful (a 0.5B MNN causal LM is ~300-500 MB).

**Trade-offs:** cache introduces first-node-in cost (model download is billable job work — the milestone explicitly funds it) and disk-pressure policy. All artifact I/O must go through `FileManager` (AsyncIOManager) per issue #17 — never raw sockets/curl — so fetches participate in the existing io_context drain pattern (`ioc->reset(); ioc->run();` at `ProcessingManager.cpp:1952`).

### Pattern 4: Results ride the existing channel; requestor aggregates

**What:** `ProcessingCoreImpl::ProcessSubTask` already returns a `SubTaskResult` whose `subtaskid` is set by `ProcessingEngine` (`processing_engine.cpp:127`), whose `ipfs_results_data_id` carries newline-joined output locations (`processing_core_impl.cpp:135-152`), and which is validated + published to `RESULT_CHANNEL_ID_<task_id>` by `CompleteSubTask` (`processing_subtask_queue_accessor_impl.cpp:230,256`). The work-item-tagged ELM result (JSON artifact with `work_item_id`, output text, token counts, hashes) is saved by the existing `FileManager::SaveASync` output loop (`ProcessingManager.cpp:1709`) to `ipfs://` + local `results/` dual-save, and its location returns via `ipfs_results_data_id`. GCS maps `subtaskid → work_item_id` using the mapping the splitter recorded (see Data Flow). **No SuperGenius-side aggregation** — `CompleteTask`/`TaskResult` just collects the subtask results.

**When to use:** always for v1.0 (single-node, non-streaming).

**Trade-offs:** no token streaming in v1.0 — `MNN::Transformer::Llm::response()` is a single blocking call today (`processing_processor_mnn_llm.cpp:196` documents this); the ELM-bridging doc's `ElmTokenDelta` streaming proto ideas are deferred with it.

## Data Flow

### Request Flow (ELM job, single node)

```
GCS builds job JSON ── ProcessImage(jsondata)
    ↓
[1] ProcessingManager::Create(jsondata)          # full-job parse; must ACCEPT elm job shape
    ↓                                             # (schema extension — see Key Decision D-2)
[2] job_type sniff → ELM branch
    ├─ SplitTaskELM: elms[i] → SubTask_i
    │    SubTask_i.json_data = ModelNode{source:"input:<work_item_id>"}   # per-work-item selection
    │    SubTask_i.subtaskid = uuid (existing generator, tasksplit.cpp:69)
    │    SubTask_i.chunks    = [1 notional chunk, n_subchunks=1]          # keeps validation 1:1
    │    Record work_item_id ↔ subtaskid map in task metadata (JSON)      # GCS joins on this
    └─ GetElmProcessCost: funding.maximum_processing_hours × $0.0003/h    # deterministic, no CoinGecko
    ↓
[3] HoldEscrow(funds) → CreateEscrowInfoCRDTTransaction → EnqueueTask     # unchanged
    ↓
[4] Same node (worker role): GrabSubTask → ProcessingEngine thread
    → ProcessingCoreImpl::ProcessSubTask
        task.json_data        → ProcessingManager::Create (whole job, cached pattern)
        subTask.json_data     → GetModelNodeFromJson → ModelNode(source=input:<work_item_id>)
    ↓
[5] ProcessingManager::Process → ProcessInternal
        GetCidForProc → ELM branch:
          manifest uri (input source_uri) → FileManager fetch → hash-verify
          → ElmModelCache::Acquire(manifest_hash):
              cache hit  → verify → materialize bundle path
              cache miss → fetch each artifact (FileManager) → sha256 each → store → pin
        → ELM processor StartProcessing:
              tokenizer + chat template apply → prefill → generate (KV cache)
              → sample (temperature/top_p/seed) → stop → detokenize → count tokens
              → result hash → output buffer (JSON: work_item_id, text, counts, hashes)
    ↓
[6] Output save: FileManager::SaveASync → ipfs://<output-uri> + file://cache/results dual-save
    ↓
[7] SubTaskResult{subtaskid, result_hash, chunk_hashes[1], ipfs_results_data_id,
                  token_id, developer_address, developer_cut}
    → CompleteSubTask → ValidateIndividualResult → publish RESULT_CHANNEL_ID_<task>
    ↓
[8] OnResultChannelMessage (same node, requester role) → OnResultReceived
    → CompleteTask → AsyncPayEscrow (payout per accepted result)         # unchanged
    ↓
[9] GCS: read TaskResult.subtask_results; join subtaskid→work_item_id via [2]'s map;
    fetch result artifact by ipfs_results_data_id; assemble ELM response
```

### State Management

No new long-lived SuperGenius-side state. New node-local state is confined to SGProcessingManager:

```
ElmModelCache (per processing node, disk-backed)
    ├─ cache/<manifest-hash-A>/ … pinned (refcount while subtask running)
    ├─ cache/<manifest-hash-B>/ … LRU-evictable
    └─ in-flight fetch dedup: concurrent subtasks on same manifest → one download
```

Escrow state remains exactly the CRDT/`escrow_path` flow from `ProcessImage` step [3]; payout remains `AsyncPayEscrow`'s per-result distribution (`TransactionManager.cpp:1205` splits by accepted subtask results, burn basis points, etc.).

### Key Data Flows

1. **elms[] → subtasks:** the splitter iterates `elms[]` (order preserved); work item i becomes SubTask i with a deterministic notional chunk id. The `subtaskid ↔ work_item_id` mapping is embedded in the task's JSON (e.g., each work item carries its generated `subtaskid` back-reference or the task metadata lists the pairs) so the requestor can aggregate without a new protocol field.
2. **Model bytes → cache → processor:** manifest URI is just another `input:` source in the job schema; the manifest resolver treats it as a special artifact-list input, fetches through `FileManager`, and hands the processor a materialized bundle directory (MNN LLM requires a directory with `llm_config.json` + weights — `MaterializeModelToTempDir` comment, `processing_processor_mnn_llm.cpp:23`).
3. **Funding:** deterministic at submit — `funding.maximum_processing_hours × $0.0003/hour` converted to minions at `TokenAmount::PRECISION=6` — replacing the CoinGecko-price-dependent byte/FLOP formula *for this job type only*. Model download time is inside the funded window (billable job work); the deadline mechanism (`per_pass_deadline_ms`/`ExecutionContext.deadlineMs`, `ProcessingManager.cpp:1348-1356`) already enforces wall-clock bounds and cancels via the unified cancel token.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1 node, 1 job (v1.0 target) | None — single-node E2E is the milestone's proof. In-flight fetch dedup still needed (two work items may share one model). |
| Few nodes, shared models | Cache hit-rate becomes the economic differentiator (warm nodes finish cheaper/faster); eligibility stays cache-blind per the corrected architecture. Escrow payout per result already multi-node safe (results channel + re-broadcast, `PublishExistingResults`). |
| Many nodes / many jobs | LRU eviction + disk-pressure policy in `ElmModelCache` becomes load-bearing; concurrent manifest fetches across nodes hit IPFS gateway/bitswap (bitswap already wired: `SubTaskQueueAccessorImpl::setBitswap`, mirror callback for result IPFS data). Streaming (`ElmTokenDelta`) and multi-ELM pipelines (planner→critic→verifier chaining) become relevant — both explicitly out of v1.0 scope. |

### Scaling Priorities

1. **First bottleneck: model download on cold nodes.** A 0.5B model over IPFS can exceed small `maximum_processing_hours` budgets. Mitigation: fund download time explicitly (already the milestone's stance), single-fetch dedup, and the existing deadline→cancel path failing fast.
2. **Second bottleneck: disk pressure from cached models.** Multiple distinct manifests × hundreds of MB each. Mitigation: LRU + pin-refcount + verify-before-reuse (cheap sha256 skip if pinned).

## Anti-Patterns

### Anti-Pattern 1: Advertising model/cache state into task assignment

**What people do:** add node capability/inventory messages ("I have model X warm") and bias assignment.
**Why it's wrong:** re-introduces exactly the scheduler/bidding layer the corrected architecture (ELM-bridging-gaps.md, "Exact correction to issue #369") removed; new nodes with empty caches become second-class, contradicting "cache state is not advertised and does not affect eligibility."
**Do this instead:** cache-blind assignment; warm cache is a private economic advantage only.

### Anti-Pattern 2: Hand-editing `generated/` schema classes or the proto

**What people do:** add `elms` accessors by hand to `SgnsProcessing.hpp` or new Task proto fields.
**Why it's wrong:** breaks the quicktype regeneration norm (sgproc-render SCHEMA-01..05, zero hand-edits) and the project constraint of not breaking existing builds via proto changes.
**Do this instead:** extend the JSON schema (ELM pass type / work-item inputs), regenerate, keep `Task.json_data` opaque.

### Anti-Pattern 3: SuperGenius-side aggregation of ELM results

**What people do:** add a node-side "ELM job aggregator" that merges work-item outputs.
**Why it's wrong:** adds a new protocol participant and re-derives what GCS already does; `TaskResult` is already a plain collection of `SubTaskResult`s.
**Do this instead:** requestor joins `subtaskid → work_item_id` and fetches artifacts by `ipfs_results_data_id`.

### Anti-Pattern 4: A separate download/pricing path outside escrow

**What people do:** treat model fetch as free infrastructure, or negotiate per-model prices.
**Why it's wrong:** unbillable work breaks the deterministic funding story; per-model pricing re-introduces bidding.
**Do this instead:** download time inside the funded `maximum_processing_hours` at the fixed $0.0003/h; deadline-cancel bounds the exposure.

## Integration Points

Concrete file/function anchors (verified on `dev_elmruntime`, 2026-09-09):

| # | Integration point | File : line | Change |
|---|-------------------|-------------|--------|
| 1 | Job-type branch in submit path | `SuperGenius/src/account/GeniusNode.cpp:2257` `ProcessImage` | **Modify** — sniff `job_type`; ELM branch picks splitter + cost fn; existing path untouched |
| 2 | ELM splitter | new `src/processing/processing_tasksplit_elm.*` (sibling of `processing_tasksplit.cpp:44`) | **New** — elms[] → SubTask list; notional single chunk; work_item_id↔subtaskid map into task JSON |
| 3 | Whole-job parse must accept ELM shape | `SGProcessingManager/src/processingbase/ProcessingManager.cpp:419` `Create`/`Init` (+`CheckProcessValidity:579`) | **Modify** — ELM pass/work-item validity branch (or tolerant skip of chunk-only checks for ELM inputs) |
| 4 | Worker dispatch — no change needed | `SuperGenius/src/processing/impl/processing_core_impl.cpp:67` `ProcessSubTask` | **Unchanged** — `GetModelNodeFromJson(subTask.json_data)` already does per-unit selection |
| 5 | Input/model fetch | `ProcessingManager.cpp:1802` `GetCidForProc`, `:2057` `GetSubCidForProc` (FileManager/AsyncIOManager) | **Extend** — manifest-aware branch feeding the new cache |
| 6 | Model cache + manifest verify | new `SGProcessingManager/src/elmruntime/` | **New** — `cache/<manifest-hash>/`, sha256, pin, dedup, evict (issue #17: AsyncIOManager FileManager only) |
| 7 | ELM processor registration | `ProcessingManager.cpp:429` `Init` factory table (`RegisterProcessorFactory`, `RegisterPassProcessorFactory:481`) | **Extend** — register ELM executor(s); follow `SGPROC_HAS_MNN_LLM` gating precedent (`src/processors/CMakeLists.txt:24-46`) |
| 8 | ELM processor execution | new `SGProcessingManager/src/processors/processing_processor_elm.*` (precedent: `processing_processor_mnn_llm.cpp:122`, `processing_processor_render.cpp`) | **New** — generation loop, sampling, stop, token counts, cancellation via `ExecutionContext.cancelToken`; `PushTeardown` for KV-cache/session cleanup |
| 9 | Results tagging | `processing_core_impl.cpp:135-152` output-locations → `ipfs_results_data_id`; `processing_engine.cpp:127` `set_subtaskid` | **Unchanged mechanism** — work_item_id lives in the result artifact JSON + task-embedded map |
| 10 | Results channel publish/receive | `processing_subtask_queue_accessor_impl.cpp:84` `CreateResultsChannel`, `:230` `CompleteSubTask`, `:480` `OnResultChannelMessage` | **Unchanged** |
| 11 | Escrow hold/payout | `GeniusNode.cpp:2320` `HoldEscrow`; `TransactionManager.cpp:1073/:1205`; `GeniusNode.cpp:2928` `AsyncPayEscrow` | **Unchanged mechanics** — amount now from `GetElmProcessCost` |
| 12 | Cost computation | `GeniusNode.cpp:2388` `GetProcessCost`; `TokenAmount.cpp:65` `CalculateCostMinions` | **Branch** — ELM: `maximum_processing_hours × $0.0003/h` → minions (PRECISION=6), no CoinGecko dependency |
| 13 | Build wiring | `SuperGenius/src/processing/CMakeLists.txt:61` links `ProcessingBase`/`MNN::MNN`/`AsyncIOManager`; `SGProcessingManager/src/elmruntime/CMakeLists.txt` (new) | **New/extend** — add `elmruntime` target in submodule; SuperGenius picks it up transitively |

## Build Order (two-repo constraint)

SGProcessingManager is a submodule of SuperGenius (`SuperGenius/.gitmodules`), and SuperGenius's `processing_service` links its `ProcessingBase`/`SGProcessors` targets. SuperGenius-side work cannot compile against ELM runtime APIs until the submodule ships them. Both repos are already on `dev_elmruntime` (verified). Suggested order:

1. **SGProcessingManager — schema + manifest/cache foundation.** Extend JSON schema (quicktype regen), add `src/elmruntime/` (manifest load/verify, cache, artifact fetch via FileManager) with unit tests. No SuperGenius dependency.
2. **SGProcessingManager — ELM processor family.** Register executor(s); generation loop with sampling/stop/counts/cancellation; conformance tests following the sgproc-render ctest pattern; keep `SGPROC_HAS_MNN_LLM`-style gating if the vendored MNN LLM build varies.
3. **SGProcessingManager — output path + manifest/error reporting.** Work-item-tagged result JSON artifact through the existing output-save loop; `ExecutionManifest` fields (errorMessage etc.) already cover terminal states.
4. **SuperGenius — ELM splitter + submit branch.** `ProcessImage` job_type sniff, `ProcessTaskSplitterELM`, `GetElmProcessCost` (bump submodule pointer to steps 1-3 first).
5. **SuperGenius — single-node E2E proof.** Empty-cache node downloads a small MNN causal LM (Qwen-0.5B-class) mid-job, completes all `elms[]`, results publish + escrow pays out; regression: existing chunk-based jobs byte-identical behavior.
6. **(Deferred, not v1.0)** Streaming events, multi-node distribution hardening, GCS-side OpenAI-compat API.

## Sources

- Direct source inspection (HIGH confidence): `SuperGenius/src/account/GeniusNode.cpp` (ProcessImage 2257, GetProcessCost 2388, escrow/payout 2320/2928), `src/processing/processing_tasksplit.cpp:44`, `src/processing/impl/processing_core_impl.cpp:67`, `src/processing/processing_engine.cpp:84-137`, `src/processing/processing_subtask_queue_accessor_impl.cpp:84/230/480`, `src/processing/proto/SGProcessing.proto:9-69`, `src/account/TokenAmount.cpp:65`
- Direct source inspection (HIGH confidence): `SGProcessingManager/src/processingbase/ProcessingManager.cpp` (Create 419, factory table 429-481, ProcessInternal 1289, GetCidForProc 1802, GetSubCidForProc 2057, output save 1637-1755, ParseBlockSize 1242), `src/processors/processing_processor_mnn_llm.cpp` (entire), `src/processors/CMakeLists.txt` (LLM gating 24-46), `generated/SgnsProcessing.hpp`, `generated/DataType.hpp`, `generated/PassType.hpp`
- Repo wiring: `SuperGenius/.gitmodules` (SGProcessingManager submodule), `SuperGenius/src/processing/CMakeLists.txt:61` (ProcessingBase/MNN/AsyncIOManager link), branch state `dev_elmruntime` on both repos (verified via git)
- Design intent: `SuperGenius/.planning/notes/ELM-bridging-gaps.md` (corrected architecture: GCS funds, SuperGenius schedules, node-side cache, no bidding/inventory; $0.0003/h fixed rate; cache-blind eligibility), `.planning/PROJECT.md` elmbridge workstream section (v1.0 target features, SuperGenius#369 / SGProcessingManager#17 tracking)
- Project norms applied: sgproc-render milestone history in PROJECT.md (quicktype zero-hand-edit norm, ctest conformance pattern, `SGPROC_HAS_MNN_LLM` gating, `ExecutionManifest` terminal-state/errorMessage, deadline/cancel-token mechanism)
