# Phase 4: Grid Integration & E2E Proof - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-14
**Phase:** 4-Grid Integration & E2E Proof
**Areas discussed:** Schema amendments, Settlement stamps & refund, Results artifact convention, E2E test shape

---

## Schema Amendments

### Stop-string job-JSON carriage (STATE.md TODO escalation #1)

| Option | Description | Selected |
|--------|-------------|----------|
| Amend now | Add `stop` array to ElmGeneration; regen quicktype; validator bound; splitter passes through to stopStrings parameter. Requestor stop strings work end-to-end in v1.0 | ✓ |
| Defer to v1.1 | Keep stopStrings parameter as only entry; requestor jobs can't request stop strings in v1.0; document as gap | |
| Parse-only stub | Schema parses and round-trips the field but splitter logs-and-ignores it — silent no-op, the set_config trap Pitfall 2 warns about | |

**User's choice:** Amend now (recommended)
**Notes:** Full end-to-end stop strings in v1.0.

### Stop array bounds

| Option | Description | Selected |
|--------|-------------|----------|
| Bound it | Max 4 stop strings, each 1-128 chars UTF-8, no empty strings; reject-at-parse on violation (never clamp). OpenAI's max-4 convention | ✓ |
| Unbounded | No schema-level limits; streambuf scan handles whatever arrives; adversarial 10k-string stop list is a bounded per-token CPU cost | |
| You decide | Whatever bound falls out of existing schema conventions and quicktype constraint survival rules | |

**User's choice:** Bound it (recommended)
**Notes:** OpenAI max-4 convention adopted.

### Embedding-role manifest amendment (STATE.md TODO escalation #2)

| Option | Description | Selected |
|--------|-------------|----------|
| Add role | `embedding_file` as 6th OPTIONAL role (not in kRequiredRoles) at `embeddings_bf16.bin`; schema + regen + RoleFileName + cache publishes when declared; Qwen-class bundles stop needing test-side injection | ✓ |
| Defer to v1.1 | Embedding-by-default bundles out of v1.0 scope; E2E uses a bundle without embeddings or documents the injection workaround; role set stays at five | |
| Research first | Propose the exact mechanism after checking MNN's embedding discovery (tie_embeddings, DiskEmbedding fallback) during research | |

**User's choice:** Add role (recommended)
**Notes:** Optional role — embedding-less models unaffected.

---

## Settlement Stamps & Refund

### Where grab/finish stamps live

| Option | Description | Selected |
|--------|-------------|----------|
| On envelope | Extend ElmEnvelope with grab_time_usec/finish_time_usec; ElmEnvelopeToJson emits them. Stamps travel with the exact artifact settlement reads via fetchOutputData — one fetch, no second channel | ✓ |
| Beside envelope | Stamps in SubTaskResult/payout_metadata proto-adjacent JSON; envelope stays 6-key pure but settlement needs a new carriage mechanism | |
| Derive from queue | Worker stamps only finish; finalizing node computes grab from queue-lock records — fragile cross-restart/cross-node data the design deliberately avoided | |

**User's choice:** On envelope (recommended)
**Notes:** Additive change to Phase 3's six-key envelope contract.

### How the E2E proves refund (FUND-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Real refund leg | E2E asserts full mechanics: escrow held = declared max; payout = measured windows (proportional OD-3); refund output returns remainder to escrow source; conservation holds. Short max_output_tokens makes refund non-trivially nonzero | ✓ |
| Unit-only refund | E2E proves generation + publication; refund arithmetic unit-proven on BuildPayoutOutputs' ELM branch with synthetic stamps; real-stamps-to-real-payout wiring unproven until v1.1 | |
| Minimal assert | E2E runs with measured ≈ declared (refund ≈ 0), just asserts conservation — weakens FUND-03/SC-2 | |

**User's choice:** Real refund leg (recommended)
**Notes:** None.

---

## Results Artifact Convention

### How the ELM result artifact reaches ipfs:// + local results/

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse save loop | ELM path derives its output URL like non-ELM jobs (FileManager cacheDir + /results/) and reuses the EXISTING SaveASync dual-save loop verbatim — an ELM branch feeding it, not a parallel save path | ✓ |
| Dedicated saver | ELM writes via its own save routine — simpler call but forks the save path; Pitfall 12's divergence warning applies to forks too | |
| Research first | Planner picks after examining how the outputs[]-keyed loop behaves fed an ELM-shaped output set | |

