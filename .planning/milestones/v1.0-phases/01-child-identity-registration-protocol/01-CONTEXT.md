# Phase 1: Child Identity & Registration Protocol - Context

**Gathered:** 2026-07-13
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase produces two design documents:
1. The **child-wallet identity model** — an independent secp256k1 keypair created like any other wallet, with its own nonce, standalone creation, and UTXO ownership (IDENT-01..04).
2. The **registration protocol** — a child-signed `RegistrationTx` that names a main wallet, its additive proto schema, and its monotonic sequencing for replay protection (REG-01..05).

Persistence (CRDT namespace/filter), pubsub broadcast/sync, consensus authority rules, discovery, rewards, and lifecycle change-flows are **out of scope** here — they are Phases 2–3. This phase only defines the identity and the registration record/tx that later phases persist, validate, and act on.
</domain>

<decisions>
## Implementation Decisions

### Child Identity Marker
- **D-01:** A child wallet is created exactly like any other wallet — a `GeniusNode`/`GeniusAccount` with its own independent secp256k1 private key. **No new account-type field, no creation-time flag.** "Child-ness" is **emergent**: an account is a child wallet iff a valid registration entry naming a main exists in consensus-visible state. `GeniusAccount.hpp` stays untouched for identity purposes.
- **D-02:** UTXO ownership (IDENT-04) needs no special design. A child owns its UTXOs via the standard `UTXOEntryRecord.owner_address` = child address (128-hex 512-bit pubkey-derived address per `GeniusAccount::IsValidPublicKey`). Child-owned assets are distinguishable by owner address alone.
- **D-03:** Independent nonce tracking (IDENT-02) reuses the existing per-account nonce machinery in `GeniusAccount` (`GetProposedNonce`/`ReserveNextNonce`/confirmed-nonce map). A child's account nonce is naturally distinct from the main's because it is a separate account.

