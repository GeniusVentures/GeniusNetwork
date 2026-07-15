# Phase 04: Registration Proto & Transaction - Context

**Gathered:** 2026-07-15
**Status:** Ready for planning

<domain>
## Phase Boundary

The SuperGenius node builds with the new `RegistrationTx` proto and `RegistrationTransaction` C++ subclass, and a child wallet can construct, sign, and submit a registration through the existing TransactionManager path — carrying it through full consensus (`sgns.nonce.v1`), writing to `reg/{child_addr}` CRDT, and verified by a GTest unit test.

Phase 4 delivers: proto schema additions (`RegistrationTx`, `RegistrationMetadata`, `registration = 8` oneof arm), the C++ subclass (factory, serialization, deserialization, deserializer registration + dispatch), the child-side API (create, sign, submit), and the minimal `FilterRegistration` element filter on the `reg/` namespace.

CRDT pubsub broadcast, main-node discovery read path, multi-node integration test, and full `FilterRegistration` (sequence monotonicity gate) are **Phase 5**.
</domain>

<decisions>
## Implementation Decisions

### Child-side API surface (from checkpoint)
- **D-40:** Both layers, full convention: `TransactionManager::RegisterChild(main_address, metadata, sequence) -> outcome::result<std::string>` (builds `New()`, signs via `MakeSignature`, submits via `SendTransactionItem`) plus a thin `GeniusNode` wrapper, mirroring the `TransferFunds`/`MintTokens` two-layer convention.
- **D-41:** Full metadata param: `main_address` + optional `RegistrationMetadata` (game_id, publisher_id, dev_wallet, peers_cut) defaulting to empty; GTest round-trips it.

### Sequence tracking (from checkpoint)
- **D-42:** Caller-supplied param: `RegisterChild(main_address, metadata, sequence)`. Phase 4 GTest passes 1; Phase 5 derives "last confirmed + 1" from `reg/{child_addr}` and can wrap it. No throwaway in-memory state.

### Phase 4 storage path (from checkpoint)
- **D-43:** `reg/` path lands in Phase 4: divert the CRDT write for `RegistrationTx` to `GetBlockChainBase() + "reg/" + child_addr` now — no registration ever touches `tx/`. Requires touching `SendTransactionItem`'s shared path logic. Planner must address the `GetTransactionFullPath()` hardcoded `"tx/" + GetHash()` override approach.

### Validation eagerness
- **D-44:** Minimal `FilterRegistration` in Phase 4 — implement the element filter **partially**, named `FilterRegistration` (same name Phase 5 extends), registered on the `^/?/bc-{net}/reg/` pattern in `TransactionManager::New()`. Phase 4 gates reject: (a) deserialization failure, (b) invalid child signature, (c) malformed `main_address` (not 128-hex pubkey). Accept everything else — including sequence=0 and sequence collisions. Phase 5 adds the sequence monotonicity gate to the same method.
- **D-45:** GTest verifies the minimal filter: valid `RegistrationTx` passes the filter (no tombstone), tampered-signature `RegistrationTx` is rejected (tombstone). Malformed-address and sequence tests deferred to Phase 5.

### the agent's Discretion
- Exact proto field numbers for `RegistrationTx` and `RegistrationMetadata` — planner chooses fields 8+ following additive-only convention, matching existing `TransferTx`/`EscrowTx`/`MintTxV2` patterns (all embed `DAGStruct dag_struct = 1`).
- `registration = 8` oneof arm placement in `Consensus.proto` `EmbeddedTransaction` — planner verifies field number 8 is unused.
- Naming and file placement of `RegistrationTransaction` C++ files — under `SuperGenius/src/account/`, following existing `GeniusTransaction` subclass conventions (`RegistrationTransaction.hpp`/`.cpp`).
- Mechanical shape of the `SerializeToEmbeddedTransaction`/`SerializeByteVector`/`DeSerializeByteVector` + `RegisterDeserializer` — follow `TransferTransaction` pattern exactly (static `Register()` with `static inline bool registered = Register()`).
- `GetTransactionSpecificPath()` override to return `"registration"` (the transaction type string, matching the existing pattern); the `reg/{child_addr}` path override happens at the `SendTransactionItem` CRDT write level, not via the virtual path methods.
- GTest file placement under `SuperGenius/test/src/account/` following existing transaction test conventions.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative design docs
- `docs/registration-protocol.md` — RegistrationTx schema (§2-3), C++ subclass design (§4), submission path (§5-6). This is the canonical field reference for all registration-related proto and C++ design.
- `docs/child-wallet-identity-model.md` — Independent keypair model, emergent child-ness (D-01), UTXO ownership (D-02), nonce tracking (D-03).
- `docs/02-crdt-registry-pubsub.md` — CRDT registry namespace/key layout, `FilterRegistration` element filter design (full gates: deserialization, signature, sequence monotonicity, well-formed). Phase 4 implements the first two gates; Phase 5 adds sequence monotonicity.

