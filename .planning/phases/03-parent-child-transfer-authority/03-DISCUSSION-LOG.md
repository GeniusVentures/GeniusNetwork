# Phase 3: Parent-Child Transfer Authority - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-20
**Phase:** 3-Parent-Child Transfer Authority
**Areas discussed:** Recovery authorization mechanism, GeniusNode/TransactionManager API shape, Certified-status implementation, Gate return type, Regression test scope/placement

---

## Recovery Authorization Mechanism

Surfaced as a critical, phase-blocking gap found while verifying `docs/02-consensus-parent-child-authority.md` §7 against the current codebase: the design doc's own described mechanism for CONS-02 (main signs a tx with `src=child_addr`) cannot pass current signature verification (`CheckSignature`, `ValidateWitness`) since both check the signature against `tx->GetSrcAddress()`'s own keypair, and main does not have the child's private key.

| Option | Description | Selected |
|--------|-------------|----------|
| Escrow-lock child funds for recovery | Route recoverable child funds through the existing escrow-lock/delegated_escrow_spend mechanism | |
| Amend GeniusInputValidator.cpp after all | Accept a narrow addition to ValidateWitness for a certified-registration delegated-spend exception | ✓ (closest match to user's answer) |
| Child must cooperate (co-sign or self-initiate) | Reframe CONS-02 as main-requested, child-executed | |
| Not sure — flag for research | Hand to phase researcher as open question | |

**User's choice (free text):** "Main signs transaction, consensus accepts because crdt records indicate that it is a child wallet."
**Notes:** This locks the direction (CRDT-derived authority, not cryptographic delegation) but leaves the exact code-level mechanism for extending signature acceptance to research/planning. Flagged explicitly in CONTEXT.md that this puts the original design doc's "GeniusInputValidator.cpp untouched" claim (D-22/D-23/REGR-03) in tension with the locked decision — needs a narrow, CRDT-gated extension rather than a blanket relaxation.

---

## GeniusNode/TransactionManager API Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse TransferFunds for funding, add RecoverFromChild only | CONS-01 needs zero new code; CONS-02 gets one new method | ✓ |
| Add named wrappers for both directions | FundChild + RecoverFromChild as a symmetric pair | |
| Single method with a direction parameter | One TransferWithChild call covering both directions | |

**User's choice:** Reuse TransferFunds for funding, add RecoverFromChild only.
**Notes:** Matches CONS-01's own framing in the design doc (an unrestricted ordinary transfer) — no new funding call needed.

---

## Certified-Status Implementation

| Option | Description | Selected |
|--------|-------------|----------|
| Look up existing tx_processed_m CONFIRMED state | Reuses the same mechanism every other tx type already relies on | ✓ |
| Treat any reg/ CRDT hit as certified | Simplify — skip separate certification tracking | |
| Not sure — let research resolve it | Flag for phase researcher | |

**User's choice:** Look up existing tx_processed_m CONFIRMED state.
**Notes:** Exact keying/queryability of tx_processed_m for a registration's hash flagged as a research item — direction is locked, precise lookup call is not.

---

## Gate Return Type

| Option | Description | Selected |
|--------|-------------|----------|
| Simple: Approve/Reject only | Not-yet-synced reg/ record treated as "not found" → Approve() | ✓ |
| Full three-state with Pending | ValidationResult::Pending(deps, retry) per design doc | |

**User's choice:** Simple: Approve/Reject only.
**Notes:** Matches how every other gate in the pipeline behaves today; avoids new retry-queue plumbing.

---

## Regression Test Scope/Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Extend existing TransactionManager test file(s) | Add new TEST_F cases alongside existing consensus tests | ✓ |
| New dedicated test file | e.g. parent_child_authority_test.cpp | |

**User's choice:** Extend existing TransactionManager test file(s).

---

## Claude's Discretion

- Exact method/parameter naming for `RecoverFromChild` beyond the locked signature shape (timeout-overload pair, mirroring `TransferFunds`).
- Precise code shape of the signature-verification extension needed for D-60 — researcher/planner design this, informed by the existing `delegated_escrow_spend` pattern.

## Deferred Ideas

- GeniusSDK C API exposure of both transfer directions — Phase 4 (already next in roadmap, not new).
- Transfer amount limits/policy, GeniusWallet Flutter UI wiring — out of scope for v2.3 entirely (already documented in PROJECT.md/REQUIREMENTS.md, not new).
