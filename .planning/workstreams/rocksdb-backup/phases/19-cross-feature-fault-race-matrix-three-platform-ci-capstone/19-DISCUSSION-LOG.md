# Phase 19: Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-19
**Phase:** 19-Cross-Feature Fault-Race Matrix & Three-Platform CI Capstone
**Areas discussed:** Matrix shape & case grammar, Fault induction & topology, CI lane mechanics, Portability list & evidence

---

## Area selection

All four presented gray areas were selected for discussion (multi-select).

## Matrix shape & case grammar

| Option | Description | Selected |
|--------|-------------|----------|
| Curated boundary list | Named cases at specific phase-boundary failure points, each asserting its impossibility; matches SC1's "each phase boundary" letter | ✓ |
| Formal 3-axis product | Systematic {erase} × {serve} × {recovery} product with a generic invariant harness; exhaustive but combinatorially large, unkeepable on 3 platforms | |
| Hybrid product + curated | erase × recovery as a small systematic product, serve arms curated | |

**User's choice:** Curated boundary list

| Option | Description | Selected |
|--------|-------------|----------|
| New sibling suite | cold_cross_feature_fault_race_test.cpp family; v1.1's 13 cases frozen as baseline; own Tier-1 label | ✓ |
| Extend in place | Append to the existing v1.1 suite file; churns the frozen SC4 baseline | |

**User's choice:** New sibling suite

| Option | Description | Selected |
|--------|-------------|----------|
| ~8–12 new cases | Every boundary: deterministic seam leg + barrier leg where true concurrency is the claim (Phase 16 D-06 per case) | ✓ |
| Minimal delta ~5–6 | Only uncovered boundaries; cite Phase 14/15/16 suites compositionally | |
| Researcher proposes | Boundary inventory first, then case list | |

**User's choice:** ~8–12 new cases

| Option | Description | Selected |
|--------|-------------|----------|
| Tri-hazard everywhere | Every case asserts all three impossibilities; strongest but diluted failure messages | |
| Hazard-mapped per case | Each case designates its primary hazard; matrix table maps coverage across the suite | ✓ |

**User's choice:** Hazard-mapped per case

## Fault induction & topology

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse + extend kit | v1.1 kit + Phase 14/15/18 seams + tri-state fakes; add only missing serve-side seams; zero new deps | ✓ |
| Fresh harness | Purpose-built cross-feature injection surface; risks parallel-kit drift | |

**User's choice:** Reuse + extend kit

| Option | Description | Selected |
|--------|-------------|----------|
| Hermetic-only + citations | All deterministic; peer-failover covered compositionally via citations | |
| Full-wire failover legs | Two-GlobalDB real-pubsub legs for refusal→failover cases; flakiest class | |
| Hybrid: one full-wire leg | Hermetic everywhere + ONE instrumented full-wire leg; Tier-1 if it holds green, else dev-gated | ✓ |

**User's choice:** Hybrid: one full-wire leg

| Option | Description | Selected |
|--------|-------------|----------|
| All three serve surfaces | Cold-fetch + refusal classification + re-warm/LRU | |
| Serving core only | Cold-fetch consult + refusal classification; re-warm/LRU cited from v1.1 suites | ✓ |

**User's choice:** Serving core only

| Option | Description | Selected |
|--------|-------------|----------|
| Walk boundaries + concurrency delta | Forced walk against induced evidence states; Phase 15 semantics re-proven only under concurrent erase | ✓ |
| Full re-proof | Re-prove all Phase 15 walk semantics from scratch inside the matrix | |

**User's choice:** Walk boundaries + concurrency delta

## CI lane mechanics

| Option | Description | Selected |
|--------|-------------|----------|
| Dispatch evidence only | build-release-tags runs with run_tests+cold_storage; run links as evidence | |
| Permanent 3-platform cold-ON Tier-1 | Extend the existing OSX ON-leg pattern to all three desktop platforms in cmake.yml + build-release-tags | ✓ |
| Tier-1 lane + final dispatch | Permanent lane (hermetic only) + one final dispatch per platform as the recorded evidence run | |

**User's choice:** Permanent 3-platform cold-ON Tier-1

| Option | Description | Selected |
|--------|-------------|----------|
| Hermetic cold only | InMemoryS3* fakes, fresh-clone safe; MinIO stays dev-gated/Tier-3 | ✓ |
| Hermetic + Linux MinIO leg | Real S3 wire on one Linux leg; heavier, new lane maintenance | |

**User's choice:** Hermetic cold only

| Option | Description | Selected |
|--------|-------------|----------|
| Full cold Tier-1 contract | All v1.2 suites (14-19) green on all three platforms | ✓ |
| Walk suites only | Phase 15 walk + Phase 19 matrix only; faster but weaker capstone claim | |

**User's choice:** Full cold Tier-1 contract

| Option | Description | Selected |
|--------|-------------|----------|
| Documented quarantine table | Pre-agreed exclusions/env-knobs for known NON-cold flakes, recorded with history; cold failures never quarantined | ✓ |
| Zero exclusions | Everything green, fix all flakes in scope | |
| Zero exclusions cold-only | Cold suites clean; non-cold quarantined per table | |

**User's choice:** Documented quarantine table

## Portability list & evidence

| Option | Description | Selected |
|--------|-------------|----------|
| Workstream notes/ chain | One notes/19-*.md: portability list + quarantine table + run evidence | ✓ |
| Repo-side doc | SuperGenius-side doc next to the lanes; breaks the rulings-chain discipline | |
| Notes + repo pointer | Canonical notes/19 + short repo-side pointer | |

**User's choice:** Workstream notes/ chain

| Option | Description | Selected |
|--------|-------------|----------|
| The four named items | Exactly SC3's letter (CloudflareWARP, base paths, poll predicates, filter grammar) | |
| Full lane runbook | Four items + env vars, cache flags, parallel caps, crash-report capture, dispatch toggles, exclusion pointers | ✓ |

**User's choice:** Full lane runbook

| Option | Description | Selected |
|--------|-------------|----------|
| Run links only | Green dispatch run links + parameters in the evidence doc | |
| Run links + fresh-clone checklist | Also refresh/extend the v1.1 12-FRESH-CLONE-CHECKLIST.md | ✓ |

**User's choice:** Run links + fresh-clone checklist

| Option | Description | Selected |
|--------|-------------|----------|
| One green per platform | One recorded green dispatch closes the record; permanent lane is the ongoing guard | ✓ |
| Two consecutive greens | Guards against first-green masking tart-VM timing flakes | |

**User's choice:** One green per platform

---

## the agent's Discretion

- Exact boundary inventory + named-case list (within the 8–12 budget)
- New serve-side seam placement/naming (siblings of the interrupt-seam family)
- Sibling suite filename(s), test registration home, Tier-1 label name
- Red-first proof mechanics per race case (fault-injected bad state per Phase 18 D-01)
- Full-wire leg promotion criteria (green-dispatch count for Tier-1 retention)
- cmake.yml / build-release-tags.yml edit shape (per-platform lane expression)
- Quarantine-table initial contents + first-occurrence run IDs
- notes/19-* exact filename; fresh-clone checklist refresh shape
- Env-knob naming for new nondeterministic tests
- Anchor re-location strategy on the final post-verification line

## Deferred Ideas

None — discussion stayed within phase scope. macOS teardown debt / multi_node smoke flake referenced only as quarantine-table entries (fixes remain SuperGenius backlog per the v1.1 round-14 ruling).
