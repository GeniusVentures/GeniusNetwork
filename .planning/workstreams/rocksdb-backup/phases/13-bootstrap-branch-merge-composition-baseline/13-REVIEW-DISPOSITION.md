---
phase: "13"
source_review: 13-REVIEW.md
total_findings: 2
open: 2
accepted: 0
fixed: 0
recorded: 2026-11-24
---

# Phase 13 Review Disposition

Per-finding ledger for the advisory code review recorded in `13-REVIEW.md`
(retrospective review of merge `2af184fa1` + baseline fix `4ae8a9a4e`; 0 critical / 0 major).

| Finding | Severity | Disposition | Note |
|---------|----------|-------------|------|
| F-1: Unbounded `routing_` accumulation for already-stored CIDs (`pubsub_broadcaster_ext.cpp:643` / `graphsync_dagsyncer.cpp:361`) — no eviction path for routes added for present blocks; slow growth on long-running nodes | minor | open | The deliberate forced-walk recovery enabler; correctness unaffected, 6 phases of green CI on top. Candidate for a bounded-lifecycle sweep or an accepted-risk record with an operator metric on `routing_.size()`. |
| F-2: `bootstrap_walk_max_retries: 0` not expressible — `read_walk_limit` rejects explicit zero, silently falls back to 8 | info | open | Config-surface gap only; "disable retries" needs a different encoding if ever required. |

*Advisory record only — neither finding blocks phase completion. Triage candidates for the milestone wrap or the v1.2+ backlog.*
