# Phase 18: Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-19
**Phase:** 18 - Role Downgrade, Collectibility Policy & GC Walk-Gap Exemption
**Areas discussed:** Walk-gap exemption form, Downgrade interlock strength, Downgrade E2E shape, Policy record shape

---

## Walk-gap exemption form

| Option | Description | Selected |
|--------|-------------|----------|
| Ship code + counter-test | GC's walk-gap abort site consults /prune/blk evidence; red-first counter-test fault-injects the v2 state (cold deleted + evidence present) to prove the walk survives. Strongest enforcement: v2 collection cannot ship without the exemption already tested | ✓ |
| Design-record only | Policy record specifies exemption semantics; no production code — matches ROADMAP letter and research lean; risk: documented, not enforced | |
| Tripwire test only | No production code; a test simulates the v2 state and asserts today's abort, marked/skipped with a pointer to the record | |

**User's choice:** Ship code + counter-test
**Notes:** —

### Predicate home

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 15 predicate | GC walk-gap site routes through the same role-aware GlobalDB evidence predicate; 'pruned' ⇒ expected-absent; extends Phase 15 D-04 source-consistency; no third builder | ✓ |
| GC-local consult | ColdStorageManager consults /prune/blk directly; smaller blast radius but a second evidence surface kept consistent by test, not construction | |
| You decide | Research/planner rule after reading the actual gap site and predicate surface | |

**User's choice:** Phase 15 predicate
**Notes:** —

### Counter-test tier

| Option | Description | Selected |
|--------|-------------|----------|
| Hermetic Tier-1 + dev-gated live | Deterministic Tier-1 leg with hermetic fake cold allowing test-side deletion + seeded evidence via the sanctioned marker writer; dev-gated live leg on a real stack (Phase 16 D-11 precedent) | ✓ |
| Hermetic only | The v2 state is fully modelable with the fake; no live leg since collection isn't a v1.2 product behavior | |
| Both + out-of-band delete | Hermetic leg plus dev-gated live leg deleting a real s3d/MinIO object out-of-band (mc client) | |

**User's choice:** Hermetic Tier-1 + dev-gated live
**Notes:** —

### Exempt observability

| Option | Description | Selected |
|--------|-------------|----------|
| Counted-continue | Dedicated walk-exempted counter in GC pass stats, per-pass INFO summary (Phase 14 D-03 / Phase 16 D-10 never-healthy-by-omission precedent) | ✓ |
| Silent-continue | Pure predicate consult, no new counter; add the counter when v2 makes it operationally meaningful | |
| You decide | Research/planner rule alongside the gap-site code | |

**User's choice:** Counted-continue
**Notes:** —

## Downgrade interlock strength

| Option | Description | Selected |
|--------|-------------|----------|
| Hard gate + ack key | New deliberate config key must be set before a detected downgrade arms pruning; mechanically enforced operator-initiated/checklist-gated; small singular config surface distinct from D-04's gate-knob concern | ✓ |
| WARN-only | Loud WARN on detecting the downgrade pattern; no new config surface; only as strong as log review discipline | |
| You decide | Research/planner decide strength after reading how the prune timer arms | |

**User's choice:** Hard gate + ack key
**Notes:** —

### Fire behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Start, pruning disarmed | Node serves normally; pruner disarmed with loud WARN until acknowledged; fail-toward-under-erase (degrades to keeps-everything) | ✓ |
| Refuse to start | Startup aborts hard on unacknowledged downgrade; loudest gate but a config mistake bricks the node | |
| Proceed fully | WARN only (the WARN-only strength option) | |

**User's choice:** Start, pruning disarmed
**Notes:** —

### Detection

| Option | Description | Selected |
|--------|-------------|----------|
| Persisted role fingerprint | Small persisted meta record of last-run role/config; deterministic; cleanly distinguishes birth-tiered-light from downgraded-archive; one tiny new state write | ✓ |
| DB heuristic | No new state: light+pruning+cold on a DB with Durable records but no /prune/ markers; false-positives on a birth-tiered-light's first cycle; indistinguishable after markers exist | |
| You decide | Research reads the prune-timer arming and existing plumbing, then rules | |

**User's choice:** Persisted role fingerprint
**Notes:** —

### Checklist home

