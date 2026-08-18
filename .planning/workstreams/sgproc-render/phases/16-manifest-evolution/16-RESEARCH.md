# Phase 16: Manifest Evolution - Research

**Researched:** 2026-08-17
**Domain:** C++ binary struct serialization / schema versioning within `SGProcessingManager` (no external libraries, no network/web domain)
**Confidence:** HIGH (this phase is entirely source-code archaeology against a single, fully-read codebase — not a framework/library research problem)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**ARTF-07 (Merkle tree over chunk hashes) — Won't implement, not applicable**
- D-01: No Merkle tree is built this phase. `Artifact::chunkHashes` (flat list, up to 1024 entries) already gives full per-chunk localization — every real consumer already has the complete list, not just a compact root.
- D-02: Task results travel over graphsync as protobuf, which already includes every subtask's chunk hashes. A verifier redoes the processing and compares hashes directly — it never holds a root without the underlying list.
- D-03: The chunk-hash-mismatch fallback path is XNODE-01c territory (cross-node consensus/redundant execution), already out of scope per REQUIREMENTS.md — not reopened here.
- D-04: Status should read "Won't implement — not applicable," not "deferred." Updating REQUIREMENTS.md's traceability table and ROADMAP.md's Phase 16 requirements/success-criteria list to reflect this is one of this phase's own plan tasks — mirrors how Phase 13 corrected its own scope wording in-plan.

**ARTF-08 (content-defined chunking) — Won't implement, not applicable**
- D-05: No content-defined chunking is built this phase. `block_len` (schema-driven, `Dimensions.hpp`) is defined by the job poster at submission time — their parameter, not SGProcessingManager's to renegotiate.
- D-06: If source data no longer fits the job's declared `block_len`, that is a bad-job condition to surface as a failure, not a gap to reconcile via smarter chunking.
- D-07: IPFS/bitswap-sourced (CID-addressed) inputs are immune to the "small edit invalidates every downstream chunk hash" problem by construction — a changed input is a different CID, i.e. a different job. `FileManager` does support non-CID sources (http/file), so the underlying problem CDC solves is reachable in principle — but per D-06, that mismatch is the job poster's responsibility.
- D-08: Same status convention as ARTF-07 — "Won't implement — not applicable," with REQUIREMENTS.md/ROADMAP.md updates handled as a Phase 16 plan task.

**ARTF-09 (human-readable error message in manifest) — Implement**
- D-09: Add a new fixed-max-size string field to `ExecutionManifest` carrying `ProcessingError::message` (currently populated at every processor error site but discarded down to the bare `TerminalState` enum at `ProcessingManager::ProcessInternal()`).
- D-10: Cap at 256 bytes, matching Phase 08's D-06 (which already anticipated this exact cap for error message strings). Overflow is truncated silently — no truncation marker — consistent with the manifest's existing fixed-max-size-with-inline-storage convention.
- D-11: Populate for all terminal states that carry a `ProcessingError` (not scoped to one particular error stage) — general-purpose diagnostic value, not tied to one specific consumer.
- D-12: No specific external consumer drove this — "any caller reading only the manifest artifact can see why it failed" is the whole goal, consumable in `outcome` form per the codebase's existing `outcome::result`/`outcome::failure` convention.

**ARTF-10 (schema evolution for binary manifest format) — Implement**
- D-13: This is the mechanism that makes ARTF-09's new field addable at all without breaking every existing manifest blob and the hardcoded-offset round-trip tests — today `SerializeManifest`/`DeserializeManifest` hard-fail on any size mismatch, and there is no version/magic field anywhere in the format.
- D-14: Must prove both compatibility directions per ROADMAP.md's Phase 16 SC4: a manifest written by the updated writer (new optional fields present) still parses successfully with an unmodified older reader (new fields ignored); a manifest written before the new fields existed still parses successfully with the updated reader (new fields default/absent).
- D-15: Exact versioning layout (magic+version header vs. trailing optional/TLV section, where the version tag lives, how the existing hardcoded-offset tests get extended without breaking) is left to planning/research — no user preference expressed beyond the two compatibility directions above.

### Claude's Discretion
- Exact binary layout for ARTF-10's versioning mechanism (magic number placement, version field size/type, whether new fields go in a trailing TLV region or a new fixed-but-versioned layout).
- Exact new field name/type for ARTF-09's error message (e.g. `char errorMessage[256]`) and its offset within `ExecutionManifest`.
- How `artifact_serializer_test.cpp`'s existing hardcoded-literal-offset assertions get extended to cover the new field(s) without breaking existing ones.
- Exact wording/table edits to REQUIREMENTS.md and ROADMAP.md documenting ARTF-07/ARTF-08 as "Won't implement — not applicable."

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. ARTF-07/ARTF-08 are not "deferred ideas" in the roadmap-backlog sense; they are this phase's own conclusion, captured above as "won't implement."
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ARTF-07 | Merkle tree over chunk hashes | **Won't implement.** No technical research needed — the decision is architectural (graphsync/protobuf already deliver full chunk-hash lists). This phase's only task against ARTF-07 is the REQUIREMENTS.md/ROADMAP.md documentation update — see "Documentation Update Task" below. |
| ARTF-08 | Content-defined chunking | **Won't implement.** No technical research needed — `block_len` is job-poster-owned per `Dimensions.hpp`/schema. This phase's only task against ARTF-08 is the same documentation update. |
| ARTF-09 | Human-readable error message in manifest | Research below covers: (a) where `ProcessingError::message` is currently discarded, (b) **the critical finding that no manifest is ever constructed on any error path today** (see "Critical Finding" section), (c) recommended field name/type/cap, (d) recommended mechanism for making the manifest retrievable on failure without breaking the existing `outcome::result<ProcessOutput>` contract. |
| ARTF-10 | Schema-evolution mechanism for the binary manifest format | Research below covers: concrete recommended trailer/version layout preserving all existing fixed offsets, the `!=`-to-`>=` size-check relaxation required in `DeserializeManifest`, and a concrete test strategy for both SC4 compatibility directions given that no manifest has ever actually been persisted outside a single `Process()` call in this codebase (there is no real "old" binary to test against). |
</phase_requirements>

## Summary

