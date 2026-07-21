# Phase 5: Child Wallet Lifecycle States - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-21
**Phase:** 5-child-wallet-lifecycle-states
**Areas discussed:** Replace-Main scope, API shape for Detach/Revoke, SDK exposure timing, test coverage depth

---

## Replace-Main Scope (LIFE-03 inclusion)

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to a future phase | Phase 5 = Detach + Revoke only, matching roadmap goal text exactly | |
| Include it now | Add child-initiated main-replacement in this phase since the CRDT filter gate work (`supersedes_sequence`) is identical either way | ✓ |
| Let Claude decide | Claude scopes based on testability | |

**User's choice:** Include it now.
**Notes:** Rationale given at question time: implementing the `supersedes_sequence` fork-prevention gate for Detach but not Replace-Main would mean re-deriving the identical logic in a separate future phase for no isolation benefit.

---

## API Shape for Detach/Revoke

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated DetachChild + RevokeChild | New two-layer methods (TransactionManager + GeniusNode) mirroring RecoverFromChild's pattern | ✓ |
| Extend RegisterChild for detach, dedicated RevokeChild for revoke | Detach reuses RegisterChild machinery with new params; only Revoke is fully new | |
| Let Claude decide | Researcher/planner pick the shape | |

**User's choice:** Dedicated DetachChild + RevokeChild.
**Notes:** Consistent with D-62 (Phase 3, dedicated RecoverFromChild over overloading TransferFunds) and D-66 (Phase 4, dedicated GeniusSDKFundChild over reusing generic transfer) — this user has repeatedly chosen dedicated, discoverable, symmetric method names over reusing generic machinery.

---

## SDK Exposure Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Defer SDK wrappers (recommended) | Phase 5 stays at proto/consensus/CRDT/GeniusNode layer only; no GeniusSDKDetach/Revoke in this phase | ✓ |
| Include SDK wrappers now | Add GeniusSDK C API functions in this same phase | |
| Let Claude decide | Claude scopes based on phase size once research is done | |

**User's choice:** Defer SDK wrappers.
**Notes:** Mirrors the Phase 3 (consensus gate) → Phase 4 (SDK wrapper) precedent exactly.

---

## Test Coverage Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full adversarial coverage (recommended) | Fork-detection, replay, unauthorized-revoke, re-registration-after-detach/revoke — all as automated E2E tests, mirroring Phase 3's REGR pattern | ✓ |
| Happy-path only | Just prove detach and revoke each work end-to-end; adversarial tests deferred | |
| Let Claude decide | Researcher/planner size the suite once implementation shape is locked | |

**User's choice:** Full adversarial coverage.
**Notes:** Matches Phase 3's rigor (REGR-01/02/03: 24/24 passing regression tests against the real consensus pipeline).

---

## Claude's Discretion

- Exact requirement ID wording/numbering for LIFE-01 through LIFE-04 in `.planning/REQUIREMENTS.md` conventions.
- Whether Replace-Main gets its own dedicated method or shares construction machinery with Detach (both are child-signed `RegistrationTx` updates with `supersedes_sequence`).
- Precise code shape of the `CheckParentChildAuthority` extension's new `"revoke"` branch.
- Whether the adversarial regression tests extend the existing TransactionManager/registration test file(s) or need a new file (Phase 3's D-65 precedent favors extending existing files).

## Deferred Ideas

- GeniusSDK C API wrappers for Detach/Revoke/Replace-Main — future phase (mirrors Phase 4's relationship to Phase 3).
- Reward policy resolution (RWD-01/02/03) — separate concern from lifecycle transitions, not scoped here.
- GeniusWallet Flutter UI wiring for lifecycle actions — already deferred at the project level (UI-01).
- Discovery/monitoring dashboard showing lifecycle status — already deferred at the project level (MON-01/02).
