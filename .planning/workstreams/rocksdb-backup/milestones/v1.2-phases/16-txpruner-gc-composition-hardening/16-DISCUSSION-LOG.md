# Phase 16: TxPruner × GC Composition Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-18
**Phase:** 16-TxPruner × GC Composition Hardening
**Areas discussed:** Sequencing ruling, Stale-LRU close, Interleave matrix, Starvation ruling

---

## Sequencing ruling

| Option | Description | Selected |
|--------|-------------|----------|
| Convergence-proof | Both may run concurrently; the interleave matrix proves both orders converge to one fixed point. No new lock. Matches SC2's letter and the research lean ("no coordination needed"). | ✓ |
| Hard mutex | Serialize whole TxPruner cycles and GC passes (261029-uj0 GcPassOnce class). Cheapest safety argument, but adds coupling the "never unify" decision resists. | |
| Proof-then-gate | Attempt convergence-proof first; land the mutex for a divergent seam only, documented. | |

**User's choice:** Convergence-proof
**Notes:** Recorded as D-01. The mutex class was explicitly rejected, not just deprioritized — deferred-ideas section records it as considered.

| Option | Description | Selected |
|--------|-------------|----------|
| Existing locks | Ruling asserts both destructive durability readers already serialize on existing locks (cold_store_mutex_ / compose lock) — verify on post-Phase-15 line, document at both homes, race-test. No new machinery. | ✓ |
| Symmetric re-check | TxPruner already re-checks in-compose; GC gains a symmetric delete-time durability re-check. Stronger but unnecessary — remote S3 is never deleted in v1.2. | |
| Researcher rules | Researcher maps actual lock coverage and proposes the ruling; discuss-level decision is only "no new gate without race evidence". | |

**User's choice:** Existing locks
**Notes:** Recorded as D-02. Satisfies the Phase 14 D-06 deferral ("must not contradict Phase 16's Interaction-C ruling") without new gate machinery.

| Option | Description | Selected |
|--------|-------------|----------|
| Fix-forward | Repair the interleave (idempotence fix) and keep concurrency — divergences are bugs in one pruner's idempotence contract. | ✓ |
| Seam mutex | Land the mutex for the offending seam only, keep the rest concurrent. Fast containment but contradicts the convergence story. | |
| User checkpoint | Stop and escalate with the failing interleave — divergences are design-level signals. | |

**User's choice:** Fix-forward
**Notes:** Recorded as D-03.

## Stale-LRU close

| Option | Description | Selected |
|--------|-------------|----------|
| In EraseEntry | Unconditional post-commit DeleteCIDBlock for every caller — single home, matching the "EraseEntry stays THE single staging point" philosophy. GC's A6 stays untouched (idempotent double-delete harmless). | ✓ |
| TxPruner only | Only the TxPruner-staged path gets the cleanup (flag/parameter). Smaller blast radius, but the window stays open for other callers. | |
| Consolidate | Put it in EraseEntry AND remove GC's A6 (one invalidator). Edits GC's sanctioned order — the surface this phase proves, not modifies. | |

**User's choice:** In EraseEntry
**Notes:** Recorded as D-04.

| Option | Description | Selected |
|--------|-------------|----------|
| Keep both | Guard 3 keeps deferring LRU-resident erases; post-commit delete closes only the race window. Smallest behavioral delta. | ✓ |
| Remove guard 3 | Full GC parity — erases proceed on cached CIDs. Bigger admission change than SC1's letter demands. | |
| Researcher rules | Check what guard 3's deferral costs (LRU residency starvation vs cycle period) and propose with numbers. | |

**User's choice:** Keep both
**Notes:** Recorded as D-05. Admission semantics unchanged — compose-don't-pick.

## Interleave matrix

