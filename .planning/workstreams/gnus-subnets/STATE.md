---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: GNUS Subnets Architecture
current_phase: 1
current_phase_name: Subnet Addressing Scheme
status: Ready to plan
stopped_at: Phase 1 context gathered
last_updated: "2026-07-25T01:44:43.147Z"
last_activity: 2026-07-24
last_activity_desc: ROADMAP.md created, all 13 v1 requirements mapped
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Current Position

Phase: 1 of 4 (Subnet Addressing Scheme)
Plan: — (not yet planned)
Status: Ready to plan
Last activity: 2026-07-24 — ROADMAP.md created, all 13 v1 requirements mapped

Progress: [░░░░░░░░░░] 0%

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-24)

**Core value:** Produce design documentation defining how isolated GNUS subnets (`net_id.subnet_id`) address, communicate, bridge tokens, and isolate job/consensus processing — no implementation this milestone.
**Current focus:** Phase 1 — Subnet Addressing Scheme (fixes the composite identity every other phase reads from)

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: N/A
- Total execution time: N/A

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table (milestone workstream) and this workstream's research/SUMMARY.md.

- Roadmap phase order (2026-07-24): addressing → pubsub namespacing → job isolation → bridge/gateway. Chosen over the milestone's originally-stated order (addressing → pubsub → bridge → job isolation) per research's Architecture/Stack recommendation — job isolation makes subnet isolation structurally real and the bridge's trust model depends on a demonstrably isolated subnet state to bridge from. Both PubSub-before-job-isolation and Addressing-first are hard dependencies, not preferences.
- This milestone is docs-only, one phase per requirement category (ADDR, PUBSUB, JOBC, BRDG) — 4 phases, no compression despite `granularity: coarse` config, since each category is a genuinely distinct design deliverable named explicitly in PROJECT.md's target-deliverables list.

### Pending Todos

None yet.

### Blockers/Concerns

- Research flags two open design forks the phase design docs must resolve explicitly, not leave implicit: (1) whether address derivation itself needs to change to fold in net_id.subnet_id, or whether tuple-keying downstream is sufficient (Phase 1); (2) gateway process architecture — two cooperating single-net processes vs. a refactored net-context parameter (Phase 4), forced by `net_id`'s process-global-singleton constraint.
- Pitfalls/architecture research is anchored to the `dev_childwallet` branch post-v2.4-merge; file/line references should be verified against current HEAD before each phase's design doc is finalized.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none — this is the first milestone for this workstream)* | | | |

## Session Continuity

Last session: 2026-07-25T01:44:43.140Z
Stopped at: Phase 1 context gathered
Resume file: .planning/workstreams/gnus-subnets/phases/01-subnet-addressing-scheme/01-CONTEXT.md

## Operator Next Steps

- Run `/gsd-plan-phase 1` to plan the Subnet Addressing Scheme design-doc phase.