### Architecture proposal
- `GNUS_Subwallet_Architecture_Proposal.md` — Full child-wallet architecture. NOTE: §Registration Flow step 4 assumes main counter-signature; superseded by D-04/D-05 (child-signed-only).

### Planning docs
- `.planning/PROJECT.md` — Locked project-level decisions: independent keypair, consensus-enforced authority, CRDT persistence, child-signed-only, additive proto.
- `.planning/REQUIREMENTS.md` — RIMPL-01, RIMPL-02, RIMPL-03 (Phase 4 requirements).
- `.planning/ROADMAP.md` §Phase 4 — goal + 3 success criteria this context must satisfy.
- `.planning/STATE.md` — Current milestone (v2.0), blockers (consensus authority deferred, CRDT path divergence warning).

### Prior phase context (locked decisions)
- `.planning/milestones/v1.0-phases/01-child-identity-registration-protocol/01-CONTEXT.md` — D-01 through D-10: emergent child-ness, UTXO ownership, independent nonce, child-signed-only, first-class RegistrationTx schema, dual nonce+sequence, connect-flow pubkey delivery.
- `.planning/milestones/v1.0-phases/02-crdt-persistence-pubsub-consensus-authority/02-CONTEXT.md` — D-11 through D-26: reg/ namespace + FilterRegistration, CRDT key `reg/{child_addr}`, CRDT value = full RegistrationTx protobuf, pubsub CID-only notification, full consensus via `sgns.nonce.v1`, certified-status two-tier model.
- `.planning/milestones/v1.0-phases/03-discovery-rewards-lifecycle/03-CONTEXT.md` — D-27 through D-39: discovery model, reward policy, lifecycle states. Phase 4 only depends on the RegistrationTx schema defined here (including `RegistrationMetadata` fields: game_id, publisher_id, dev_wallet, peers_cut).

### Code anchor points (exist today)
- `SuperGenius/src/account/proto/SGTransaction.proto` — Where additive `RegistrationTx` + `RegistrationMetadata` messages are appended. Existing patterns: `TransferTx`, `EscrowTx`, `MintTxV2`, `MigrationTx`, `ProcessingTx` (all embed `DAGStruct dag_struct = 1`).
- `SuperGenius/src/blockchain/impl/proto/Consensus.proto` — `EmbeddedTransaction` oneof where `registration = 8` arm is added (fields 1-7 are occupied: transfer, mint_v2, mint, processing, migration, escrow, escrow_release).
- `SuperGenius/src/account/GeniusTransaction.hpp` — Base class: `FillHash`, `MakeSignature`, `CheckSignature`, `SerializeToEmbeddedTransaction`, `SerializeByteVector`, `DeSerializeDAGStruct`, `RegisterDeserializer`, `GetTransactionFullPath` (hardcodes `"tx/"` + hash), `GetSlotID` (= `src:nonce`).
- `SuperGenius/src/account/TransferTransaction.hpp` — Reference subclass pattern: `New()` factory, private constructor, `SerializeByteVector`, `SerializeToEmbeddedTransaction`, `DeSerializeByteVector`, `GetTransactionSpecificPath`, `HasUTXOParameters`, `GetTopics`, static `Register()` with `static inline bool registered`.
- `SuperGenius/src/account/TransactionManager.hpp` + `.cpp` — `DeSerializeEmbeddedTransaction` (oneof switch dispatch, lines 1395-1449), `SendTransactionItem` (CRDT write + SubmitProposal path), `FilterTransaction` (pattern for `FilterRegistration`), `GetBlockChainBase()` (base path for `reg/` namespace).
- `SuperGenius/src/crdt/globaldb/globaldb.hpp` — `RegisterElementFilter(regex, callback)` pattern for element filter registration.
- `SuperGenius/src/account/GeniusAccount.hpp` — `MakeSignature`, `CheckSignature`, `GetProposedNonce`, `IsValidPublicKey`, `NormalizeAddress`. Used by `RegistrationTransaction::New()` for child signing.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`GeniusTransaction` base class** — `RegistrationTransaction` extends it; inherits hashing (`FillHash`), signing (`MakeSignature`, `CheckSignature`), serialization (`SerializeByteVector`, `SerializeToEmbeddedTransaction`), and deserializer registry (`RegisterDeserializer`). No new tx infrastructure needed.
- **`DAGStruct` proto** — reused verbatim as `dag_struct = 1` in `RegistrationTx`, giving child-signed authenticity + nonce-based account ordering for free.
- **`TransferTransaction` class pattern** — exact template for `RegistrationTransaction`: `New()` factory, private constructor, `SerializeByteVector`, `SerializeToEmbeddedTransaction`, `DeSerializeByteVector`, static `Register()` with `static inline bool registered`.
- **`DeSerializeEmbeddedTransaction` switch** — oneof dispatch pattern at `TransactionManager.cpp:1395-1449`. New `case EmbeddedTransaction::kRegistration:` arm follows identical pattern (serialize sub-message → call deserializer).
- **`RegisterElementFilter` API** — `globaldb.hpp` element filter registration with regex pattern + callback returning `std::nullopt` (accept) or tombstone vector (reject).
- **`GeniusAccount` signing** — `MakeSignature(account)` creates child signature; `CheckSignature()` verifies it. `RegistrationTransaction` reuses both directly.