### Registration Model — signing
- **D-04:** Registration is **child-signed only.** The child signs the `RegistrationTx`; consensus accepts it because the child's own signature is valid over its own registration event. **The main wallet does NOT counter-sign.**
- **D-05:** ⚠ **This reverses locked requirement REG-02 (dual-signature) and PROJECT.md's "dual-signature required" decision.** The design doc MUST state this explicitly. Rationale/consequence to document:
  - Main *consent* is expressed at the UX level via the connect flow (see D-10), not by a cryptographic counter-signature.
  - Because there is no main signature, consensus cannot verify the named main actually consented — **any child can claim any main.** This is acceptable because a registration grants the child **zero authority over the main** (funding and recovery both require the *main's* signature in Phase 2). The bounded impact is discovery-view spam (a main could see unsolicited "claimed child" entries), NOT loss of funds.
  - Downstream: flag REG-02 and the PROJECT.md "Dual-signature" key decision for update at phase transition.

### Registration Carrier
- **D-06:** Registration is a **first-class `RegistrationTx`** — a new `GeniusTransaction` subclass with a new arm in `SGTransaction.proto`. It flows through the **same `TransactionManager` path** as `TransferTx`/`EscrowTx` (create → sign → `FilterTransaction` → validation → persist). This reuses `DAGStruct` (nonce, signature, hashing via `FillHash`/`CheckSignature`), consensus ordering, and existing `tx/` persistence for free.
- **D-07:** The registration **record** materializes into a CRDT namespace as the committed/queryable current state. The tx authenticates the event; the CRDT entry holds state. **The CRDT namespace layout and validating element filter are a Phase 2 hand-off** — not designed here.

### Registration Schema (REG-01, REG-03)
- **D-08:** Single top-level **`RegistrationTx`** message:
  - `DAGStruct dag_struct = 1` — reuses `source_addr` (= child address), `nonce`, `signature`, `timestamp`, hashing.
  - `main_address` — the registered main wallet (pubkey/address supplied via connect flow).
  - `sequence` — dedicated monotonic per-child registration sequence (see D-09).
  - optional embedded **`RegistrationMetadata`** sub-message: `game_id`, `publisher_id`, `dev_wallet`, `peers_cut`.
  - **All new field numbers, additive-only. No renumbering of existing fields.** The design doc MUST include a backward-compatibility matrix (Pitfall 7). New arm added to whatever oneof/dispatch mechanism the tx path uses; do NOT modify existing `TransferTx`/`EscrowTx`/`MintTx` messages.

### Sequencing & Replay (REG-05, IDENT-02)
- **D-09:** `RegistrationTx` carries **both**:
  - `DAGStruct.nonce` — per-account tx ordering that drives the normal tx path.
  - a dedicated monotonic **`sequence`** field scoped to a child's registration events only. Consensus selects the highest valid registration `sequence` as authoritative; replace/detach reference the prior sequence ("supersedes seq N").
  - This separates account tx ordering from registration lineage ordering (Pitfalls 1 & 2). **The tie-break rule (e.g., tx hash) and the exact consensus-ordering mechanism are a Phase 2 hand-off** — Phase 1 only defines that the field exists and is monotonic.

### Connect / Signing Boundary (REG-04)
- **D-10:** The connect flow (GNUS Wallet app / "Connect GNUS Wallet" UI) **only delivers the main wallet's public key** to the child app. The main performs **no signing** during registration, so REG-04 ("main private key never enters the game/child process") is satisfied trivially. The design doc specifies this pubkey-delivery handshake as **transport-agnostic**; concrete platform UI flows are out of scope (v2 / PLAT-01, PLAT-02).

### Agent's Discretion
- Exact proto field numbers and the mechanical shape of the new tx arm/dispatch — planner/researcher choose the idiomatic form matching existing `SGTransaction.proto` conventions, subject to additive-only.
- Naming of the new tx subclass, metadata message, and its C++ file placement under `SuperGenius/src/account/` — follow existing `GeniusTransaction` subclass conventions.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative spec
- `GNUS_Subwallet_Architecture_Proposal.md` — full child-wallet architecture. Phase-1-relevant sections: §High-Level Concept, §Core Properties, §Main-Wallet Registration (record fields, registration flow), §Security Model, §Lifecycle States. NOTE: proposal §Registration Flow step 4 assumes main counter-signature; decision D-04/D-05 supersedes this to child-signed-only.

### Planning docs
- `.planning/PROJECT.md` — locked decisions (independent keypair, additive proto). NOTE: "Dual-signature required" key decision is superseded by D-04; flag for transition.
- `.planning/REQUIREMENTS.md` — IDENT-01..04, REG-01..05. NOTE: REG-02 (dual-signature) is reversed by D-04; flag for transition.
- `.planning/ROADMAP.md` §Phase 1 — goal + 4 success criteria this context must satisfy.
- `.planning/research/SUMMARY.md` — stack/feature/architecture grounding (HIGH confidence).
- `.planning/research/PITFALLS.md` — Pitfall 1 (replay/reorder), Pitfall 6 (child-key blast radius), Pitfall 7 (proto compat) are directly relevant to Phase 1.

### Code anchor points (audited, exist today)
- `SuperGenius/src/account/proto/SGTransaction.proto` — where the additive `RegistrationTx` + `RegistrationMetadata` messages go. Existing patterns: `TransferTx`, `EscrowTx`, `MintTxV2` (all embed `DAGStruct dag_struct = 1`), `UTXOEntryRecord.owner_address`.
- `SuperGenius/src/account/proto/SGAccountComm.proto` — request/response messaging pattern (`SignedNonceRequest`, etc.); reference for how signed messages are shaped (connect-flow pubkey delivery may relate, but is transport-agnostic in Phase 1).
- `SuperGenius/src/account/GeniusAccount.hpp` — identity/keypair/nonce anchor (`Sign`, `VerifySignature`, `GetProposedNonce`, `ReserveNextNonce`, `IsValidPublicKey`, `NormalizeAddress`, `eth_keypair_`). Independent secp256k1 keypair via `EthereumKeyGenerator`.
- `SuperGenius/src/account/GeniusTransaction.hpp` — base class the new `RegistrationTx` subclass extends (`FillHash`, `MakeSignature`, `CheckSignature`, `SerializeToEmbeddedTransaction`, `RegisterDeserializer`, `GetSlotID` = `src:nonce`).
- `SuperGenius/src/account/GeniusNode.*` — standalone child creation / `AccountSource` (IDENT-03).
- `SuperGenius/src/account/GeniusUTXO.hpp`, `UTXOStructs.hpp` — UTXO ownership (IDENT-04).
- `SuperGenius/src/account/TransactionManager.cpp` — `FilterTransaction` (how tx types are gated), the path `RegistrationTx` flows through.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GeniusTransaction` base class — new `RegistrationTx` extends it; inherits hashing, signing, serialization, deserializer registry. No new tx infrastructure needed.
- `DAGStruct` proto (`source_addr`, `nonce`, `timestamp`, `signature`) — reused verbatim as `dag_struct = 1` in `RegistrationTx`, giving child-signed authenticity + account ordering for free.
- `GeniusAccount` nonce machinery — per-account nonce (proposed/reserved/confirmed) already isolates a child's ordering from the main's since they are separate accounts.
- Existing tx subclasses (`TransferTx`, `EscrowTx`, `MintTxV2`, `MigrationTx`) — templates for the additive proto message + C++ subclass shape.

### Established Patterns
- Every tx type embeds `DAGStruct dag_struct = 1` and adds type-specific fields with fresh field numbers — additive-only proto evolution is the established norm.
- Transactions are gated in `TransactionManager::FilterTransaction` by key pattern (`tx/`, `proof/`); a registration record will need its own gate/namespace — but that filter is **Phase 2**.
- Authorization today is **purely cryptographic signature verification** — there is NO hierarchical/role authority. Phase 1 stays within this model (child signs its own registration); the parent-child authority layer is Phase 2.

### Integration Points
- `SGTransaction.proto` — new messages appended (additive).
- Tx create/dispatch path in `TransactionManager` — new `RegistrationTx` registered like other types.
- `GeniusTransaction::RegisterDeserializer` — register the new type's deserializer.
- Connect flow (main pubkey delivery) — a new, transport-agnostic seam on the child side; concrete transport deferred.

</code_context>

<specifics>
## Specific Ideas

- User's exact framing: "A child wallet will initially be created like any other wallet as a GeniusNode with a private key. We will have a mechanism to connect [the child] to our GeniusWallet app, which will give the app with the intended child wallet the main GeniusWallet's public key. The child wallet will add an entry to CRDT signed by itself — this is a new type of CRDT entry — it will contain data as to the main wallet public key. Consensus passes because it is signed by the child wallet account."
- This is the definitive Phase-1 shape: child-signed registration, main pubkey delivered by connect flow, new registration entry type carried as a first-class tx that materializes into CRDT.

</specifics>

<deferred>
## Deferred Ideas

- **CRDT registration namespace + validating element filter** — Phase 2 (SYNC-01, SYNC-02).
- **Registration sequence tie-break rule + consensus ordering mechanism** — Phase 2 (resolves the CRDT eventual-consistency vs ordering tension).
- **Pubsub broadcast of registration + main subscribing to child channels** — Phase 2 (SYNC-03, SYNC-04, SYNC-05).
- **All consensus authority rules** (main→child fund, destination-restricted recovery, child→arbitrary/main/developer, child-cannot-spend-main rejection) — Phase 2 (CONS-01..06).
- **Optional out-of-process main acceptance signature** (pending→confirmed upgrade) — considered and rejected for Phase 1 in favor of child-signed-only; could be revisited as a v2 hardening if discovery-spam becomes a real problem.
- **Metadata/reward-policy update rules** (authenticated dev-wallet/split changes) — Phase 3 (RWD-03).
- **Lifecycle state machine + replace/detach/revoke change-flows** ("supersedes seq N" mechanics) — Phase 3 (LIFE-01..04).
- **Platform "Connect GNUS Wallet" UI flows** — v2 (PLAT-01, PLAT-02); Phase 1 only defines the transport-agnostic pubkey-delivery handshake.

</deferred>

---

*Phase: 1-Child Identity & Registration Protocol*
*Context gathered: 2026-07-13*