This phase is pure C++ source-code archaeology, not a "pick a library" research problem — there are no candidate libraries to evaluate (the codebase is deliberately protobuf/MessagePack/CBOR-free per Phase 08 D-04, and ARTF-07/ARTF-08 are both closed as "won't implement" so no Merkle/CDC research was performed at all, per this phase's explicit scope narrowing). Everything needed to plan ARTF-09/ARTF-10 is already visible in the five source files CONTEXT.md's canonical_refs names, plus one file it doesn't name that turned out to be load-bearing: `SuperGenius/src/processing/impl/processing_core_impl.cpp` (the real, only production caller of `ProcessingManager::Process()`).

**The single most important finding, not previously surfaced in CONTEXT.md:** today, `ProcessingManager::ProcessInternal()` **never constructs or returns an `ExecutionManifest` on any error path.** Every branch that would set `TerminalState` to `Cancelled`/`Timeout`/`BudgetExceeded`/`Error` returns `outcome::failure(Error::PROCESSING_FAILED)` immediately (`ProcessingManager.cpp:1332-1358`), before the manifest-assembly block (`1442+`) ever executes. That assembly block only runs inside the success path's `if (processResult.output_buffers && !outputs.empty())` guard. This means the `terminalState` local variable computed at lines 1319-1329 is dead with respect to any real caller — it is never written into a manifest that reaches anyone. **ARTF-09 cannot be satisfied by adding a struct field alone; the phase must also restructure the error paths so a manifest (with the new error-message field) is actually built and made retrievable when processing fails.** See "Critical Finding" below for the recommended minimal-diff fix.

**Primary recommendation:** (1) Add `char errorMessage[MAX_IDENTIFIER]` (256 bytes, matching the existing 256-byte string-field convention) to `ExecutionManifest`. (2) Build the manifest on every terminal path — not just success — storing it in a new `ProcessingManager::m_lastManifest` member with a `GetLastManifest()` accessor (mirrors the existing `GetProgress()` precedent), so a caller that received `outcome::failure` from `Process()` can still retrieve the manifest and its error message without touching the existing `outcome::result<ProcessOutput>` contract or its one real caller (`processing_core_impl.cpp`). (3) For ARTF-10, append (not prepend) a small version+field trailer immediately after today's fixed `MANIFEST_SERIALIZED_SIZE` (5649) region, relax `DeserializeManifest`'s `bytes.size() != MANIFEST_SERIALIZED_SIZE` hard-fail to `bytes.size() < MANIFEST_SERIALIZED_SIZE`, and extend (never renumber) the existing hardcoded-offset tests. (4) Update REQUIREMENTS.md's traceability table and ROADMAP.md's Phase 16 section to mark ARTF-07/ARTF-08 "Won't implement — not applicable" with the D-01..D-08 rationale, as its own plan task.

## Architectural Responsibility Map

This is a single-process, embedded C++ backend engine (`SGProcessingManager`) — there is no browser/SSR/CDN tier in play. The relevant internal tiers are the processor layer, the orchestration layer, and the serialization layer.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Capturing `ProcessingError.message` at the failure site | Processor layer (`processing_processor.hpp` / `processing_processor_mnn_*.cpp`) | — | Already implemented; every processor error site already populates a real string. No change needed here. |
| Threading the message into the manifest + making it retrievable on failure | Orchestration layer (`ProcessingManager::ProcessInternal()`, `ProcessingManager.hpp` new member/accessor) | — | This is where the message is currently discarded (`ProcessingManager.cpp:1353-1356` only logs it) and where the manifest-on-failure gap lives. |
| Binary layout / version trailer / bounds-checked parsing | Serialization layer (`artifact_serializer.hpp/.cpp`) | — | Owns `SerializeManifest`/`DeserializeManifest`; the only place fixed-offset layout and size checks live. |
| REQUIREMENTS.md/ROADMAP.md wording update for ARTF-07/08 | Project docs (non-runtime) | — | Not a code tier; a plan task that edits planning artifacts, mirroring Phase 13's in-plan scope correction precedent. |

## Package Legitimacy Audit

Not applicable — this phase adds no external packages, libraries, or dependencies of any kind (npm/pip/cargo/vcpkg/conan). It is pure modification of existing, already-vendored C++ code (`SGProcessingManager`'s own `artifacts/` module) plus test-file and Markdown edits. No `package-legitimacy check` was run because there is nothing to check.

## Critical Finding: No Manifest Is Ever Built On An Error Path Today

Read directly from `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp`:

```cpp
// Lines 1319-1329: terminalState IS computed from the error stage...
TerminalState terminalState = TerminalState::Success;
if ( processResult.error )
{
    switch ( processResult.error->stage )
    {
        case ProcessingErrorStage::CANCELLED:       terminalState = TerminalState::Cancelled;      break;
        case ProcessingErrorStage::TIMED_OUT:       terminalState = TerminalState::Timeout;        break;
        case ProcessingErrorStage::BUDGET_EXCEEDED: terminalState = TerminalState::BudgetExceeded; break;
        default:                                    terminalState = TerminalState::Error;          break;
    }
}

// Lines 1331-1349: ...but CANCELLED/TIMED_OUT/BUDGET_EXCEEDED return immediately,
// with NO ExecutionManifest ever constructed:
if ( processResult.error )
{
    if ( processResult.error->stage == ProcessingErrorStage::CANCELLED )
    {
        m_logger->error( "Processing cancelled" );
        return outcome::failure( Error::PROCESSING_FAILED );   // <-- no manifest built
    }
    // ...same pattern for TIMED_OUT, BUDGET_EXCEEDED
}

// Lines 1351-1358: ...and every OTHER error (the generic/default -> TerminalState::Error case)
// ALSO returns immediately here, again with no manifest:
if ( processResult.error || processResult.hash.empty() )
{
    m_logger->error( "Processing failed: {}",
                     processResult.error ? processResult.error->message : "..." );  // logged, then discarded
    return outcome::failure( Error::PROCESSING_FAILED );   // <-- no manifest built
}

// Line 1360+: manifest assembly (ExecutionManifest &manifest = output.manifest; ...) only
// happens AFTER this point, gated by `if (processResult.output_buffers && !outputs.empty())`
// -- i.e. only reachable on the success path.
```

`[VERIFIED: SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp:1319-1511]` — read directly, not inferred.

`ProcessInternal()`'s signature is `outcome::result<ProcessOutput> ProcessInternal(...)` (`ProcessingManager.cpp:1191`; declared `ProcessingManager.hpp:198`). The **only real production caller** is `SuperGenius/src/processing/impl/processing_core_impl.cpp:102-109`:

```cpp
auto result_retval = processing_manager_->Process( ioc, chunk_hashes, model_retval.value(), output_locations );
DecProcessingSubTaskCount();
if ( !result_retval.has_value() )
{
    return result_retval.error();   // <-- discards everything; no manifest access attempted today
}
```
`[VERIFIED: SuperGenius/src/processing/impl/processing_core_impl.cpp:100-109]`. Even on the **success** path, this caller never reads `result_retval.value().manifest` — it only reads the backward-compat `combinedHash` accessor (`result_retval.value().begin()/.end()`) to populate `SGProcessing::SubTaskResult`. So today, **nobody in production reads `ProcessOutput.manifest` at all** — it is a data contract for future consumers (per Phase 08's stated intent), currently exercised only by `artifact_serializer_test.cpp`.

**Why this matters for planning:** D-11 ("Populate for all terminal states that carry a `ProcessingError`") and ROADMAP SC3 ("retrievable from the manifest artifact by a caller that only has the manifest, not the original error site") are **currently unsatisfiable** without a structural change to `ProcessInternal()`'s error paths — not just a struct field addition. The plan must include a task that makes the manifest reachable on failure. See "Recommended ARTF-09 Design" below for the lowest-risk way to do this.

## Recommended ARTF-09 Design

**New field:** `char errorMessage[MAX_IDENTIFIER]` (256 bytes — reuse the existing `MAX_IDENTIFIER` constant from `execution_manifest.hpp` rather than inventing a new size constant; Phase 08 D-06 already anticipated "256 bytes for error messages" verbatim). Populate from `ProcessingError::message` (`processing_processor.hpp:49`, `std::string`) via the same `strncpy`-and-truncate pattern the codebase already uses for every other string field (D-10: silent truncation, no marker). Default/empty when `terminalState == Success`.

**Making it reachable on failure — three options considered:**

1. **(Rejected — too large a blast radius) Change `ProcessInternal()` to return `outcome::success(output)` even on processing failure**, with the manifest's `terminalState` carrying the failure information (i.e. "the call succeeded in producing a manifest describing a failure"). This would let a caller read `.manifest.errorMessage` uniformly, but it silently changes what `result_retval.has_value()` means for the **only real caller** (`processing_core_impl.cpp:106`) — that caller's `if (!result_retval.has_value())` branch would stop firing for processing errors entirely, and it would fall through to building a `SubTaskResult` as if processing succeeded, unless that file is *also* rewritten in the same phase to check `manifest.terminalState` explicitly. That is a materially larger, riskier change than this "deferred gap closure" phase's framing supports, and it isn't required by any of D-09 through D-15.

2. **(Rejected — needs a new custom outcome error type) Attach the manifest to the `Error` payload itself** via `OUTCOME_HPP_DECLARE_ERROR_2`. This macro (`ProcessingManager.hpp:238`) wraps a plain enum into `std::error_code`-compatible machinery; extending it to carry a full `ExecutionManifest` payload would require restructuring the error-code framework used elsewhere in this class (`MISSING_INPUT`, `NO_PROCESSOR`, etc.) — larger surface area than the field this phase is adding.

3. **(Recommended) Keep `outcome::failure(Error::PROCESSING_FAILED)` exactly as-is (zero change to the existing contract or to `processing_core_impl.cpp`), and additionally store the just-assembled manifest into a new private member (e.g. `ExecutionManifest m_lastManifest{};`) right before every terminal `return` (success or failure) in `ProcessInternal()`, exposed via a new public accessor** — e.g. `const ExecutionManifest &GetLastManifest() const { return m_lastManifest; }`. This mirrors the existing `GetProgress()` accessor precedent (`ProcessingManager.hpp:155-160`, delegates to an internal member) and the established pattern of adding purely-additive, backward-compatible surface area (Phase 09 P12's 5-arg `Process()` overload, cited in STATE.md, did exactly this for a different problem). A caller that gets `outcome::failure` back from `Process()` can call `processingManager->GetLastManifest().errorMessage` immediately afterward — satisfying "retrievable from the manifest artifact by a caller that only has the manifest, not the original error site" (SC3) literally, with no change to any existing caller's control flow.

Building `m_lastManifest` requires moving a *minimal* manifest assembly (executionId/passId/timing/terminalState/errorMessage — not the full artifact-hash-dependent assembly at lines 1442+, since output artifacts don't exist on a failure path) into (or ahead of) each of the three early-return sites (lines ~1334-1348 for CANCELLED/TIMED_OUT/BUDGET_EXCEEDED, and line ~1353 for the generic error/default case). This is a small, mechanical addition, not a redesign.

**Populate for every stage that maps to a non-Success `TerminalState`,** per D-11 — not just the generic `Error` case. `Cancelled`/`Timeout`/`BudgetExceeded` all currently have a `ProcessingError` available (`processResult.error->message`) at their respective early-return sites; thread the same field through all four.

## Recommended ARTF-10 Design

### The core constraint

Today's `SerializeManifest`/`DeserializeManifest` (`artifact_serializer.cpp:144`, `:233`) use a completely fixed, offset-hardcoded layout with **no version or magic field anywhere**, and `DeserializeManifest` hard-fails via `if (bytes.size() != MANIFEST_SERIALIZED_SIZE) return false;` (`:235-238`) `[VERIFIED: artifact_serializer.cpp:235-238]`. Any new field necessarily changes the serialized size, so this exact-equality check is the literal thing that must change for schema evolution to be possible at all — this **is** the versioning mechanism ARTF-10 introduces, not a side effect of it.

### Where to put the version tag: append, don't prepend

Canonical binary-format advice (magic number + version at file offset 0) `[CITED: web search — file-format design conventions, e.g. fadden.com/tech/file-formats.html, IETF magic-number draft]` would normally place a magic+version header at the very start of the blob. **This phase should not follow that convention literally**, because `execution_manifest.hpp`'s fields all sit at fixed offsets starting at 0 (`OFF_executionId = 0`), and `artifact_serializer_test.cpp` asserts against those exact literal offsets directly (e.g. `ManifestZeroIdentityHashes` checks `bytes[1344]` for `tokenizerIdentity`, `bytes[1376]` for `adapterIdentity`). Prepending a header would shift every existing offset by the header's width, silently invalidating every hardcoded-literal assertion in the test file — exactly what CONTEXT.md's canonical_refs warns must not happen ("any field additions must extend these without breaking them").

**Recommendation: append a small trailer immediately after today's fixed region (offset `MANIFEST_SERIALIZED_SIZE` = 5649), leaving every existing offset (0 through 5648) byte-for-byte unchanged.**

```
[ existing 5649-byte fixed layout — UNCHANGED, same offsets as today ]
[ offset 5649: uint32_t schemaVersion  (4 bytes) ]
[ offset 5653: char errorMessage[256]             ]
--> new total: MANIFEST_V2_SERIALIZED_SIZE = 5649 + 4 + 256 = 5909 bytes
```

A leading magic number is arguably unnecessary here regardless of placement: `ExecutionManifest` blobs are never persisted as standalone files of ambiguous type (confirmed below — nothing writes them to disk at all today); they only ever move between `SerializeManifest`/`DeserializeManifest` within this same codebase, where "this is a manifest, not some other file" is never in question. A bare version field is sufficient; a magic number adds no real protection here and would cost 4 more bytes for no benefit. (If the planner prefers the extra safety margin, a 4-byte magic ahead of `schemaVersion` in the trailer is a one-line addition — flagging as a cheap optional extra, not a requirement.)

### Required relaxation in `DeserializeManifest`

Change:
```cpp
if ( bytes.size() != MANIFEST_SERIALIZED_SIZE ) { return false; }
```
to:
```cpp
if ( bytes.size() < MANIFEST_SERIALIZED_SIZE ) { return false; }   // still reject too-short/corrupt blobs
```
then, after parsing the unchanged base fields exactly as today, conditionally read the trailer:
```cpp
out.errorMessage[0] = '\0';  // default: absent
if ( bytes.size() >= MANIFEST_SERIALIZED_SIZE + sizeof(uint32_t) )
{
    uint32_t schemaVersion = 0;
    std::memcpy( &schemaVersion, bytes.data() + MANIFEST_SERIALIZED_SIZE, sizeof(uint32_t) );
    if ( schemaVersion >= 2 &&
         bytes.size() >= MANIFEST_SERIALIZED_SIZE + sizeof(uint32_t) + MAX_IDENTIFIER )
    {
        std::memcpy( out.errorMessage, bytes.data() + MANIFEST_SERIALIZED_SIZE + sizeof(uint32_t), MAX_IDENTIFIER );
        out.errorMessage[MAX_IDENTIFIER - 1] = '\0';
    }
}
```
Every trailer read is gated by an explicit `bytes.size() >= ...` check before the corresponding `memcpy` — this is a genuine security-relevant detail (see Security Domain below), not just a style preference: without it, a truncated/corrupted blob whose size lands between `MANIFEST_SERIALIZED_SIZE` and `MANIFEST_SERIALIZED_SIZE + 4` would cause an out-of-bounds read on the `schemaVersion` `memcpy`.

`SerializeManifest` should always emit the full v2-sized trailer (`schemaVersion = 2`, `errorMessage` populated or empty) going forward — there is no reason to conditionally emit a shorter v1-only blob from the updated writer.

### Why the SC4 "both directions" proof needs an honest reframing

ROADMAP SC4 asks for proof that (a) a new-writer manifest still parses with an "unmodified older reader" and (b) an old-writer manifest still parses with the updated reader. **There is no actual pre-Phase-16 binary or persisted manifest anywhere in this repository to test against** — confirmed by grepping the entire `SGProcessingManager` source tree: `SerializeManifest`/`DeserializeManifest` are called only from `artifact_serializer.hpp`'s inline `ComputeManifestHash()` helper and from `artifact_serializer_test.cpp`; nothing in `ProcessingManager.cpp` or anywhere else writes a manifest blob to a file or persists it across process runs. `[VERIFIED: grep across SuperGenius/SGProcessingManager and SuperGenius/src for SerializeManifest/manifest-to-disk call sites]` So "old reader" cannot mean "a literally frozen historical binary" — it must mean "the base-layout-only parsing logic this phase's mechanism defines," proven via two test-side constructs that are both faithful and honest about that limitation:

1. **Direction 2 (old-writer bytes / new reader) — straightforward:** In `artifact_serializer_test.cpp`, hand-construct (or truncate a real `SerializeManifest` output down to) exactly `MANIFEST_SERIALIZED_SIZE` (5649) bytes with no trailer. Feed it to the **updated** `DeserializeManifest`. Assert success, all base fields match, and `errorMessage` defaults to empty. This directly exercises the `bytes.size() < MANIFEST_SERIALIZED_SIZE` relaxation.

2. **Direction 1 (new-writer bytes / old reader) — needs a test-local proxy for "old reader":** Add a small, explicitly-commented test-local helper function (e.g. `DeserializeManifestBaseFieldsOnly`) that parses *only* the unchanged base-region fields using the exact same offsets as today, and — critically — uses the **relaxed** `bytes.size() >= MANIFEST_SERIALIZED_SIZE` check rather than today's literal `!=` (because, as established above, an exact-equality check can never tolerate a longer blob no matter how the extra bytes are laid out — that check itself is what's being replaced by this phase's mechanism). Feed it a manifest produced by the **new** `SerializeManifest` (with `errorMessage` populated, i.e. genuinely longer than 5649 bytes). Assert it returns true and every base field it knows about matches, without the helper ever touching the trailer bytes. Document in the test's comment exactly what this proves and what it cannot prove: it demonstrates the *mechanism* (relaxed size check + never reading past what you understand) is sufficient for forward-tolerance; it does not — and cannot — demonstrate that a binary compiled before this phase existed would happen to already contain that relaxation, because no such binary or persisted artifact exists in this system today. This honest framing should be stated directly in the plan/PLAN.md and the eventual verification notes, not glossed over.

### Extending the existing hardcoded-offset tests

`artifact_serializer_test.cpp`'s manifest tests currently assert `bytes.size() == MANIFEST_SERIALIZED_SIZE` in three places (`ManifestSerializeRoundTrip.AllFieldsMatch:221`, implicitly via `bytes1.size()==bytes2.size()` in `ManifestDeterminism:255`, and `ManifestZeroIdentityHashes.SentinelZerosForInapplicable:265`). Once `SerializeManifest` always emits the new trailer, these `ASSERT_EQ(bytes.size(), MANIFEST_SERIALIZED_SIZE)` assertions must be updated to assert against a new `MANIFEST_V2_SERIALIZED_SIZE` (or equivalent) constant — this is an **extension** (the base-region literal offsets like `bytes[1344]`/`bytes[1376]`/`bytes[1440]` stay exactly as they are; only the total-size assertions and any new trailer-region assertions change). Note the offset-1112 literal CONTEXT.md's canonical_refs cites belongs to `ArtifactZeroChunkCount` (the `Artifact` struct's `chunkHashes` region), not `ExecutionManifest` — `Artifact` is untouched by ARTF-10, so that specific test needs no change; only the *manifest* tests (`bytes[1344]`, `bytes[1376]`, `bytes[1440]`, and the three size assertions) are in scope.

## Documentation Update Task (ARTF-07 / ARTF-08 "Won't implement")

This phase's plan must include a task, not just code changes, to correct:
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — traceability table rows for `ARTF-07`/`ARTF-08` currently read `Phase 16 | Pending`; change to `Phase 16 | Won't implement — not applicable` (or equivalent wording), with a one-line rationale citing D-01/D-02 (Merkle) and D-05/D-06 (CDC).
- `.planning/workstreams/sgproc-render/ROADMAP.md` Phase 16 section — the Goal line and Success Criteria #1/#2 (SC1 Merkle, SC2 CDC) are stale (written before this phase's discuss-phase narrowed scope); these need updating so a future reader of ROADMAP.md doesn't chase a goal that's already been closed as "won't implement." Precedent: Phase 13 corrected its own ROADMAP.md wording in-plan (STATE.md: "REQUIREMENTS.md VALD-01 / ROADMAP.md Phase 13 SC1 wording corrected... via scoped Edit calls").

This is documentation-only — no source code, no tests — but it's an explicit CONTEXT.md D-04/D-08 requirement and should be its own small, clearly-scoped plan task (likely Wave 0 or a standalone task, done first so the rest of the plan's Success Criteria section isn't itself describing stale/moot goals).

## Standard Stack

Not applicable in the conventional sense (no new library/framework selection). The "stack" for this phase is entirely the existing, already-adopted in-house pattern:

| Component | Version/Location | Purpose | Why Standard (for this codebase) |
|-----------|-------------------|---------|-----------------------------------|
| Custom fixed-offset binary serialization | `artifact_serializer.hpp/.cpp` (this repo) | Deterministic manifest/artifact byte layout | Established Phase 08 D-04/D-05 — no protobuf/MessagePack/CBOR anywhere in `SGProcessingManager` by deliberate project convention |
| `sgns::sgprocmanagersha::sha256` | `util/sha256.hpp/.cpp` (this repo) | Manifest self-hash (unchanged this phase) | Existing, already-used hashing utility; ARTF-10 doesn't touch hashing logic |
| `outcome::result<T>` (Boost.Outcome-style) | `ProcessingManager.hpp` (existing usage) | Return-value error handling for `Process()` | Established codebase-wide convention; D-12 explicitly asks ARTF-09 to be "consumable... per the codebase's existing `outcome::result`/`outcome::failure` convention" |
| GoogleTest | `test/artifacts/artifact_serializer_test.cpp` (existing) | Round-trip / compat tests | Already the test framework for this exact file; no change needed |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled fixed-offset + trailer | FlatBuffers / Cap'n Proto (zero-copy, versioned by design) | Both are exactly the "avoid hand-rolling schema evolution" instinct — but Phase 08 D-04 already deliberately rejected any serialization library ("no protobuf... C++ structs only"), and introducing one now for a single 256-byte field would be a much larger, out-of-scope architectural reversal. Not recommended. |
| Trailing version+field trailer (recommended) | Prepended magic+version header at offset 0 (textbook convention) | Textbook-correct but breaks every existing hardcoded-offset test literal in this specific codebase; rejected for this integration only, not as a general critique of the convention. |

**Installation:** None — no packages to install.

## Architecture Patterns

### System Architecture Diagram

```
ProcessingCoreImpl::ProcessSubTask()          (SuperGenius/src/processing/impl/processing_core_impl.cpp)
        │
        │  calls
        ▼
ProcessingManager::Process()  ──delegates──▶  ProcessInternal()   (SGProcessingManager)
        │                                            │
        │                                            ├─▶ m_processor->StartProcessing()  (ProcessingProcessor subclass)
        │                                            │        └─▶ on failure: fills ProcessingError{ stage, message }
        │                                            │
        │                                            ├─▶ [TODAY] error branches (CANCELLED/TIMED_OUT/BUDGET_EXCEEDED/generic)
        │                                            │        return outcome::failure(...) immediately — NO manifest built
        │                                            │
        │                                            ├─▶ [ARTF-09 FIX] build minimal ExecutionManifest on EVERY terminal
        │                                            │        path (success or failure), store into m_lastManifest
        │                                            │
        │                                            └─▶ [success path only, existing] build Artifact records +
        │                                                     full ExecutionManifest → output.manifest
        │
        ├── outcome::failure(Error::PROCESSING_FAILED)  ──▶  caller checks !has_value(), can now ALSO call
        │                                                      processingManager->GetLastManifest().errorMessage
        │
        └── outcome::success(ProcessOutput{ artifacts, manifest, combinedHash })
                     │
                     ▼
        ExecutionManifest ──▶ SerializeManifest() ──▶ [fixed base bytes 0..5648][schemaVersion:4][errorMessage:256]
                     ▲                                          (ARTF-10 trailer, appended not prepended)
                     │
        DeserializeManifest() ◀── accepts bytes.size() >= 5649 (relaxed from == 5649), reads trailer if present
```

### Recommended Project Structure
No new files/folders — all changes land in the existing `artifacts/` module and `processingbase/`:
```
SGProcessingManager/
├── include/artifacts/
│   ├── execution_manifest.hpp     # + errorMessage[MAX_IDENTIFIER] field
│   └── artifact_serializer.hpp    # + MANIFEST_V2_SERIALIZED_SIZE constant
├── src/artifacts/
│   └── artifact_serializer.cpp    # SerializeManifest/DeserializeManifest trailer logic
├── include/processingbase/
│   └── ProcessingManager.hpp      # + m_lastManifest member, + GetLastManifest() accessor
├── src/processingbase/
│   └── ProcessingManager.cpp      # ProcessInternal(): build manifest on every terminal path
└── test/artifacts/
    └── artifact_serializer_test.cpp   # extend size assertions; add ARTF-09/ARTF-10 test cases
```

### Pattern 1: Additive, backward-compatible accessor instead of contract change
**What:** When new information (the manifest on a failure path) needs to reach a caller without disturbing an existing, real, production call site's control flow, add a new accessor method rather than changing an existing return type's meaning.
**When to use:** Exactly this situation — `outcome::result<ProcessOutput>` is a real, load-bearing contract with exactly one production caller whose `if (!result.has_value())` branch must keep working unchanged.
**Example (this codebase's own precedent):**
```cpp
// Existing precedent, ProcessingManager.hpp:155-160
float GetProgress() const
{
    if ( m_processor ) { return m_processor->GetProgress(); }
    return 0.0f;
}
// Recommended, same shape, for ARTF-09:
const ExecutionManifest &GetLastManifest() const { return m_lastManifest; }
```

### Pattern 2: Append-only trailer preserves existing fixed-offset literals
**What:** New optional fields go in a region appended after the existing fixed layout's last byte, never inserted before or within it.
**When to use:** Any codebase (like this one) whose tests assert against literal hardcoded byte offsets for the existing layout.
**Example:**
```cpp
// Source: this repo, artifact_serializer.cpp — existing convention, extended
static constexpr size_t OFF_manifestHash   = 5617;  // existing, UNCHANGED
static constexpr size_t OFF_schemaVersion  = MANIFEST_SERIALIZED_SIZE;       // 5649 — NEW, appended
static constexpr size_t OFF_errorMessage   = MANIFEST_SERIALIZED_SIZE + 4;   // 5653 — NEW, appended
```

### Anti-Patterns to Avoid
- **Prepending a magic/version header at offset 0:** Textbook-correct in general, wrong for this specific codebase — shifts every existing offset and breaks every hardcoded-literal test assertion for no compatibility benefit this codebase actually needs (see Recommended ARTF-10 Design above).
- **Trusting an embedded length/version field before bounds-checking against `bytes.size()`:** Reading `schemaVersion` or `errorMessage` from the trailer without first confirming `bytes.size()` is long enough is an out-of-bounds read on any truncated/corrupted input (see Security Domain).
- **Assuming SC4's "unmodified older reader" means a literally frozen historical binary:** No such binary or persisted manifest exists in this repository (see "Why the SC4 proof needs honest reframing" above) — treating the test as if one does will produce a test that either can't be written or silently tests the wrong thing.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Detecting whether a byte blob is long enough before reading a given trailer field | Ad hoc, one-off `if` checks scattered per field with slightly different arithmetic each time | A single small bounds-check helper (e.g. `bool HasTrailingBytes(size_t blobSize, size_t offset, size_t fieldSize)`) reused for every trailer field this phase and any future one adds | Keeps every future field addition (v3, v4...) using the exact same proven-safe bounds-check idiom instead of re-deriving arithmetic each time — reduces the exact class of off-by-one/overflow bug this trailer design is otherwise exposed to |
| A one-off versioning scheme solving only ARTF-09's single field | A bespoke `if (bytes.size() == 5909) { read errorMessage }` special case with no `schemaVersion` field at all | The `schemaVersion`-gated trailer described above | A size-only check (no explicit version) works for exactly one field addition; the next field addition (v3) would need its own new size-based special case layered on top, compounding complexity. A version field pays for itself the second time a field is added — and Phase 08's own history (four deferred gaps opened in one phase, closed incrementally) suggests more additions are likely. |

**Key insight:** This phase's entire challenge is disciplined, minimal-diff extension of an existing, deliberately hand-rolled format — not avoiding hand-rolling (that ship sailed at Phase 08 D-04) but avoiding hand-rolling the *versioning bookkeeping* differently every time a field is added.

## Common Pitfalls

### Pitfall 1: Adding the `errorMessage` field without fixing the "no manifest on error" gap
**What goes wrong:** The field gets added to `ExecutionManifest`, `SerializeManifest`/`DeserializeManifest` round-trip it correctly in tests — but in production, `ProcessInternal()`'s early-return error branches still never construct a manifest at all, so `errorMessage` is never actually populated or reachable by any real caller. SC3 ("retrievable from the manifest artifact by a caller that only has the manifest") silently fails to hold in the real system despite all unit tests passing.
**Why it happens:** The struct-field change and the control-flow change are easy to treat as separable, and the struct-field change is the one visible in `execution_manifest.hpp`'s diff; the control-flow gap is buried inside `ProcessInternal()`'s early returns and easy to miss without reading the full function (see "Critical Finding" above).
**How to avoid:** Treat the `m_lastManifest`/`GetLastManifest()` restructuring (or an equivalent mechanism) as a first-class, required task in this phase's plan — not an optional nice-to-have.
**Warning signs:** A plan whose tasks only touch `execution_manifest.hpp` and `artifact_serializer.*` (not `ProcessingManager.cpp`/`.hpp`) for ARTF-09 has not addressed this gap.

### Pitfall 2: Trailer field reads without incremental bounds checks (security-relevant)
**What goes wrong:** `DeserializeManifest` reads `schemaVersion` or `errorMessage` from the trailer based on the presence of a version tag without first confirming `bytes.size()` is actually long enough for that specific read — an out-of-bounds read on truncated/corrupted/adversarial input.
**Why it happens:** Once the exact-size check is relaxed to `>=`, it's tempting to assume "the rest is just optional, read what's there" without re-deriving the bounds check for each conditionally-read field.
**How to avoid:** Gate every trailer-region `memcpy` behind its own explicit `bytes.size() >= offset + fieldSize` check (see the code sketch in "Required relaxation in DeserializeManifest" above), defaulting the field instead of reading when the check fails.
**Warning signs:** Any `memcpy(..., bytes.data() + OFF_something, N)` in the trailer-parsing region that isn't immediately preceded by a size check for that exact offset+N.

### Pitfall 3: Updating the manifest size assertions without checking whether it silently regresses the ARTF-05 determinism guarantee
**What goes wrong:** `SerializeManifest`'s determinism tests (`ManifestDeterminism.ByteIdenticalAcrossTwoRuns`) already pass because both calls use the exact same input — this is unaffected by the trailer addition as long as `errorMessage`'s truncation/padding is itself deterministic (e.g. always zero-pad the unused tail of the 256-byte field, matching the existing `copyStr` lambda's convention). If a new ad hoc truncation routine is written instead of reusing the existing `copyStr` pattern, it's easy to introduce non-deterministic padding (e.g. leaving stale/uninitialized bytes past the string's null terminator).
**Why it happens:** `errorMessage` looks like "just another string field" but sits in a newly-appended region that isn't part of the original `std::vector<uint8_t> out(MANIFEST_SERIALIZED_SIZE, 0)` zero-fill allocation unless the vector is resized/reallocated to the new total size before writing.
**How to avoid:** Reuse the exact same `copyStr` lambda pattern already used for every other string field (`artifact_serializer.cpp:180-184`), and ensure the output vector is allocated at the *new* total size (`MANIFEST_V2_SERIALIZED_SIZE`) from the start so the zero-fill covers the trailer region too.
**Warning signs:** A new, separate helper function for writing `errorMessage` instead of reusing `copyStr`; an output vector still allocated at the old `MANIFEST_SERIALIZED_SIZE`.

### Pitfall 4: Diagnostic error messages leaking sensitive detail (information-disclosure adjacent)
**What goes wrong:** `ProcessingError::message` strings are currently written for internal logging only (`m_logger->error(...)`) and may include raw `VkResult` codes, internal file paths, or other implementation detail (`ProcessingErrorStage` comments mention "carries the failing VkResult/context as a plain message string"). Once threaded into a manifest that's part of a "data contract" future consumers may read, this detail becomes externally visible in a way it wasn't before.
**Why it happens:** D-12 explicitly says no specific external consumer drove ARTF-09 and the goal is general-purpose diagnostic value — it's easy to thread the string through verbatim without considering who might eventually read a manifest.
**How to avoid:** Not a blocker for this phase (D-11/D-12 explicitly ask for the raw message, unfiltered, and there is no current external/network consumer of manifests) — but flag this in the plan's verification notes as a known, accepted tradeoff rather than an oversight, so a future phase adding an external manifest consumer/export path revisits it deliberately.

## Code Examples

### Existing string-field truncation pattern to reuse for `errorMessage`
```cpp
// Source: SuperGenius/SGProcessingManager/src/artifacts/artifact_serializer.cpp:180-184 (existing, unmodified)
auto copyStr = [&]( size_t offset, const char *src, size_t maxLen )
{
    size_t len = std::min( std::strlen( src ), maxLen - 1 );
    std::memcpy( out.data() + offset, src, len );
    // Rest is already zero from pre-allocation
};
// Reuse directly for the new field:
copyStr( OFF_errorMessage, manifest.errorMessage, MAX_IDENTIFIER );
```

### Existing accessor precedent to mirror for `GetLastManifest()`
```cpp
// Source: SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp:155-160 (existing, unmodified)
float GetProgress() const
{
    if ( m_processor )
    {
        return m_processor->GetProgress();
    }
    return 0.0f;
}
```

## State of the Art

| Old Approach (Phase 08) | Current/New Approach (Phase 16) | When Changed | Impact |
|--------------------------|-----------------------------------|---------------|--------|
| `DeserializeManifest`: `bytes.size() != MANIFEST_SERIALIZED_SIZE` hard-fail | `bytes.size() < MANIFEST_SERIALIZED_SIZE` — tolerates trailing/extension bytes | This phase (ARTF-10) | First time this format supports any additive field without a breaking change |
| No error string anywhere in the manifest (D-15: "error details live in logs") | `errorMessage[256]` inline field, populated for all `ProcessingError`-carrying terminal states | This phase (ARTF-09) | A caller with only the manifest (not log access) can now see why processing failed |
| Manifest only ever built on the success path | Manifest built on every terminal path (success or failure), retrievable via `GetLastManifest()` even when `Process()` returns `outcome::failure` | This phase (ARTF-09, structural fix) | Closes the previously-undocumented "manifest never exists on error" gap |

**Deprecated/outdated:** None — this phase extends rather than replaces Phase 08's serialization approach.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A 4-byte `uint32_t schemaVersion` (no magic number) is sufficient for this trailer, since manifests are never persisted as standalone ambiguous-type files in this codebase today | Recommended ARTF-10 Design | Low — if a future phase does start persisting manifests to disk as freestanding files, a magic number could be added to the trailer at that point without breaking this phase's mechanism (it would just be a new, later trailer field) |
| A2 | `GetLastManifest()`/`m_lastManifest` (option 3) is the lowest-risk mechanism versus changing `outcome::result<ProcessOutput>`'s success/failure semantics (option 1) or extending the `Error` outcome type (option 2) | Recommended ARTF-09 Design | Medium — this is a design recommendation, not a locked decision (CONTEXT.md leaves "how `ProcessingManager` integrates..." fully to discretion); if the planner has a different preference informed by information this research didn't have (e.g. an in-flight design elsewhere in the codebase this research didn't discover), that should override this recommendation |
| A3 | No manifest has ever been persisted to disk or otherwise survives past a single `Process()` call in the current codebase, so there is no real "old" binary/artifact to test SC4 against | "Why the SC4 proof needs honest reframing" | Low-Medium — verified via grep of all `SerializeManifest`/`DeserializeManifest` call sites in `SGProcessingManager` and `SuperGenius/src`; if some other module (outside those two trees) does persist a manifest blob this research didn't search, the compat test could target real bytes instead of a test-local proxy — worth a final grep sweep at plan time if time permits |

**If this table is empty:** N/A — see above; both A2 and A3 carry Medium-or-lower risk and neither blocks planning, but the planner should sanity-check A3 with one more targeted grep across the full monorepo (not just the two trees this research covered) before writing the SC4 test task.

## Open Questions

1. **Should `errorMessage` be added to `ExecutionManifest` at a new fixed offset within the *original* 5649-byte region (requiring `MANIFEST_SERIALIZED_SIZE` itself to grow and the surrounding fields — none exist after `manifestHash`, so this is moot) or purely in the appended trailer?**
   - What we know: `manifestHash` is the last field in the current struct (`execution_manifest.hpp:82`) and the last thing serialized (`OFF_manifestHash = 5617`, ending at 5649) — there is no "gap" inside the existing layout to reuse; any new field is necessarily appended.
   - What's unclear: Nothing, really — this resolves cleanly to "append after `manifestHash`" once the layout is inspected. Marking this as answered/closed rather than genuinely open, but included for the planner's confidence that no viable in-place alternative was overlooked.
   - Recommendation: Append after byte offset 5649, as designed above.

2. **Exact placement of `errorMessage` relative to `schemaVersion` in the trailer, and exact constant name for the new total size.**
   - What we know: Order within the trailer doesn't affect correctness as long as both `SerializeManifest`/`DeserializeManifest` agree and bounds checks are correct per-field.
   - What's unclear: Naming convention preference (`MANIFEST_V2_SERIALIZED_SIZE` vs. `MANIFEST_SERIALIZED_SIZE_V2` vs. something else) — purely cosmetic, left to planner/implementer discretion per CONTEXT.md's explicit "exact new field name/type... and its offset" discretion grant.
   - Recommendation: Any consistent naming works; suggested `MANIFEST_V2_SERIALIZED_SIZE = 5909` in this research is illustrative, not mandatory.

## Environment Availability

Skipped — this phase has no new external dependencies. It uses the same build/test toolchain every prior phase in this workstream has already used successfully (per `.planning/workstreams/sgproc-render/config.json`: `cmake --build build/Windows/Debug`, `ctest --test-dir build/Windows/Debug -j -C Debug --verbose`), and touches only files already inside the existing CMake target for `SGProcessingManager`'s `artifacts` module and its existing test target (`artifact_serializer_test.cpp` is already wired into ctest per prior phases' STATE.md notes on the ctest `enable_testing()` ordering fix).

## Security Domain

`security_enforcement` is `true` (ASVS level 1) in `.planning/config.json` — this section is required.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | No | This phase touches only in-process data structures; no auth surface |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | **Yes** | Every conditional trailer read in the relaxed `DeserializeManifest` must be preceded by an explicit `bytes.size() >= offset + fieldSize` bounds check before the corresponding `memcpy` — see Pitfall 2. This is the one genuine security-relevant surface this phase introduces (a size-check relaxation is, by definition, a place where bounds discipline can regress). |
| V6 Cryptography | No | The manifest's SHA-256 self-hash (`ComputeManifestHash`) is untouched by this phase — `errorMessage` and `schemaVersion` are appended *after* `manifestHash` is computed over the rest of the struct, so the existing zero-then-restore `manifestHash` dance (`artifact_serializer.cpp:173-178, 227-228`) is unaffected as long as the new trailer fields are included in the byte range that gets hashed (i.e. `SerializeManifest`'s full output, trailer included, is what `ComputeManifestHash` hashes — confirm this remains true once the vector is resized to the v2 total length). |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Truncated/corrupted manifest blob causing an out-of-bounds read when the trailer's `schemaVersion`/`errorMessage` fields are read past the buffer's actual length | Tampering / Denial of Service | Explicit `bytes.size() >= offset + fieldSize` check before every trailer-region `memcpy`, defaulting the field on failure instead of reading (see code sketch above) |
| `ProcessingError::message` (potentially containing internal paths/VkResult detail) now propagating into a structured artifact instead of staying log-only | Information Disclosure | Accepted, deliberate tradeoff per D-11/D-12 (no current external consumer); flag in verification notes for future revisit if/when an external manifest export path is added (Pitfall 4) |

## Sources

### Primary (HIGH confidence — direct codebase reads, this session)
- `SuperGenius/SGProcessingManager/include/artifacts/execution_manifest.hpp` — full read
- `SuperGenius/SGProcessingManager/include/artifacts/artifact_serializer.hpp` — full read
- `SuperGenius/SGProcessingManager/src/artifacts/artifact_serializer.cpp` — full read
- `SuperGenius/SGProcessingManager/include/artifacts/artifact_types.hpp` — full read
- `SuperGenius/SGProcessingManager/include/processors/processing_processor.hpp` (lines 1-80) — read
- `SuperGenius/SGProcessingManager/test/artifacts/artifact_serializer_test.cpp` — full read
- `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` (lines 1191-1560, including the critical-finding region 1319-1511) — read
- `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp` (relevant excerpts: `ProcessOutput`, `Process()`/`ProcessInternal()` signatures, `GetProgress()`, `Error` enum, `OUTCOME_HPP_DECLARE_ERROR_2`) — read
- `SuperGenius/src/processing/impl/processing_core_impl.cpp` (lines 60-155) — read; **not previously named in CONTEXT.md's canonical_refs, discovered during this research and load-bearing for the Critical Finding**
- `.planning/workstreams/sgproc-render/phases/16-manifest-evolution/16-CONTEXT.md` — full read
- `.planning/workstreams/sgproc-render/phases/08-structured-artifacts-execution-manifests/08-CONTEXT.md` — full read
- `.planning/workstreams/sgproc-render/REQUIREMENTS.md` — full read
- `.planning/workstreams/sgproc-render/STATE.md` — full read
- `.planning/workstreams/sgproc-render/ROADMAP.md` (Phase 16 section, lines 71-96) — read
- `.planning/workstreams/sgproc-render/config.json` — read (build/test commands)
- `.planning/config.json` — read (`nyquist_validation: false`, `security_enforcement: true`, `security_asvs_level: 1`)

### Secondary (MEDIUM confidence — WebSearch, general binary-format conventions, not codebase-specific)
- WebSearch: "binary file format schema evolution forward and backward compatibility magic number version header design pattern" — general convention that magic+version belongs at offset 0; used to justify explicitly *departing* from that convention in this specific codebase's integration, not to justify following it literally
- WebSearch: "TLV (type-length-value) versioned binary struct serialization C++ best practices" — general TLV/version-field conventions; informed the recommendation to keep a version field even though full TLV-per-field wasn't deemed necessary for a single new field

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- Standard stack: N/A — no library selection involved; existing in-house pattern confirmed by direct source read (HIGH)
- Architecture (Critical Finding + recommended designs): HIGH — every claim traced to a specific file/line read this session, including the previously-undiscovered production caller
- Pitfalls: HIGH for Pitfalls 1-3 (directly derived from source reads); MEDIUM for Pitfall 4 (a judgment call about future-proofing, not a verified defect)

**Research date:** 2026-08-17
**Valid until:** No natural expiry — this research is tied to the exact current state of the five source files read; valid until any of them changes (e.g. if a different phase touches `ProcessingManager.cpp`'s error-handling paths before Phase 16 executes, this research should be re-checked against the new diff)