### Established Patterns
- **Every tx type embeds `DAGStruct dag_struct = 1`** — additive-only proto evolution with fresh field numbers is the norm. New `RegistrationTx` follows this exactly.
- **Deserializer registration** — `TransferTransaction` uses `static Register() + static inline bool registered` for static-init registration; `TransactionManager::DeSerializeEmbeddedTransaction` registers all types in a static lambda. `RegistrationTransaction` adds one new `RegisterDeserializer("registration", ...)` call in the static lambda.
- **Transaction submission** — `SendTransactionItem` writes to CRDT → submits to consensus (`sgns.nonce.v1`). `RegistrationTx` follows the same path with one deviation: CRDT key = `reg/{child_addr}` instead of `tx/{hash}`.
- **CRDT element filters** — `FilterTransaction` (on `tx/`) validates signature + key-collision. `FilterRegistration` (on `reg/`) follows the same pattern with registration-specific gates.

### Integration Points
- `SGTransaction.proto` — append `RegistrationTx` + `RegistrationMetadata` messages (field numbers 8+, additive only).
- `Consensus.proto` `EmbeddedTransaction` oneof — add `SGTransaction.RegistrationTx registration = 8`.
- `TransactionManager::DeSerializeEmbeddedTransaction` — add `case EmbeddedTransaction::kRegistration:` arm.
- `TransactionManager::SendTransactionItem` — divert CRDT write for `RegistrationTx` to `GetBlockChainBase() + "reg/" + child_addr`.
- `TransactionManager::New()` — register `FilterRegistration` on `^/?/bc-{net}/reg/` pattern alongside existing `tx/` and `proof/` filters.
- `RegistrationTransaction` C++ files — placed under `SuperGenius/src/account/`, CMakeLists.txt updated.

### Critical Gaps
- **`GetTransactionFullPath()` hardcodes `"tx/" + GetHash()`** (`GeniusTransaction.hpp:174-177`). `RegistrationTransaction` must NOT use this path. Solution: either override `GetTransactionSpecificPath()` to return a different base (but the method is used differently), or handle the `reg/` path directly at the `SendTransactionItem` CRDT write point by checking tx type. Planner must resolve this.
- **`reg/` namespace is unguarded between Phase 4 and Phase 5** — the minimal `FilterRegistration` accepts sequence=0 and sequence collisions. In the Phase 4 GTest isolated-network scenario this is safe (no external peers), but the planner should note that `reg/` entries written in Phase 4 may be overwritten by Phase 5 nodes running the full filter.
</code_context>

<specifics>
## Specific Ideas

- **User's checkpoint framing of storage path:** "reg/ path lands in Phase 4: divert the CRDT write for RegistrationTx to `GetBlockChainBase() + reg/{child_addr}` now — no registration ever touches tx/. Requires touching `SendTransactionItem`'s shared path logic in Phase 4." This is a deliberate break from the standard `tx/{hash}` pattern — the planner must find the cleanest override point without breaking existing tx types.
- **User's framing of the filter:** "Minimal FilterRegistration in Phase 4 — signature + well-formed only, named FilterRegistration (Phase 5 extends), partial implementation." This establishes a forward-compatible naming convention: Phase 5 researchers add gates to the same method, not a new one.
- **User's framing of the GTest scope:** "Test accept + reject: valid RegistrationTx passes, tampered-signature tx is rejected." Focuses Phase 4 testing on the filter's existence and wiring, not exhaustive gate coverage.
</specifics>

<deferred>
## Deferred Ideas

- **Full `FilterRegistration` with sequence monotonicity** — Phase 5 (RIMPL-04, RIMPL-07). The `FilterRegistration` method is partially implemented in Phase 4; Phase 5 adds the sequence gate to the same method.
- **Malformed-address rejection test** — Phase 5 (TEST-04). Phase 4 GTest only tests signature rejection; malformed-address rejection is deferred with the full filter.
- **CRDT pubsub broadcast of RegistrationTx CID** — Phase 5 (RIMPL-05). Phase 4 writes to local CRDT only; no pubsub notification.
- **Main-node discovery read path** — Phase 5 (RIMPL-06).
- **Multi-node integration test** — Phase 5 (TEST-01 through TEST-04).
- **`GetTransactionFullPath()` refactor or override** — The hardcoded `"tx/"` prefix may need broader refactoring in Phase 5 if the override approach in Phase 4 is temporary. Planner should note this technical debt.
- **Consensus authority gate (`CheckParentChildAuthority`)** — Deferred to later milestone (CONS-01..06). RegistrationTx flows through full consensus in Phase 4/5 but the authority gate is NOT installed.
</deferred>

---

*Phase: 04-Registration Proto & Transaction*
*Context gathered: 2026-07-15*
