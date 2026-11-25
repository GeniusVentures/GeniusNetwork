---
phase: 15-evidence-aware-cold-serving-forced-walk-recovery
source: [15-REVIEW.md]
recorded: 2026-11-17
reviewer: gsd-code-reviewer (standard depth, 26 files)
severity_counts: { critical: 1, warning: 2, info: 3, total: 6 }
---

# Phase 15 Review Disposition

Per-finding ledger for `15-REVIEW.md`. Status defaults to `open` at recording time;
a triaged finding must be distinguishable downstream from a forgotten one.

| ID | Severity | Title | Status | Notes |
|----|----------|-------|--------|-------|
| CR-01 | Critical | Serve-side TOCTOU: TxPruner erase committing between evidence consult and Rehydrate resurrects erased bytes hot (persists until eviction) | open | Defeats the phase headline invariant under concurrency. Walk path is protected (InitCIDBlock defers erase); getNode/GetNodeWithoutRequest/re-warm surfaces are not. Proposed fix: re-classify after the slow cold Get, before Rehydrate; same for the re-warm worker window. |
| WR-01 | Warning | Evidence lambda fails OPEN on `CID::toString()` error (prefix-only key → NoEvidence → serve) | open | Contradicts the Pitfall 7 fail-closed discipline applied to every other decode error. Low practical reachability. Fix: classify Malformed. |
| WR-02 | Warning | Failover budget consumed by peers whose RequestNode never initiates (sync dial failures burn the bound) | open | Fail-closed direction (bound never exceeded) — availability impact on RECOVER-02 restore only. Fix: refund/relocate the increment. |
| IN-01 | Info | Two parallel decoders of the `/prune/blk` row — `PruneEligibility::LookupPrunedBlockEntry` has no production caller | open | Consolidation candidate. |
| IN-02 | Info | `EraseTransactionEntryPruned` default `generation = 0` records `has_erased_at_generation = true` with a synthetic value | open | Semantics hygiene on the D-02 record. |
| IN-03 | Info | Dead arm in the walk-gap abort log | open | Cosmetic. |

## Triage guidance

- CR-01 is the load-bearing item. Natural homes: a `$gsd-quick` fix before Phase 16
  (the proposed re-consult patch is small and the interrupt-hook test kit from 15-03
  can carry the deterministic repro), or folded into Phase 16 (pruner×GC hardening)
  planning as an explicit requirement — it is exactly a pruner/serve race.
- WR-01/WR-02 are small, same-file fixes; both fit the same quick task.
- Info items can ride Phase 16/17 or be dropped by design decision.