| Option | Description | Selected |
|--------|-------------|----------|
| Both layers | Real-thread barrier-driven races + deterministic seam-stepped interleavings. Each covers what the other can't (261029-uj0 OSX timing vs forced exact orderings). | ✓ |
| Seam-stepped only | Fully reproducible, no flake risk, but never exercises true lock contention. | |
| Real-thread only | True contention, but specific orderings (SC1's window) can't be forced reliably. | |

**User's choice:** Both layers
**Notes:** Recorded as D-06.

| Option | Description | Selected |
|--------|-------------|----------|
| Fold crossfire in | One matrix product over all shared surfaces including both marker namespaces, with Pitfall 5 crossfire invariants as matrix assertions. | ✓ |
| Separate suites | Matrix covers only the SC2 letter's surfaces; crossfire stays a separate GC-02-style invariant suite. | |
| Both homes | Fold key rows + extend GC-02 as a fast standalone gate — two assertion homes for the same invariants. | |

**User's choice:** Fold crossfire in
**Notes:** Recorded as D-07.

| Option | Description | Selected |
|--------|-------------|----------|
| Rows + answers | Byte-level row convergence via exact prefix enumeration AND observable equivalence (HasBlock / getNode / predicate). | ✓ |
| Rows only | Strongest single claim, but hides answer differences (e.g. LRU residue). | |
| Answers only | Resilient to benign differences, but SC2's "one fixed point" is a state claim. | |

**User's choice:** Rows + answers
**Notes:** Recorded as D-08. Gives "one fixed point" a mechanical definition.

| Option | Description | Selected |
|--------|-------------|----------|
| Tier-1, no soak | Deterministic suites enter CI Tier-1 (14-D-09 precedent); no soak-scale leg — SC2 is correctness, not capacity. | ✓ |
| Tier-1 + soak leg | Plus one modest-multiplicity soak leg (~10² iterations) for storm-class drift. Costs three-platform runner time. | |
| Tier-2 first | Local-only until proven stable; defers the three-platform contract Phase 19 builds on. | |

**User's choice:** Tier-1, no soak
**Notes:** Recorded as D-09.

## Starvation ruling

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-marker skip | Gate consults GC's disposed markers for NoRecord constituents: explicit deferral + SPLIT counter, still under-prune. Reads via the GC module's key builder. | ✓ |
| Document only | Minimal SC3 letter compliance; NoRecord defers silently as one undifferentiated mass. | |
| Erase on disposed | Gate accepts disposed-marker + remote-presence as erase-sufficient. Adds S3 GET I/O; research recommended against for v1.2. | |

**User's choice:** Cross-marker skip
**Notes:** Recorded as D-10. Chosen for operator visibility of stranded mass (Phase 17/18 feed) per the MI-02 never-healthy-by-omission precedent. Still under-prune — never an erase.

| Option | Description | Selected |
|--------|-------------|----------|
| Both legs | Tier-1 journal-injection leg (red-first) + one dev-gated live GC-dispose→TxPruner-cycle leg. | ✓ |
| Injection only | Deterministic, but might model the wrong post-disposal state. | |
| Live sequence only | Most faithful, but dev-gated and slower to iterate red-first. | |

**User's choice:** Both legs
**Notes:** Recorded as D-11. Mirrors the Phase 14 D-08 hybrid posture.

| Option | Description | Selected |
|--------|-------------|----------|
| Code + doc | Comments at both destructive homes (TxPruner gate + EvictLocalAndMarkDisposed) + workstream planning doc with the full ruled analysis. | ✓ |
| Doc only | Cleaner source tree, but future editors won't see the interplay warning where they work. | |
| Code only | Lightest, but SC3's "ruled and documented" reads as more than a comment, and Phase 18 needs a citable record. | |

**User's choice:** Code + doc
**Notes:** Recorded as D-12. The sequencing/Interaction-C ruling (D-02) gets the same code-at-both-homes treatment.

---

## the agent's Discretion

- Interrupt-seam placement/naming for the SC1 window counter-test
- Barrier design and env-knob scheme for real-thread legs (Windows/macOS flake containment)
- Prefix-spy keyspace enumeration scope per fixture
- Counter naming for the D-10 split and per-cycle INFO surfacing
- Matrix fixture design (overlapping CID sets, seal rows, both marker namespaces)
- Home and name for the workstream ruling doc
- Post-commit delete iteration mechanics (vector vs helper)
- Anchor re-location procedure against the final post-Phase-15 state

## Deferred Ideas

- `DisposedDurable` journal terminal state (v2 — REQUIREMENTS Future)
- Erase-on-disposed with remote-presence verification (rejected this phase)
- Hard mutual exclusion of TxPruner × GC (rejected by D-01; recorded as considered)
- Removing guard 3 for full GC parity (rejected by D-05; measured-trigger future item)
- Soak-scale composition evidence (Phase 17/19 territory)
