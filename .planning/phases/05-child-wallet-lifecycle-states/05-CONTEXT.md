# Phase 5: Child Wallet Lifecycle States - Context

**Gathered:** 2026-07-21
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase implements the three child-wallet lifecycle transitions that move a registered child out of (or between) main-wallet associations, per the v1.0 lifecycle design (`docs/03-02-reward-policy-lifecycle.md` §6-10, archived design authored in `.planning/milestones/v1.0-phases/03-discovery-rewards-lifecycle/03-CONTEXT.md` D-34 through D-39):

1. **Detach (child-initiated):** child signs a new `RegistrationTx` with `main_address` cleared, `detach_flag = true`, `sequence` incremented, `supersedes_sequence` = current sequence.
2. **Revoke (main-initiated):** main signs a new first-class `RevokeTx` (new `EmbeddedTransaction` oneof arm 9) targeting the child's `reg/` record; validated via an extended `CheckParentChildAuthority` gate (main signature + `reg/{child}.main_address == signer` + Registered state).
3. **Replace-Main (child-initiated):** child signs a new `RegistrationTx` with a *different* `main_address`, `detach_flag = false`, `sequence` incremented, `supersedes_sequence` = current sequence — added to this phase's scope because it reuses the identical `supersedes_sequence` CRDT-filter mechanism as Detach (see Decisions below).

All three transitions share one new `FilterRegistration` gate extension: a `supersedes_sequence` check (gate 3b) that rejects any lifecycle-change `RegistrationTx` whose `supersedes_sequence` doesn't match the current `reg/{child_addr}` record's `sequence` — this is the fork-prevention mechanism for all three flows, not three separate gates.

**Explicitly OUT of scope for this phase** (confirmed against roadmap wording, not re-litigated):
- **Reward policy resolution (RWD-01/02/03)** — `HoldEscrow`/`PayDev`/`ProcessImage` reading `RegistrationMetadata.dev_wallet`/`peers_cut` instead of `DevConfig_st`. This is a separate concern from lifecycle state transitions, documented in the same source doc but not part of this phase's roadmap goal. Deferred to a future phase if/when needed.
- **GeniusSDK C API exposure** of Detach/Revoke/Replace-Main (see Decisions — deferred, mirrors the Phase 3→4 split).
- **Discovery/monitoring dashboard changes** (DISC-01/02/03, MON-01/02) — already deferred at the project level.

</domain>

<decisions>
## Implementation Decisions