| Option | Description | Selected |
|--------|-------------|----------|
| In the policy record | Checklist is a section of the Phase 18 rulings doc; ack key docs reference it by path; one canonical home | ✓ |
| Standalone runbook | Separate operator-facing doc optimized for consumption rather than provenance | |
| You decide | Decided alongside the policy record shape | |

**User's choice:** In the policy record
**Notes:** —

## Downgrade E2E shape

| Option | Description | Selected |
|--------|-------------|----------|
| 2-node: light + archive peer | Node A downgrades and prunes; history fetched from archive peer B — SC2's letter literally; EraseNodeCollection precedent; flakiest test class | |
| Single-node restart | One node restarted as light (same DBs + cold, node_type flipped); covers SC3/SC4 timeline | ✓ |
| You decide | Research weighs SC2's cross-node letter against flaky-class cost | |

**User's choice:** Single-node restart
**Notes:** Consequence surfaced and resolved via the SC2-letter question below.

### SC2 letter (consequence of single-node choice)

| Option | Description | Selected |
|--------|-------------|----------|
| Compositional coverage | E2E proves the downgraded node's half; cross-node fetchability rides on landed Phase 15 SERVE-04 failover semantics cited as evidence; interpretation recorded in CONTEXT.md | ✓ |
| 2-node in dev-gated leg | Tier-1 stays single-node; dev-gated live leg adds the second archive node for a literal one-time cross-node proof | |
| Defer to Phase 19 | Downgrade cell added to Phase 19's fault-race matrix; explicit deferral recorded | |

**User's choice:** Compositional coverage
**Notes:** —

### E2E tier

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid: Tier-1 + dev-gated | Tier-1 hermetic single-node re-open timeline (fake cold, deterministic mechanics, interlock fire/ack legs); dev-gated live leg on real S3 | ✓ |
| All hermetic | Including faked peer serving — maximally CI-safe, cross-node claim rides a fake | |
| All dev-gated | Full E2E only as dev-gated live; weakest CI protection | |

**User's choice:** Hybrid: Tier-1 + dev-gated
**Notes:** —

### Timeline depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full t0→t3 | Through retention-eviction of local cold copies with remote-backed serving + walk health (exemption exercised in-band); retention-age manipulation deterministic hermetically | ✓ |
| Stop at t2 | Markers + refusal + interlock only; t3 steady state covered by existing Phase 11 GC/retention suites | |

**User's choice:** Full t0→t3
**Notes:** —

## Policy record shape

| Option | Description | Selected |
|--------|-------------|----------|
| One rulings doc | notes/18-*.md carries two-halves policy, exemption record, operator checklist, tiered-node model writeup, downgrade timeline docs — one citable home in the 16/17 chain | ✓ |
| Ruling + model writeup split | Policy/exemption/checklist in notes/; tiered-node model as separate explanatory doc | |
| You decide | Planner decides alongside the STATE.md one-liner and cross-references | |

**User's choice:** One rulings doc
**Notes:** —

### V2 ask depth

| Option | Description | Selected |
|--------|-------------|----------|
| Sketch the v2 contract | What Remove must require (evidence-driven, node-local, per-CID), why (two-halves + poisoned-GC-triangle), preconditions (exemption shipped, DisposedDurable lifecycle); REQUIREMENTS Future cross-referenced | ✓ |
| Pointer-depth only | One paragraph at REQUIREMENTS-Future depth; keeps the record strictly v1.2-scoped | |

**User's choice:** Sketch the v2 contract
**Notes:** —

## The Agent's Discretion

- Ack-key naming/shape and config-file home
- Fingerprint record mechanics (keyspace, fingerprint contents, write timing, test seams)
- Exemption consult seam mechanics and predicate exposure to the GC pass
- Counter-test fixture shape (fake-cold deletion modeling; sanctioned marker writer seeding)
- Walk-exempted counter naming + INFO format
- E2E restart mechanics (in-process re-open vs process restart)
- SC3's no-re-drain observable assertion shape
- Test file homes (sibling-file precedent)
- Exact notes/18-*.md filename
- Tier-1 floor/registration details for new suites
- Anchor re-location strategy against the post-Phase-17 line

## Deferred Ideas

None — discussion stayed within phase scope.
