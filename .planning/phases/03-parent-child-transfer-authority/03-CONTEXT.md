# Phase 3: Parent-Child Transfer Authority - Context

**Gathered:** 2026-07-20
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers a new `CheckParentChildAuthority` consensus gate enabling two directions of main↔child fund movement:
1. **CONS-01 (main→child fund):** an ordinary main-signed `"transfer"` tx to a registered child, where the `reg/` check is a consistency validation, not access control.
2. **CONS-02 (main-recover-from-child):** a main-signed `"transfer"` tx moving funds from a registered child back to its own registered main address, destination-restricted (D-21).

Plus regression coverage (REGR-01/02/03) proving every existing child-signed path (child→arbitrary, child→main, child→dev via `PayDev`, child-cannot-spend-main) is unaffected by the new gate.

GeniusSDK C API exposure of both directions is **Phase 4** — out of scope here. New tx types, new proto messages, transfer amount limits/policy, and GeniusWallet Flutter UI wiring are out of scope for the whole v2.3 milestone.

</domain>

<decisions>
## Implementation Decisions

### Recovery Authorization Mechanism (the central open question this phase must resolve)
- **D-60 (supersedes the literal CONS-02 mechanism in `docs/02-consensus-parent-child-authority.md` §7):** Main signs the recovery transaction directly (declaring `src = child_addr`, `dst = main_addr`), and consensus accepts it because the CRDT `reg/{child_addr}` record certifies the parent-child relationship — authority is derived from the CRDT registration, not from cryptographic delegation of the child's key.
- **Why this needed resolving:** Verified against current code (`GeniusTransaction::CheckSignature` at `GeniusTransaction.cpp:72-81`, `GeniusAccount::VerifySignature` at `GeniusAccount.cpp:790-815`, `GeniusInputValidator::ValidateWitness` per-input check at `GeniusInputValidator.cpp:357-361` and owner check at `:419-432`) — all three currently verify a signature strictly against `tx->GetSrcAddress()`'s own public key. If `src = child_addr`, a signature produced with the main's private key will NOT verify against the child's address using today's code. The design doc's own §7 trace hits this exact contradiction mid-derivation and hand-waves past it ("no special flag needed") without resolving it.
- **Consequence downstream agents MUST address:** Making D-60 work necessarily means `CheckTransactionAuthorization` (`TransactionManager.cpp:4066-4076`, currently `tx.CheckSignature() || tx.CheckDAGSignatureLegacy()`) and/or `ValidateWitness`'s per-input signature check (`GeniusInputValidator.cpp:357-366`) must be extended to accept a signature produced by the certified registered main's key when the declared `src` is a certified registered child. **This is in direct tension with CONS-06/REGR-03's original wording that `GeniusInputValidator.cpp` stays untouched** — the researcher/planner must design the narrowest possible extension (e.g., an alternate verification branch keyed off a certified `reg/` lookup, mirroring the existing narrow `delegated_escrow_spend` exception pattern already in `ValidateWitness`) and explicitly document where the "untouched" claim from the original design doc no longer holds.
- Regardless of mechanism, D-21 (hard destination restriction: `dst` must equal the certified `reg/` record's `main_address`) and D-26 (registration must be certified before authority applies) still hold as designed.

### GeniusNode / TransactionManager API Shape
- **D-61:** CONS-01 (funding) needs **no new call** — it's an ordinary transfer via the existing `GeniusNode::TransferFunds` / `TransactionManager::TransferFunds` (`GeniusNode.cpp:2258-2283`). The new `CheckParentChildAuthority` gate's `reg/` lookup for funding is a consistency validation only; it doesn't change the call path.
- **D-62:** CONS-02 (recovery) gets exactly one new method: `RecoverFromChild(child_address, amount, token_id)` at both the `TransactionManager` and `GeniusNode` layers (mirroring the existing two-layer `TransferFunds`/`RegisterChild` convention). This is the only new transfer-construction machinery this phase adds — it must build a tx with `src = child_addr`, `dst = main's own address`, signed with the main's own key per D-60.

### Certified-Status Lookup (D-26 enforcement)
- **D-63:** The gate resolves certification by looking up the registration's existing `tx_processed_m` `CONFIRMED` state (the same mechanism every other tx type already uses for consensus-certification tracking) — no new storage or CRDT field. `GetRegistrationsForMain`/`RegistrationDiscoveryEntry` (`TransactionManager.hpp:45-51`, `.cpp:4983-5031`) currently expose no certified flag at all; this phase's gate does its own lookup independent of that discovery path. **Flagged for research:** the exact keying/queryability of `tx_processed_m` for a registration's hash needs confirming during research/planning — the mechanism is directionally locked, the precise lookup call is not.

### Gate Return Type
- **D-64:** `CheckParentChildAuthority` returns **Approve/Reject only** — no `Pending` retry-queue state. A `reg/` record that hasn't synced locally yet is treated as "not found" → `Approve()` (ordinary tx, no delegated authority claimed applies). This simplifies the design-doc's original three-state `ValidationResult::Pending(deps, retry)` proposal down to match how every other existing gate in `ValidateTransactionForConsensus` behaves.

### Regression Test Placement
- **D-65:** REGR-01/02/03 tests extend the **existing TransactionManager test file(s)** (alongside existing transfer/registration consensus tests) rather than a new dedicated test file — keeps all consensus-pipeline coverage in one place.

### Claude's Discretion
- Exact method/parameter naming details for `RecoverFromChild` beyond the locked signature shape (e.g., whether it needs a timeout-overload pair mirroring `TransferFunds`'s two overloads) — planner follows the existing `TransferFunds` two-overload convention (fire-and-return-tx-id vs wait-for-finalized).
- The precise code shape of the signature-verification extension in `CheckTransactionAuthorization`/`ValidateWitness` needed to make D-60 work — researcher/planner design this, informed by the existing `delegated_escrow_spend` narrow-exception pattern as the closest existing precedent.
- Insertion point confirmation: gate slots between `CheckTransactionAuthorization` and `CheckTransactionTimestamp` at `TransactionManager.cpp:3988-3997` (verified current line numbers; logic identical to design doc's D-19, only line numbers shifted since v2.0-v2.2 added code).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design doc (primary spec for this phase — read first)
- `docs/02-consensus-parent-child-authority.md` — Full CONS-01–06 rule specifications, gate insertion point (D-19), rule dispatch logic (D-20), destination restriction (D-21), child-cannot-spend-main invariant (D-22), orthogonality claim (D-23). **§7's own recovery-mechanism trace is where the D-60 contradiction was found — read it critically, not as settled fact.** §6 (RegistrationTx validation gap) and §8 (traceability matrix) remain accurate.

### Planning docs
- `.planning/PROJECT.md` — Locked v2.3 milestone scope, security constraint ("child signs its own spends, main cannot spend on the child's behalf" — now qualified by D-60: main's signature is accepted via CRDT-certified delegation, not by possessing the child's key), Key Decisions table.
- `.planning/REQUIREMENTS.md` — CONS-01, CONS-02, CONS-06, REGR-01, REGR-02, REGR-03 (this phase's 6 requirements, of 9 total in v2.3).
- `.planning/ROADMAP.md` §Phase 3 — goal + 5 success criteria this context must satisfy.
- `.planning/STATE.md` — Current milestone position, prior decisions log.

### Prior phase context (locked decisions this phase builds on)
- `.planning/milestones/v1.0-phases/02-crdt-persistence-pubsub-consensus-authority/02-CONTEXT.md` — D-19 through D-26: gate insertion point, rule dispatch, destination restriction, child-cannot-spend-main invariant, orthogonality, certified-status two-tier model. This is where CONS-01–06 were originally scoped and designed.
- `.planning/milestones/v2.0-phases/04-registration-proto-transaction/04-CONTEXT.md` — RegistrationTx schema, `reg/{child_addr}` CRDT storage path, `FilterRegistration` filter (Phase 4 minimal, Phase 5 full — now fully implemented per code scout below).

### Code anchor points (verified against current code, 2026-07-20)
- `SuperGenius/src/account/TransactionManager.cpp:3966-4033` — `ValidateTransactionForConsensus`, current 6-gate pipeline; gate insertion point at line 3988-3997 (between `CheckTransactionAuthorization` and `CheckTransactionTimestamp`).
- `SuperGenius/src/account/TransactionManager.cpp:4066-4076` — `CheckTransactionAuthorization` (signature-only today; `tx.CheckSignature() || tx.CheckDAGSignatureLegacy()`).
- `SuperGenius/src/account/TransactionManager.hpp:45-51` — `RegistrationDiscoveryEntry` struct (no certified-status field today).
- `SuperGenius/src/account/TransactionManager.cpp:4983-5031` — `GetRegistrationsForMain` (reads `reg/` CRDT directly, no certification check).
- `SuperGenius/src/account/TransactionManager.cpp:2258-2283` (GeniusNode.cpp) — existing `TransferFunds` two-overload pattern to mirror for `RecoverFromChild`.
- `SuperGenius/src/account/GeniusTransaction.cpp:59-96` — `MakeSignature` (signs with the calling account's own key), `CheckSignature` (verifies against `dag_st.source_addr()` as literal pubkey), `CheckDAGSignatureLegacy`.
- `SuperGenius/src/account/GeniusAccount.cpp:790-815` — `VerifySignature` (unhexes `address` directly as the secp256k1 public key — confirms signature must match the declared address's actual keypair).
- `SuperGenius/src/account/GeniusInputValidator.cpp:357-366` — per-input witness signature check (verified against `tx->GetSrcAddress()`).
- `SuperGenius/src/account/GeniusInputValidator.cpp:419-432` — `payload_owner` vs `src_address` check + the existing `delegated_escrow_spend` narrow exception (the closest existing precedent for how a D-60-compliant extension might be shaped).
- `SuperGenius/src/account/TransactionManager.cpp:222-315` — existing `reg/` element filter registration (`FilterRegistration` pattern, fully implemented — not a Phase 3 concern, confirmed already done).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GeniusNode::TransferFunds` (two overloads: fire-and-return-tx-id, and wait-for-finalized-with-timeout) — CONS-01 funding needs zero new code, just calls this directly with the child's address as destination.
- `TransactionManager::GetRegistrationsForMain` / `RegistrationDiscoveryEntry` — existing pattern for reading `reg/` CRDT records; the new gate needs an equivalent single-child lookup (`reg/{child_addr}` → linked main + certification), not the full-scan-for-main variant.
- The existing `delegated_escrow_spend` narrow-exception pattern in `ValidateWitness` (`GeniusInputValidator.cpp:421-424`) — the closest existing precedent for how a second, CRDT-gated signature-acceptance path could be shaped without a blanket relaxation of ownership checks.
- `tx_processed_m` CONFIRMED-state tracking — already used by every other tx type for consensus-certification; the gate reuses this instead of inventing new storage.

### Established Patterns
- Every new consensus-authority tx type reuses `"transfer"` — no new tx type or proto message needed (D-20, unchanged).
- Two-layer method convention: `TransactionManager::X()` + thin `GeniusNode::X()` wrapper (see `TransferFunds`, `RegisterChild`) — `RecoverFromChild` follows this exactly.
- `ValidateTransactionForConsensus`'s gate-list pattern: each gate is a private const method called in sequence, logging entry/failure identically — `CheckParentChildAuthority` follows the same logging/error-message shape as its neighbors.

### Integration Points
- `TransactionManager::ValidateTransactionForConsensus` (`TransactionManager.cpp:3988`, between line 3988 and 3997) — insert the new gate call here.
- `TransactionManager.hpp` — add `CheckParentChildAuthority` declaration near `CheckTransactionAuthorization`/`CheckTransactionTimestamp` declarations.
- `TransactionManager::CheckTransactionAuthorization` and/or `GeniusInputValidator::ValidateWitness` — likely need the D-60 signature-acceptance extension (exact shape left to research/planning).
- New `TransactionManager::RecoverFromChild` + `GeniusNode::RecoverFromChild` — new methods, placed near existing `TransferFunds`/`RegisterChild` methods in both files.

### Critical Gap Carried Into This Phase
- **`GeniusInputValidator.cpp` "untouched" assumption from the original design doc (D-22/D-23) does not survive contact with D-60.** This is the single most important thing for the researcher and planner to internalize before starting: CONS-06's "orthogonal to UTXO ownership" framing needs updating to "orthogonal, but the signature-acceptance layer gains a narrow CRDT-gated exception" — not "zero changes to GeniusInputValidator.cpp."

</code_context>

<specifics>
## Specific Ideas

- User's directional call on the central open question: "Main signs transaction, consensus accepts because CRDT records indicate that it is a child wallet." This is the locked resolution (D-60) — the mechanism is CRDT-derived authority, not cryptographic delegation of the child's key.
- User confirmed CONS-01 needs no new code — reuse existing `TransferFunds` as-is.
- User confirmed simplicity preferences throughout: Approve/Reject only (no Pending retry state), tests extend existing files (no new dedicated test file) — consistent with this project's general preference for minimal surface area over exhaustive new scaffolding (see also project memory: no dedicated GeniusSDK tests for thin wrappers).

</specifics>

<deferred>
## Deferred Ideas

- GeniusSDK C API exposure of both transfer directions — Phase 4 (SDKT-01/02/03), explicitly next in the roadmap.
- Transfer amount limits/policy beyond CONS-01/CONS-02 — out of scope for v2.3 entirely (POL-01, future milestone).
- GeniusWallet Flutter UI wiring for child-wallet transfers — out of scope for v2.3 entirely (UI-01, future milestone).

### Reviewed Todos (not folded)
None — no pending todos matched this phase (`todo.match-phase` returned zero matches).

</deferred>

---

*Phase: 3-Parent-Child Transfer Authority*
*Context gathered: 2026-07-20*