### Scope: Replace-Main Included (LIFE-03)
- **D-70 (User's call):** Include Replace-Main (child swaps `main_address` without detaching) in this phase, not deferred. Rationale given: it reuses the identical `supersedes_sequence` CRDT-filter gate mechanism as Detach — implementing the gate for one and not the other would mean re-deriving the same fork-prevention logic twice, in two separate phases, for no isolation benefit.
- This phase's requirement set is therefore **LIFE-01 (state machine + Detach + Revoke transitions), LIFE-02 (supersedes_sequence linkage/fork-prevention), LIFE-03 (main replacement, child-only, no old-main consent — D-37), and LIFE-04 (detach/revoke/replace leaves child a valid standalone-capable wallet — UTXOs/keypair/nonce unaffected, D-39)**. Final requirement IDs/wording are the planner's to confirm against `.planning/REQUIREMENTS.md` conventions used in prior phases.
- D-37 (already locked in v1.0 design, not re-opened): Replace-Main is **child-only** — no consent signature required from the old main. Rationale: avoids deadlock if the old main's key is lost; consistent with the child-owned identity model (D-04/D-05).

### API Shape: Dedicated Methods, Two-Layer Convention
- **D-71 (User's call):** Add **dedicated** `TransactionManager::DetachChild` + `GeniusNode::DetachChild` (child-initiated) and `TransactionManager::RevokeChild` + `GeniusNode::RevokeChild` (main-initiated) methods — NOT an overload extension of the existing `RegisterChild`/`TransferFunds` methods.
- This matches the project's established precedent: D-62 (Phase 3) added a dedicated `RecoverFromChild` rather than overloading `TransferFunds`; D-66 (Phase 4) added a dedicated `GeniusSDKFundChild` rather than just documenting that the generic transfer call already covered it. The user has consistently chosen discoverable, dedicated, symmetric names over reusing generic machinery for a specific caller intent.
- Replace-Main's method shape is the researcher/planner's call — likely a third dedicated method (e.g. `ReplaceMain`) or a shared parameterized method with Detach given both transitions are child-signed `RegistrationTx` updates with `supersedes_sequence`; the difference is only whether `main_address` is cleared or replaced and whether `detach_flag` is set. Planner should follow the two-layer convention (`TransactionManager::X` + thin `GeniusNode::X` wrapper) for whichever shape is chosen, mirroring `RecoverFromChild`/`RegisterChild`.
- `RevokeChild` mirrors `RecoverFromChild`'s two-layer shape exactly (main-initiated action against a child's `reg/` record).

### SDK Timing: Deferred (mirrors Phase 3→4 split)
- **D-72 (User's call):** No `GeniusSDKDetach`/`GeniusSDKRevoke`/`GeniusSDKReplaceMain` C API functions in this phase. This phase stays at the proto/consensus-gate/CRDT-filter/`GeniusNode` layer only, exactly mirroring how Phase 3 (consensus gate + `RecoverFromChild`) was split from Phase 4 (`GeniusSDK` C API wrapper). SDK exposure of lifecycle actions is a future phase, likely numbered after this one, analogous to Phase 4.

### Test Depth: Full Adversarial Coverage
- **D-73 (User's call):** Mirror Phase 3's REGR-pattern rigor, not just happy-path tests. This phase's automated E2E regression suite must prove:
  - **Fork detection:** two competing lifecycle-change `RegistrationTx` entries at the same `supersedes_sequence` — only the first to reach consensus at its nonce is accepted; the second is rejected at gate 3b (per design doc §9.3-9.4).
  - **Replay prevention:** an old/stale lifecycle `RegistrationTx` replayed at a higher nonce is rejected both by `sequence > current.sequence` (gate 3) and by the nonce chain (`sgns.nonce.v1`) rejecting the reused nonce (design doc §9.4, T-03-12).
  - **Unauthorized revoke:** `RevokeTx` signed by a wallet that is NOT the certified `main_address` on the target `reg/{child}` record → rejected. `RevokeTx` targeting a `reg/{child}` record NOT currently in Registered state (already detached/revoked) → rejected.
  - **Re-registration after Detach/Revoke:** child can re-register (same or different main) at higher sequence after either transition — proves D-39's "not final for the child wallet" invariant.
  - **Post-transition invariants (LIFE-04):** child's UTXOs, keypair, and nonce counter are unaffected by Detach/Revoke/Replace-Main — only the `reg/` record's fields change.
  - Per D-65 (Phase 3 precedent, expected to hold here too): extend the **existing** TransactionManager/registration consensus test file(s) rather than creating a new dedicated test file, unless the researcher/planner finds a strong reason to split.

### Claude's Discretion
- Exact proto field numbers for `detach_flag`/`supersedes_sequence` on `RegistrationTx` — the design doc already specifies field 5 (`detach_flag`, bool) and field 6 (`supersedes_sequence`, uint64) appended additively; confirm these are still free in the current `.proto` file at implementation time (confirmed free as of this discussion — see Code Context below) and use them unless something has changed.
- `RevokeTx` proto message shape — the design doc specifies `dag_struct` (1), `child_address` (2), `registration_sequence` (3); confirm field 9 is still free on the `EmbeddedTransaction` oneof (confirmed free as of this discussion) and use it.
- Exact insertion point and code shape of the `CheckParentChildAuthority` extension for `RevokeTx` — today the gate only branches on `tx.GetType() == "transfer"` (everything else passes trivially, per code scout below); the researcher/planner must add a new branch for the `"revoke"` tx type. Unlike Phase 3's D-60 recovery case, this does NOT require touching `CheckTransactionAuthorization`/`ValidateWitness`'s signature-verification model — a `RevokeTx` is naturally signed by the main as its own transaction (the main is the tx's own source/signer; `child_address` is just a payload field, not a `src` being spent from), so ordinary signature verification already works. The only new logic needed is: after signature verification passes, look up `reg/{child_address}`, confirm `main_address == signer` and the record is in Registered state (`detach_flag == false`).
- Whether Replace-Main shares a method/tx-construction path with Detach or gets a fully separate one — see API Shape above.
- Exact requirement ID wording/numbering in `.planning/REQUIREMENTS.md` — planner reconciles the four LIFE-0x IDs referenced here with the project's existing requirement-numbering conventions.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design doc (primary spec for this phase — read first, in full)
- `docs/03-02-reward-policy-lifecycle.md` — §6 Lifecycle State Machine (LIFE-01, four states, transition table), §7 Detach Flow (LIFE-01/02), §8 Revoke Flow + RevokeTx proto design (LIFE-01/02), §9 Replace Main + Policy Fork Decision (LIFE-02/03), §10 Detach Semantics/invariants (LIFE-04), §11 Proto Evolution Summary (exact field numbers for all three transitions), §12 Requirement Traceability. **§2-5 (Reward Policy Resolution, RWD-01/02/03) are OUT OF SCOPE for this phase — do not implement, only the lifecycle sections (§6-10) apply.**

### Prior phase context (locked decisions this phase builds on)
- `.planning/milestones/v1.0-phases/03-discovery-rewards-lifecycle/03-CONTEXT.md` — D-34 (four-state model, no pending/closed states), D-35 (Detach mechanism), D-36 (Revoke mechanism, main-signed), D-37 (Replace-Main is child-only, deadlock-avoidance rationale — NOT re-opened this discussion), D-38 (supersedes_sequence chain-of-custody + fork resolution), D-39 (detach/revoke leaves child a valid standalone wallet).
- `.planning/phases/03-parent-child-transfer-authority/03-CONTEXT.md` — D-60 (CRDT-derived authority model for main-signed actions on child accounts — the precedent this phase's `RevokeTx` validation follows, though notably simpler since Revoke doesn't have a `src=child` signature-verification problem the way Recovery did), D-62 (dedicated two-layer method convention — `RecoverFromChild` is the direct precedent for `RevokeChild`/`DetachChild`), D-63 (certified-status lookup via `blockchain_->CheckCertifiedParent`), D-64 (gate returns Approve/Reject only, no Pending state), D-65 (regression tests extend existing test files).
- `.planning/phases/04-geniussdk-transfer-wrappers/04-CONTEXT.md` — D-66 (dedicated wrapper naming precedent), D-67/68/69 (fire-and-forget SDK convention, GNUS-string sibling functions, error-code reuse) — relevant only once a future SDK-exposure phase begins; not implemented in this phase.

### Planning docs
- `.planning/PROJECT.md` — Current validated requirements, Key Decisions table (D-01 through D-70+), security constraint (child signs its own spends; main's authority is bounded to specific signature-gated actions — now includes revoke as one of those bounded actions).
- `.planning/ROADMAP.md` §Phase 5 — goal statement (detach_flag/supersedes_sequence fields, RevokeTx oneof arm 9, FilterRegistration extension, CheckParentChildAuthority reuse).
- `.planning/STATE.md` — Roadmap Evolution note on why Phase 5 was added; full decisions log D-01 through D-69.

### Code anchor points (verified against current code, 2026-07-21)
- `SuperGenius/src/account/proto/SGTransaction.proto:146-152` — `RegistrationTx` message, current 4 fields (`dag_struct`=1, `main_address`=2, `sequence`=3, `metadata`=4). Fields 5 (`detach_flag`) and 6 (`supersedes_sequence`) confirmed NOT present yet — free to add additively.
- `SuperGenius/src/blockchain/impl/proto/Consensus.proto:70-81` — `EmbeddedTransaction` oneof, arms 1-8 in use (`registration`=8 is highest); arm 9 confirmed free for `revoke`.
- `SuperGenius/src/account/TransactionManager.cpp:2986-3065` — `FilterRegistration`, current gates: deserialization (L2994-2999), child-signature check (L3011-3016), `main_address` size/hex validation (L3018-3023), sequence monotonicity (L3025-3054). No `supersedes_sequence` gate exists yet — this is the insertion point for gate 3b.
- `SuperGenius/src/account/TransactionManager.hpp:685` — `RegisterElementFilter` registration point for `FilterRegistration` (registered around `TransactionManager.cpp:233`).
- `SuperGenius/src/account/TransactionManager.cpp:4255-4287` (declared `TransactionManager.hpp:784`) — `CheckParentChildAuthority`. Current logic ONLY branches on `tx.GetType() == "transfer"` (L4258-4262) — any other tx type (including a future `"revoke"` type) passes trivially today. This is the exact spot needing a new `"revoke"` branch. Called from `ValidateTransactionForConsensus` at `TransactionManager.cpp:4156`, between `CheckTransactionAuthorization` (L4147) and `CheckTransactionTimestamp` (L4165).
- `SuperGenius/src/account/TransactionManager.cpp:594` (`RecoverFromChild`), `TransactionManager.cpp:651,667` (`RegisterChild`) — the two-layer method precedents to mirror for `DetachChild`/`RevokeChild`.
- `SuperGenius/src/account/GeniusNode.cpp:2285,2307` (`RecoverFromChild`), `GeniusNode.cpp:2334,2349` (`RegisterChild`); `GeniusNode.hpp:544,559,571,584` — `GeniusNode`-level wrapper precedents.
- No `RevokeTx`, `detach_flag`, or `supersedes_sequence` found anywhere in `SuperGenius/src` or `GeniusSDK/` as of this scout — confirms this is genuinely greenfield work, not a partial implementation.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CheckParentChildAuthority` (`TransactionManager.cpp:4255-4287`) — already slots into `ValidateTransactionForConsensus`; extending it with a `"revoke"` branch avoids adding a whole new gate call site.
- `blockchain_->CheckCertifiedParent(address)` (D-63 precedent) — existing certified-registration lookup mechanism; the revoke gate branch and the `supersedes_sequence` filter gate both need equivalent `reg/{child_addr}` reads.
- `sgns.nonce.v1` nonce-chain infrastructure — already used by `RegistrationTx` (D-24); `RevokeTx` reuses the same subject for replay protection, no new consensus-subject plumbing needed.
- Two-layer method convention (`TransactionManager::X` + `GeniusNode::X`) — fully established by `TransferFunds`, `RegisterChild`, `RecoverFromChild`; `DetachChild`/`RevokeChild` follow it exactly.

### Established Patterns
- Additive-only proto evolution — every existing field number in `RegistrationTx` (1-4) and every existing oneof arm (1-8) stays untouched; new fields/arms only append.
- `FilterRegistration`'s gate-list pattern (deserialize → signature → format → sequence) — gate 3b (`supersedes_sequence`) slots in as one more sequential check, same style as the existing gates.
- `ValidateTransactionForConsensus`'s per-gate private-method pattern, identical logging/error-message shape across gates (established across Phases 2-3) — the new `"revoke"` branch in `CheckParentChildAuthority` should match this style.

### Integration Points
- `SGTransaction.proto` — append `detach_flag` (bool, field 5) and `supersedes_sequence` (uint64, field 6) to `RegistrationTx`; add new `RevokeTx` message (`dag_struct`=1, `child_address`=2, `registration_sequence`=3).
- `Consensus.proto` `EmbeddedTransaction` oneof — add `revoke = 9`.
- `TransactionManager::FilterRegistration` (`TransactionManager.cpp:2986-3065`) — add gate 3b (`supersedes_sequence` check) after the existing sequence-monotonicity gate.
- `TransactionManager::CheckParentChildAuthority` (`TransactionManager.cpp:4255-4287`) — add a `"revoke"` branch alongside the existing `"transfer"` branch.
- New `TransactionManager::DetachChild`/`RevokeChild` (and Replace-Main's method, shape TBD) + `GeniusNode::DetachChild`/`RevokeChild` — new methods, placed near `RegisterChild`/`RecoverFromChild` in both files.
- `TransactionManager`'s `transaction_parsers` dispatch table — Phase 3 discovered (and fixed) a gap where `"registration"` had no entry, causing "Unknown tx type" rejection before certification could ever happen. **Researcher must verify `"revoke"` gets a dispatch-table entry from day one** — do not repeat the Phase 3 near-miss.

</code_context>

<specifics>
## Specific Ideas

- User's directional calls, in order: (1) fold Replace-Main into this phase since the fork-prevention gate is identical either way; (2) dedicated `DetachChild`/`RevokeChild` methods, not overloads — consistent with the project's repeated preference for discoverable, symmetric, dedicated method names (D-62, D-66); (3) defer all GeniusSDK C API exposure to a future phase, exactly mirroring the Phase 3→4 split; (4) full adversarial regression coverage (fork, replay, unauthorized revoke, re-registration), not just happy-path — matching Phase 3's REGR rigor rather than a lighter bar.
- Consistent theme: this user wants the lifecycle-transition layer (proto + consensus + CRDT filter + GeniusNode caller surface) fully hardened and tested in one phase, with external-facing SDK exposure explicitly pushed to its own later phase — the same two-step pattern already proven out by Phases 3→4.

</specifics>

<deferred>
## Deferred Ideas

- **GeniusSDK C API wrappers** for Detach/Revoke/Replace-Main (`GeniusSDKDetachChild`, `GeniusSDKRevokeChild`, etc.) — future phase, mirrors Phase 4's role relative to Phase 3.
- **Reward policy resolution** (RWD-01/02/03: `HoldEscrow`/`PayDev`/`ProcessImage` reading `RegistrationMetadata.dev_wallet`/`peers_cut` instead of `DevConfig_st`) — separate concern from lifecycle transitions; not scoped to this phase. Revisit as its own phase if/when needed.
- **GeniusWallet Flutter UI wiring** for lifecycle actions (inspect/revoke/detach buttons) — already deferred at the project level (UI-01).
- **Discovery/monitoring dashboard** showing lifecycle status per child — already deferred at the project level (MON-01/02).

### Reviewed Todos (not folded)
None — no pending todos matched this phase (`todo.match-phase` returned zero matches).

</deferred>

---

*Phase: 5-Child Wallet Lifecycle States*
*Context gathered: 2026-07-21*
