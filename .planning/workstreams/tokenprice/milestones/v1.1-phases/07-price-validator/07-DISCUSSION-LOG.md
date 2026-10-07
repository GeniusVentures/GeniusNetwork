# Phase 7: Price Validator - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-06
**Phase:** 7-Price Validator
**Areas discussed:** Threshold defaults, No-coverage policy, Legacy-task policy, Result shape & reason taxonomy

---

## Threshold defaults

| Option | Description | Selected |
|--------|-------------|----------|
| 10% | Absorbs cross-node fetch variance for a volatile low-cap token; still catches deliberate gaming | ✓ |
| 5% | Tightest anti-gaming; OQ2 suggestion but more false rejects on real spikes | |
| 15–20% | Nearly never false-rejects; weaker anti-gaming | |
| Two-sided asymmetry | Separate up/down values (more knobs to tune) | |

| Option | Description | Selected |
|--------|-------------|----------|
| Asymmetric [T − (300s + skew), T + skew] | Exactly D-06-03; minimal dead band, smallest cherry-picking surface | ✓ |
| Symmetric ±10 min | OQ2 suggestion; includes prices after the escrow that couldn't have been used | |
| Asymmetric with +60s margin | Covers one retry cycle for slow poster nodes | |

| Option | Description | Selected |
|--------|-------------|----------|
| Skew 30s, max age 10 min | Skew within one freshness band; 10-min-old escrow beyond any quote TTL | ✓ |
| Skew 60s, max age 5 min | Stricter: T older than the stale-but-usable horizon rejects immediately | |
| Skew 120s, max age 30 min | Lenient for globally distributed nodes with slow task propagation | |

| Option | Description | Selected |
|--------|-------------|----------|
| Struct + env-var overrides | PriceValidatorConfig defaults in code; SGNS_PRICEVAL_* env overrides, Phase 4 precedent | ✓ |
| Struct defaults only | Configurable only by code/tests; no runtime knobs | |
| sgns_config.json keys | Node-operator friendly but touches config plumbing Phase 4 avoided | |

**User's choice:** 10% tolerance; asymmetric TTL+skew window; 30s/10min; struct + env overrides.

## No-coverage policy

| Option | Description | Selected |
|--------|-------------|----------|
| Reject with NO_COVERAGE | Deterministic, fail-closed; typed reason distinguishes unverifiable from gamed | ✓ |
| Fetch-and-widen once | More permissive but timing-dependent (breaks determinism); fresh quote isn't from T anyway | |
| Defer | Honest but a third state the Phase 8 consensus hook must handle | |

| Option | Description | Selected |
|--------|-------------|----------|
| Background self-heal fetch | Reject stays the verdict; node fetches so subsequent tasks pass; recovers within one fetch cycle | ✓ |
| No self-heal in validator | Cold nodes reject until normal polling covers them; validator stays pure | |
| Self-heal + next-validation evidence | Fetch is evidence only for the next validation, no same-call retry | |

| Option | Description | Selected |
|--------|-------------|----------|
| count >= 1 is coverage | Single observation is evidence; >10% move in 5 min is rare; rejecting is worse | ✓ |
| count >= 2 required | Two fetches make a meaningful [min,max]; count==1 also NO_COVERAGE | |
| Weighted widening | count==1 doubles tolerance instead of rejecting | |

**User's choice:** Reject NO_COVERAGE + background self-heal; count >= 1 is coverage.

## Legacy-task policy

| Option | Description | Selected |
|--------|-------------|----------|
| Reject with LEGACY_NO_PRICE | Fail-closed from day one; no grace flag to remove; no gaming window | ✓ |
| Accept-with-warning grace | Gentler rollout but needs a flag + later removal; grace keeps the hole open | |
| Version-gated | Reject only when a version marker says the field should exist; needs a new wire field | |

| Option | Description | Selected |
|--------|-------------|----------|
| Hard cutover | Network is young; posters and validators ship together in the node release | ✓ |
| Log-only mode first | Validator logs rejections for N days before Phase 8 enforces (needs a mode knob) | |

**User's choice:** Reject LEGACY_NO_PRICE; hard cutover.

## Result shape & reason taxonomy

| Option | Description | Selected |
|--------|-------------|----------|
| struct + enum + diagnostics | Reason enum for control flow; band/observed stats in the struct for logging/tests | ✓ |
| outcome::result error codes | Codebase idiom, but accept is the common case; loses diagnostics | |
| enum-only | Minimal; forces Phase 8 to recompute the band to log why | |

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed fail-fast order | legacy → timestamp → cost binding → band; cheapest first; deterministic single reason | ✓ |
| Most-specific-first | Cost binding before timestamp; surfaces honest-price/lowered-escrow distinctly | |
| Bitmask accumulation | Maximal diagnostics but heavier API for Phase 8 | |

| Option | Description | Selected |
|--------|-------------|----------|
| Free function in src/coinprices/ | PriceValidationInput struct; depends only on TokenAmount + stats; zero-mock hermetic tests | ✓ |
| LocalPriceManager method | Convenient history access but couples pure logic to a threaded component | |
| New src/pricevalidation/ module | Maximal isolation but a whole module for one pure function | |

**User's choice:** struct with diagnostics; fixed fail-fast order; free function in src/coinprices/.

---

## the agent's Discretion

File names, Reason enum spelling, diagnostics field set, env-var key names beyond the SGNS_PRICEVAL_ prefix, test file organization under test/src/coinprices/, and whether the self-heal helper is a free function or Phase 8 caller code.

## Deferred Ideas

- Poster trust/reputation and consensus-applied penalties (later milestone; carried from Phase 6).
- Retune tolerance/window defaults from real GNUS volatility telemetry once mainnet data exists.
- Reviewed-not-folded todo: "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (keyword-only match, unrelated domain).
