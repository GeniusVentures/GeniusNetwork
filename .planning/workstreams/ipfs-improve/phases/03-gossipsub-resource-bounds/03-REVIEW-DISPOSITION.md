---
phase: 03-gossipsub-resource-bounds
review: 03-REVIEW.md
recorded: 2026-10-13
total_findings: 5
counts:
  critical: 0
  major: 1
  minor: 2
  info: 2
dispositions:
  open: 5
  fixed: 0
  wont_fix: 0
  deferred: 0
---

# Phase 03 Review Disposition

Per-finding disposition ledger for `03-REVIEW.md` (code review is advisory — this records what
happened to each finding; default state is `open`).

| ID | Severity | One-line summary | Disposition | Notes |
|----|----------|------------------|-------------|-------|
| MAJ-01 | major | `m_sustainedOverflowCloses` per-peer close-counter map has no eviction (not on block/UnblockPeer/disconnect) — Sybil can pin map entries; post-unblock peer re-blocks on a single close (D-09 tolerance lost) | open | Legitimate gap; not D-10-locked. Candidate for a small follow-up (gsd-quick on dev_ipfs_fix, ~6-line additive fix) BEFORE Phase 4 repin |
| MIN-01 | minor | `GossipCore::setViolationHandler` called after `start()` is a silent no-op (stored, never forwarded to Connectivity) | open | In-tree caller registers pre-start (verified race-free); document or assert |
| MIN-02 | minor | Default cap can drop batched/piggybacked legitimate RPCs (>1<<24 with empty queue) → sustained-overflow → honest slow mesh peer permanently blocked | open | Partially plan-locked (D-02/D-07/D-09); the batching consequence is undocumented — carry into fork-maintenance backlog alongside deferred-items.md |
| INF-01 | info | Pure-virtual `setViolationHandler` on public `Gossip` is source-breaking for out-of-tree implementers | open | Plan-acknowledged (only in-tree implementer is GossipCore); compatibility note for the repin phase |
| INF-02 | info | Strong-capture violation post + `this`-capturing handler teardown path | open | Traced safe via StopImpl ordering; plan-locked Flagged Assumption #5; ASan clean; adjacent fixture issues already in deferred-items.md 2/3 |

**Recorded by:** execute-phase orchestrator (code_review_gate), 2026-10-13.
