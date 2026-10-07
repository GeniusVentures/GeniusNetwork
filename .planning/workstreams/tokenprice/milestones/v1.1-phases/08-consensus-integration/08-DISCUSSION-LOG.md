# Phase 8: Consensus Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-06
**Phase:** 8-Consensus Integration
**Areas discussed:** Validator hook point, Escrow return mechanism, Rejection semantics & convergence, Multi-node test shape

---

## Validator hook point

| Option | Description | Selected |
|--------|-------------|----------|
| At task claim — GrabTask path | Validate before locking; MarkTaskBad skip on reject | |
| At payout — before AsyncPayEscrow | Gate the payout in ProcessingDone | |
| Both claim and payout | Defense in depth at both ends | |

**User's choice:** (free text) "I feel like they should run it at crdt sync. We have existing consensus mechanisms in place, maybe in transactionmanager? We should generally follow that."
**Notes:** Redirected the question from the presented options to CRDT-sync-time enforcement via existing consensus machinery. Follow-up question explored which seam.

| Option | Description | Selected |
|--------|-------------|----------|
| Task-record callback at sync | GlobalDB RegisterNewElementCallback on task keys; MarkTaskBad skip | |
| Escrow-transaction consensus gate | Extend ValidateTransactionForConsensus / ParseEscrowTransaction to cross-reference claimed_price | ✓ |
| Both | Callback enforcement + escrow-side log-only check | |

**User's choice:** Escrow-transaction consensus gate
**Notes:** Accepts the cross-reference cost (task lookup from the tx validator) in exchange for enforcement living inside consensus proper.

| Option | Description | Selected |
|--------|-------------|----------|
| Pending until task syncs | Migration-allowlist Pending() precedent; escrow waits for its task | ✓ |
| Atomic poster-side commit | Escrow hold + task enqueue in ONE CRDT transaction | |
| Skip-if-absent | Gate checks only when task is local; enforcement falls to claim time | |

**User's choice:** Pending until task syncs
**Notes:** Ordering problem surfaced during discussion: poster commits escrow first, task second — gate can see escrow before task.

| Option | Description | Selected |
|--------|-------------|----------|
| Escrow tx not applied locally | Funding vanishes from rejecting node's state; return handled separately | ✓ |
| Accept escrow, block task | Escrow applies; task fails gate; refund via existing release path | |
| Reject + auto-release at gate | Rejector constructs EscrowReleaseTx immediately at gate time | |

**User's choice:** Reject = escrow tx not applied locally
**Notes:** Separates the verdict from the refund mechanism.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, claim-time backstop | GrabTask runs ValidatePrice before locking; MarkTaskBad skip | ✓ |
| No, gate only | Single enforcement point | |

**User's choice:** Yes, claim-time backstop
**Notes:** Belt-and-suspenders for catchup-synced tasks; validator is pure so cost is negligible.

## Escrow return mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| First honest rejector releases | First rejector constructs consensus-certified EscrowReleaseTx to poster's release_address | ✓ |
| Expiry-based return | TTL; unpicked escrow returns after timeout | |
| Poster reclaims | Poster's node releases after its job times out unpicked | |

**User's choice:** First honest rejector releases

| Option | Description | Selected |
|--------|-------------|----------|
| New consensus subject for rejections | Typed rejection subject (task ref + reason + escrow ref), independently verifiable | ✓ |
| Reuse existing escrow-release tx path | Ordinary consensus-validated transaction; no new subject type | |
| Defer to researcher/planner | Capture intent, let research pick the mechanism | |

**User's choice:** New consensus subject for rejection releases
**Notes:** A rejection has no task result, so the TASK_RESULT subject can't carry it.

| Option | Description | Selected |
|--------|-------------|----------|
| Full refund, no burn | Penalties deferred in Phases 6/7; requirement is "escrow is returned" | ✓ |
| Burn applies | Treat rejection release like any other release; mild spam deterrent | |

**User's choice:** Full refund, no burn

## Rejection semantics & convergence

| Option | Description | Selected |
|--------|-------------|----------|
| No honest node processes a gamed job | Per-node fail-closed; uncovered node skipping honest job is harmless | ✓ |
| Identical verdicts everywhere | All honest nodes same verdict on same job | |
| Identical only for gamed case | Objective out-of-band verdicts converge; NO_COVERAGE divergence tolerated | |

**User's choice:** Convergence = no honest node processes a gamed job

| Option | Description | Selected |
|--------|-------------|----------|
| Rejection marker in CRDT | Rejector writes rejection record; others skip without re-validating | |
| Local-only rejection | Only cross-node artifact is the certified release | |
| Local + log-only broadcast | Local record + diagnostics logging; no new CRDT type | |

**User's choice:** (free text) "Do whatever existing consensus does."
**Notes:** Interpreted as: propagation rides existing consensus mechanics (rejection-release subject + validation verdicts); no parallel CRDT marker.

| Option | Description | Selected |
|--------|-------------|----------|
| Per-node skip only | Gate + backstop; no network-wide tombstone | ✓ |
| Network-wide cleanup | Rejector tombstones claimable entry in CRDT | |

**User's choice:** Per-node skip only

## Multi-node test shape

| Option | Description | Selected |
|--------|-------------|----------|
| Extend ProcessingNodesTest | New cases in existing 3-node suite | ✓ |
| New dedicated test file | Separate suite, own fixture | |
| Both layers | Multi-node case + hermetic gate-level unit tests | |

**User's choice:** Extend ProcessingNodesTest

| Option | Description | Selected |
|--------|-------------|----------|
| Poster API with stub price manipulation | Real ProcessImage path; flip stub price so claim is out-of-band | ✓ |
| Inject hand-built Task proto | Craft Task + escrow directly into CRDT | |
| Both | Manipulation for multi-node; injection for reason coverage | |

**User's choice:** Poster API with stub price manipulation

| Option | Description | Selected |
|--------|-------------|----------|
| Poster balance restored + release confirmed | Balance returns to pre-post level and/or WaitForEscrowRelease confirms | ✓ |
| Balance-only | Simplest assertion | |
| Release record visible | Assert artifact existence in poster's node state | |

**User's choice:** Poster balance restored + release confirmed

---

## the agent's Discretion

- Rejection-subject proto naming/fields; cross-reference lookup placement; Pending re-evaluation mechanics; release construction plumbing; backstop input assembly; logging/metrics naming; test helper organization.

## Deferred Ideas

- Trust/reputation + penalties for repeat offenders (carried from Phases 6/7).
- Volatility-telemetry-derived tolerance/window defaults (carried from Phase 7).