**User's choice:** Reuse save loop (recommended)
**Notes:** ipfs_results_data_id carries the artifact location back exactly as today.

### Inline vs artifact split for envelope text

| Option | Description | Selected |
|--------|-------------|----------|
| Always artifact | Inline SubTaskResult payload = envelope WITHOUT text (work_item_id, counts, finish_reason, manifest hash, stamps, artifact hash); text lives ONLY in the artifact. No threshold logic, no 4KB boundary case | ✓ |
| 4KB threshold | Pitfall 12's original shape: text inline when ≤ 4KB, artifact-only above — size-dependent dual behavior plus the boundary case in tests | |
| All inline | Everything inline including full text (current MNN_Llm behavior) — listed as technical debt in PITFALLS | |

**User's choice:** Always artifact (recommended)
**Notes:** Supersedes Pitfall 12's threshold suggestion; simpler single convention.

---

## E2E Test Shape

### Topology

| Option | Description | Selected |
|--------|-------------|----------|
| One node | ONE GeniusNode (is_processor=true) submits and executes its own job — true single-node grid path (submit → gossip → grab → execute → publish → payout on one node) | ✓ |
| Two nodes | Requestor + processor via gossip (processing_multi_test shape) — exercises cross-node channel but doubles startup and adds flake surface for a single-node milestone | |
| One node + overtime leg | One node for main E2E plus a second terminal-envelope leg on the same node with tiny funding | |

**User's choice:** One node (recommended)
**Notes:** The overtime leg was selected as a separate decision (below).

### Fixture transport

| Option | Description | Selected |
|--------|-------------|----------|
| Real IPFS path | Test publishes the fixture via FileManager to ipfs://; job JSON points at real URIs; E2E exercises the REAL download path (empty cache → fetch → verify → generate) | ✓ |
| file:// URIs | Local-copy transport; still exercises fetch→verify→generate but skips IPFS/bitswap — the ipfs:// leg stays unproven until v1.1 | |
| Both paths | Main E2E on file:// for reliability plus a separate smaller ipfs:// leg — two fixture conventions to maintain | |

**User's choice:** Real IPFS path (recommended)
**Notes:** None.

### Work-item count

| Option | Description | Selected |
|--------|-------------|----------|
| 2 items, 1 model | Proves 1:1 splitter mapping, elm_subtask_map, single-flight dedup (two subtasks, one download), and order-independence in one run; model cost paid once | ✓ |
| 1 item minimal | Minimal acceptance shape; splitter mapping and single-flight stay unit-proven only | |
| 2 models | Different manifests prove cache keying at scale; doubles fixture weight (~1.1GB) for marginal v1.0 value | |

**User's choice:** 2 items, 1 model (recommended)
**Notes:** Single-flight gets its first grid-level proof.

### Terminal-state (overtime) leg

| Option | Description | Selected |
|--------|-------------|----------|
| Include overtime leg | Tiny funding drives real deadline overrun → cancel → terminal envelope (cancelled/BUDGET_EXCEEDED) published → NOT re-grabbed (Pitfall 10's E2E verification leg) | ✓ |
| Happy path only | Terminal states stay unit-proven (Phase 3 legs); E2E proves only happy path + refund — shorter runtime | |
| Planner decides | Whether the overtime leg belongs in the E2E target or a separate binary (CTest TIMEOUT budget governs) | |

**User's choice:** Include overtime leg (recommended)
**Notes:** Exact funding value and test-binary placement left to planner discretion.

---

## Claude's Discretion

- ProcessImage ELM-branch shape and elm_subtask_map writing mechanics (follow Phase 1 design verbatim)
- input_uri prompt resolution placement (ProcessInternal ELM branch vs pre-step)
- Overtime-leg funding value and test-binary placement (CTest TIMEOUT budget governs)
- Production cache construction site and lifetime
- Unit-test structure for splitter, settlement branch, results-convention legs
- Inline envelope-minus-text serialization onto SubTaskResult fields (follow validation-core-accepted conventions)
- Backward-compat mechanics of both schema amendments (researcher verifies quicktype regen realities)

## Deferred Ideas

None — discussion stayed within phase scope.
