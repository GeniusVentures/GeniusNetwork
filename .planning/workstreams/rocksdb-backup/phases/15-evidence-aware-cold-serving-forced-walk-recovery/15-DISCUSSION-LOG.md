# Phase 15: Evidence-Aware Cold Serving & Forced-Walk Recovery - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-17
**Phase:** 15-Evidence-Aware Cold Serving & Forced-Walk Recovery
**Areas discussed:** Marker staging, HasBlock shape (SC3 interpretation), Walk matrix + bounds, Refusal surface

---

## Area selection

All four presented gray areas were selected for discussion (multiSelect). A fifth candidate — TEST-01 fake architecture — was held in reserve and not discussed; it is recorded under the agent's discretion in CONTEXT.md with the Phase 14 D-08 precedent as anchor. At the done-check the user chose "Ready for context" without exploring the reserve area.

## Marker staging

### Q1: How should the /prune/blk marker be staged into the erase batch?

| Option | Description | Selected |
|--------|-------------|----------|
| Widen extra_entry | Widen EraseEntry's opaque extra_entry (globaldb.hpp:489) from one pair to a vector; TxPruner passes both /prune/tx and /prune/blk; single atomic staging point; key shapes in PruneEligibility (D-C1) | ✓ |
| Stage in TM | Keep EraseEntry signature frozen; EraseTransactionEntryWithMarker writes /prune/blk when the block's last member erases; second write must join the same compose-locked batch | |
| Researcher rules | Researcher decides within constraints (atomicity, PruneEligibility key shapes, single-CID removal set, Phase 16 non-contradiction) | |

**User's choice:** Widen extra_entry
**Notes:** Recommended option accepted — atomicity by construction preferred over a mechanism the researcher would have to design to keep the second write in the same batch.

### Q2: What does the /prune/blk/<cid> marker value carry?

| Option | Description | Selected |
|--------|-------------|----------|
| Presence only | Key presence IS the evidence; empty/sentinel value; disposed-marker precedent | |
| Back-reference | Minimal record: erased-at generation + /prune/tx hash back-reference; operator CID→tx traceability; feeds Phase 17 ancestry-density measurement; shaped in PruneEligibility | ✓ |

**User's choice:** Back-reference
**Notes:** Diagnosability valued (never-healthy-by-omission discipline).

### Q3: Pre-existing v1.1 erases — how handled?

| Option | Description | Selected |
|--------|-------------|----------|
| No backfill | Moot if nothing deployed; evidence starts fresh; assumption recorded | |
| Startup backfill | One-time migration scanning /prune/tx values for erased CIDs | |
| Lookup fallback | Predicate falls back to scanning /prune/tx on /prune/blk miss; O(erased txs) per cold-chain miss | |

**User's choice:** No backfill (free-text confirmation)
**Notes:** User free-text: "1.1 refers to this workstream's old milestone? in that case, no backfill, it has not been deployed." — confirmed the premise (v1.1 = this workstream's archived milestone, dev-line only, never deployed) and the conclusion. Recorded as an explicit assumption in CONTEXT.md D-03.

## HasBlock shape (SC3 interpretation)

### Q1: How do we interpret SC3's "consistent across HasBlock, getNode, and the cold chain"?

| Option | Description | Selected |
|--------|-------------|----------|
| Source-consistency | HasBlock stays bool, body unchanged (dedup-correct TRUE); all surfaces derive from the ONE GlobalDB predicate; SC3 evidence = consistency test; matches develop SURV-02 posture | ✓ |
| Tri-state variant | HasBlockEx/BlockAvailability returning tri-state + Present; callers migrate where distinction matters; SC3 asserts shape-consistency | |
| False-for-pruned | HasBlock false for pruned, aligned with getNode refusal; research rules against (loses dedup win) | |

**User's choice:** Source-consistency
**Notes:** Framed as the Phase-14-D-01-style SC-interpretation ruling. Reversibility rated costly in CONTEXT.md D-04 (defines SC3's evidence contract).

## Walk matrix + bounds

### Q1: Walk visit: sealed, not retained, no cold bytes, no prune evidence — what happens?

| Option | Description | Selected |
|--------|-------------|----------|
| Peers→abort | Fall through to getNode (peers eligible), bounded by per-CID failover budget; exhausted → loud abort with distinct walk-gap error + counter | ✓ |
| Immediate abort | No peer attempt; unexplained absence is immediately a gap | |
| Skip+counter | Treat like prune-skip under skipped_unknown; violates abort-never-skip | |

**User's choice:** Peers→abort
**Notes:** The fourth quadrant was characterized as unreachable in a healthy system (TxPruner-erased ⇒ evidence; GC-evicted ⇒ cold bytes) but reachable via corruption/manual deletion/seal-only remnants.

### Q2: Per-CID peer-failover budget defaults — what posture given the validating probe runs later (Phase 17)?

| Option | Description | Selected |
|--------|-------------|----------|
| Constants+TODO | Named constants with conservative values + Phase 17 re-tune TODO; Phase 14 D-04 no-config posture | |
| Config knobs | sgns_config surface with conservative defaults | |
| Derive v1.1 | Compute defaults from recorded v1.1 walk-recovery test numbers; rationale recorded | ✓ |

**User's choice:** Derive v1.1
**Notes:** User selected against the recommended option. Coherence note recorded: derive-now from v1.1 numbers, Phase 17 probe validates/re-tunes later — the recorded Phase 15↔17 dependency holds in both directions. Research directive added to locate the v1.1 walk-recovery numbers.

## Refusal surface

### Q1: How far does pruned-distinct-from-not-found go at the protocol surface this phase?

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror develop | Local tri-state + distinct GraphsyncDAGSyncer::Error; responder clean standard refusal; existing per-CID accounting; zero wire/proto changes | ✓ |
| Wire-level signal | New graphsync response extension carrying 'pruned'; develop rejected this shape; proto compatibility cost | |
| Researcher rules | Researcher confirms mirror posture against actual code paths incl. A5 caveat | |

**User's choice:** Mirror develop
**Notes:** Grounding presented before the question: develop's completed SURV-02 = local distinct ("history pruned") + clean standard RS_NOT_FOUND/CID_NOT_FOUND peer refusal + per-CID RecordCIDFailure failover accounting (19-05 local half, 19-07 peer half, verified on real pubsub). A5 caveat (wire status value plumbing-verified, not exercised) carried into CONTEXT.md research directives.

## The Agent's Discretion

- TEST-01 fake architecture (seeded real-RocksDB vs in-memory PrunedLookup fake; refusal-matrix-as-product shape) — held in reserve, not discussed; Phase 14 D-08 precedent noted
- Predicate injection mechanics (interface shape at the OpenColdStorageStack seam)
- Cold-present probe mechanics in the walk
- Error enum naming/placement; walk-gap error + counter naming
- Consistency-test shape (SC3 evidence)
- Tier placement of new deterministic suites (Tier-1 expected per precedent)
- Interrupt-seam extensions for induced-evidence tests

## Deferred Ideas

- Wire-level graphsync "pruned" signal — rejected this phase (D-07); its own future phase if ever wanted
- /prune/blk backfill migration or /prune/tx-scan fallback — moot per D-03 deployment premise; revisit only if deployment posture changes
- Vulkan capability-probe todo — reviewed, not folded (third consecutive phase; keyword-only match)
