---
phase: 03-discovery-rewards-lifecycle
plan: 01
subsystem: design-docs
tags: [child-wallet, discovery, pubsub, AccountMessenger, monitoring, per-child-info, main-wallet-actions, RevokeTx, proto-extension]

# Dependency graph
requires:
  - phase: 01-child-identity-registration-protocol
    provides: RegistrationTx schema, RegistrationMetadata fields (game_id, publisher_id, dev_wallet, peers_cut)
  - phase: 02-crdt-persistence-pubsub-consensus-authority
    provides: reg/ CRDT namespace, FilterRegistration, pubsub broadcast/subscription, CheckParentChildAuthority gate, certified status
provides:
  - "Complete discovery & monitoring design document (docs/03-01-discovery-monitoring.md)"
  - "Push-primary/poll-fallback discovery mechanism with AccountMessenger proto extension"
  - "Per-child information aggregation from reg/ CRDT + child deltas + local JSON"
  - "Main-wallet action mappings (Fund, Recover, Inspect, Revoke, Detach) to Phase 2/3 mechanics"
  - "First-class RevokeTx recommendation with full consensus gate path"
affects: ["03-discovery-rewards-lifecycle (03-02 reward policy + lifecycle)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Push-primary/poll-fallback discovery with AccountMessenger request/response extension"
    - "Three-source per-child information aggregation (reg/ CRDT + child deltas + local JSON)"
    - "First-class RevokeTx as GeniusTransaction subclass (revoke = 9 in EmbeddedTransaction oneof)"
    - "Exponential backoff polling with push-reset timer"
    - "Certified-status filter on all discovery responses (D-26)"

key-files:
  created:
    - "docs/03-01-discovery-monitoring.md — Complete discovery & monitoring design document (466 lines, 8 sections)"
  modified: []

key-decisions:
  - "Discovery polling uses AccountMessenger request/response pattern (NOT messaging_watcher) — reuses existing HandleNonceRequest/HandleNonceResponse pattern"
  - "ChildDiscoveryRequest/ChildDiscoveryResponse proto arms 10/11 in AccountMessage oneof — additive, backward-compatible"
  - "RevokeTx recommended as first-class GeniusTransaction subclass (revoke = 9 in EmbeddedTransaction), NOT a flagged transfer — cleaner audit trail, no transfer type overloading"
  - "GlobalDB reg/ scan: prefix scan if available, full CRDT iteration fallback (Open Question #2 resolved)"
  - "RegistrationTx schema references 01-01-SUMMARY.md for RegistrationMetadata fields (not stale docs/registration-protocol.md path)"
  - "No new CRDT namespace — discovery is peer-to-peer with local JSON cache"

patterns-established:
  - "Design-document format: anchor points include file path + line number in backtick monospace"
  - "Proto additive evolution: new fields/arms appended at next available number, never renumber"
  - "Cross-document references: Phase 2 design docs cited as docs/02-crdt-registry-pubsub.md and docs/02-consensus-parent-child-authority.md"

requirements-completed: [DISC-01, DISC-02, DISC-03]

# Metrics
duration: 11min
completed: 2026-07-13
---

# Phase 03 Plan 01: Discovery & Monitoring Design Summary

**Complete discovery & monitoring design document specifying push-primary/poll-fallback discovery via AccountMessenger proto extension, three-source per-child information aggregation from reg/ CRDT + child deltas + local JSON, and all five main-wallet actions (Fund, Recover, Inspect, Revoke, Detach) mapped to concrete Phase 2/3 consensus mechanics with file:line anchor points — all without creating any new CRDT namespace.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-07-13T21:38:08-0400
- **Completed:** 2026-07-13T21:49:00-0400
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments

- Produced `docs/03-01-discovery-monitoring.md` (466 lines, 8 sections) — the authoritative design document for main-wallet discovery
- Push path documented end-to-end: CID broadcast → `AddListenTopic(main_address)` → CRDT resolution → certified check → cache
- Poll path specified with full AccountMessenger proto extension: `ChildDiscoveryRequest`/`ChildDiscoveryResponse` at oneof arms 10/11 in `SGAccountComm.proto`, handler methods following `HandleNonceRequest`/`HandleNonceResponse` pattern, GlobalDB `reg/` CRDT scan with certified-status filter
- Explicitly rejects `messaging_watcher` with rationale — extends `AccountMessenger` instead
- Per-child information table maps all DISC-02 fields to `reg/` CRDT, child CRDT deltas, and local JSON cache
- All five main-wallet actions (Fund, Recover, Inspect, Revoke, Detach) mapped to concrete Phase 2/3 consensus rules with gate-by-gate validation paths
- First-class `RevokeTx` recommended as new `GeniusTransaction` subclass (`revoke = 9` in `EmbeddedTransaction` oneof) with full consensus gate path (gates 1-4 + 2.5)
- All three DISC requirements (DISC-01, DISC-02, DISC-03) traceable to document sections with concrete SuperGenius anchor points
- Three researcher open questions resolved (RegistrationTx schema ref, GlobalDB scan, first-class RevokeTx)

## Task Commits

Each task was committed atomically:

1. **Task 1: Write discovery & monitoring design — push/poll discovery + per-child info (DISC-01, DISC-02)** — `d74f996` (feat)
   - Sections 1-5: Overview, Push Path, Poll Path, Per-Child Info, JSON Cache

2. **Task 2: Write discovery & monitoring design — main-wallet actions + traceability + phase hand-offs (DISC-03)** — `6e302cb` (feat)
   - Sections 6-8: Main-Wallet Actions, Traceability, Phase Hand-Offs

## Files Created/Modified

- `docs/03-01-discovery-monitoring.md` — Complete discovery & monitoring design document with 8 sections:
  - §1 Overview — Push-primary/poll-fallback architecture statement, key anchor points table
  - §2 Push Path — End-to-end CID notification flow: RegistrationTx → CRDT write → `SendTransactionItem` → `PubSubBroadcasterExt::Publish` → `AddListenTopic(main_address)` → `GlobalDB::Get(cid)` → certified check → cache
  - §3 Poll Path — AccountMessenger extension (NOT `messaging_watcher`): `ChildDiscoveryRequest`/`ChildDiscoveryResponse` proto (arms 10/11), handler methods (`RequestChildDiscovery`, `HandleChildDiscoveryRequest`, `HandleChildDiscoveryResponse`), `WorkerLoop` integration, `RequestType::ChildDiscovery` enum, GlobalDB `reg/` scan with certified-status filter
  - §4 Per-Child Information — Three-source aggregation table mapping all DISC-02 fields to `reg/` CRDT + child CRDT deltas + local JSON cache with data freshness matrix
  - §5 Local JSON Cache — Schema (`discovered_children.json`), update policy (push → update, poll → merge), exponential backoff polling (30s → 60s → 120s → 300s → 600s cap, push resets timer)
  - §6 Main-Wallet Actions — Five actions: Fund (CONS-01, main-signed transfer), Recover (CONS-02, dst hard-restricted to main_address), Inspect (SYNC-04, read-only CRDT sync), Revoke (LIFE-01/D-36, first-class `RevokeTx` with gate 2→2.5→3→4 path), Detach (LIFE-01/D-35, child-initiated `RegistrationTx` with `detach_flag` and `supersedes_sequence`), action-to-mechanic summary table
  - §7 Requirement Traceability — Table mapping DISC-01..03 to sections with anchor points, decisions reflected table (D-27/D-28/D-29/D-26)
  - §8 Phase Hand-Offs — Dependencies (Phase 1/2 docs), v2 deferrals (PLAT-01/02, ADV-01/02, v2 hardening), integration surface for 03-02

## Decisions Made

- Discovery polling uses `AccountMessenger` (NOT `messaging_watcher`) — the `AccountMessenger` already has `OnRequest`/`OnResponse` dispatch, worker-thread queuing, timeout management, signed messages, and response collection; extending it requires 2 proto additions + 2 handler methods vs hundreds of lines of new infrastructure on `messaging_watcher`
- `ChildDiscoveryRequest`/`ChildDiscoveryResponse` proto arms 10/11 in `AccountMessage` oneof — additive, backward-compatible, follows existing `NonceRequest`/`NonceResponse` pattern at `SGAccountComm.proto:5-17`
- `RevokeTx` recommended as first-class `GeniusTransaction` subclass (`revoke = 9` in `EmbeddedTransaction` oneof), NOT a flagged transfer — cleaner audit trail, no transfer type overloading, dedicated `CheckParentChildAuthority` path
- GlobalDB `reg/` scan: prefix scan if available, full CRDT iteration fallback — acceptable because `reg/` records are sparse (one per child)
- RegistrationTx schema references `01-01-SUMMARY.md` for `RegistrationMetadata` fields (game_id, publisher_id, dev_wallet, peers_cut) — not the stale `docs/registration-protocol.md` path per PLAN.md instruction
- No new CRDT namespace — discovery is peer-to-peer with local JSON cache (`discovered_children.json`)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Threat Model Coverage

All five STRIDE threats from the plan's threat register are addressed in the document:

| Threat ID | Category | Mitigation | Document Section |
|-----------|----------|------------|------------------|
| T-03-01 | Spoofing (push) | CID content-addressed resolution + certified check (D-26) | §2 Push Path, steps 5-6 |
| T-03-02 | Spoofing (poll) | Responder signature verify + CID resolution + certified filter in `HandleChildDiscoveryRequest` | §3.3.2, §3.1 rationale |
| T-03-03 | Elevation of Privilege | All actions invoke `CheckParentChildAuthority` gate + destination restriction | §6.1-6.5, action-to-mechanic table |
| T-03-04 | Denial of Service | Exponential backoff polling (30s→600s cap), push resets timer | §5.3 |
| T-03-05 | Information Disclosure | Accepted — CRDT state is publicly readable by design | §6.3 (Inspect) |

## Next Phase Readiness

- Discovery & monitoring document is complete and ready for the reward policy + lifecycle design (Plan 03-02)
- All SuperGenius anchor points are concrete (file path + line number), enabling 03-02 to reference them directly
- Integration surface for 03-02 is documented in §8.3 — covering reward policy resolution, lifecycle state machine, detach/revoke flows, main replacement, and supersedes conflict resolution
- Phase Hand-Offs section clearly defers v2 concerns (PLAT-01/02, ADV-01/02, v2 hardening)

---

*Phase: 03-discovery-rewards-lifecycle*
*Completed: 2026-07-13*
