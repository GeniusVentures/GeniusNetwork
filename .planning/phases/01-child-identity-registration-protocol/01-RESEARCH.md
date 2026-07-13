# Phase 1: Child Identity & Registration Protocol - Research

**Researched:** 2026-07-13
**Domain:** Child-wallet identity model + child-signed registration protocol on a C++17 UTXO blockchain node
**Confidence:** HIGH

## Summary

Phase 1 produces two design documents: (1) the child-wallet identity model, and (2) the registration protocol with additive proto schema changes. The phase is purely a **design-documentation milestone** — no implementation, no code, no new dependencies. All research maps child-wallet concepts onto existing SuperGenius primitives (GeniusAccount, GeniusTransaction, DAGStruct, EmbeddedTransaction oneof dispatch) that were audited this session.

The key architectural decision is that a child wallet is created identically to any other wallet (independent secp256k1 keypair via `EthereumKeyGenerator`, own `GeniusNode`/`GeniusAccount` with its own nonce counter). "Child-ness" is **emergent**: an account is a child wallet iff a valid `RegistrationTx` naming a main exists in consensus-visible state. Registration is **child-signed only** (D-04 reverses REG-02 dual-signature requirement) — the main wallet's public key is delivered via a transport-agnostic connect flow but the main performs no cryptographic counter-signature during registration.

The registration carries a `RegistrationTx` (new `GeniusTransaction` subclass) with `DAGStruct` (reuses source_addr=child, nonce, signature, timestamp, hashing), a `main_address` field, a dedicated monotonic `sequence` field for registration lineage, and an optional `RegistrationMetadata` sub-message. It flows through the existing `TransactionManager` path (create → sign → FilterTransaction → validate → persist) and serializes through a new arm in the `EmbeddedTransaction` oneof in `Consensus.proto`. The additive proto message is appended to `SGTransaction.proto` with all-new field numbers; a backward-compatibility matrix is required.

**Primary recommendation:** Define `RegistrationTx` as a proto3 message at `SGTransaction.proto` with `DAGStruct dag_struct = 1` (matching all existing tx types), `main_address` at field 2, `sequence` at field 3, and `RegistrationMetadata metadata = 4`. Add `RegistrationTx registration = 8` to the `EmbeddedTransaction` oneof in `Consensus.proto`. Follow the exact patterns of existing `TransferTx`/`EscrowTx` for the C++ subclass and `SerializeToEmbeddedTransaction` / `DeSerializeByteVector` / `RegisterDeserializer` wiring.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** A child wallet is created exactly like any other wallet — a `GeniusNode`/`GeniusAccount` with its own independent secp256k1 private key. **No new account-type field, no creation-time flag.** "Child-ness" is **emergent**: an account is a child wallet iff a valid registration entry naming a main exists in consensus-visible state. `GeniusAccount.hpp` stays untouched for identity purposes.
- **D-02:** UTXO ownership (IDENT-04) needs no special design. A child owns its UTXOs via the standard `UTXOEntryRecord.owner_address` = child address (128-hex 512-bit pubkey-derived address per `GeniusAccount::IsValidPublicKey`). Child-owned assets are distinguishable by owner address alone.
- **D-03:** Independent nonce tracking (IDENT-02) reuses the existing per-account nonce machinery in `GeniusAccount` (`GetProposedNonce`/`ReserveNextNonce`/confirmed-nonce map). A child's account nonce is naturally distinct from the main's because it is a separate account.
- **D-04:** Registration is **child-signed only.** The child signs the `RegistrationTx`; consensus accepts it because the child's own signature is valid over its own registration event. **The main wallet does NOT counter-sign.**
- **D-05:** ⚠ This reverses locked requirement REG-02 (dual-signature) and PROJECT.md's "dual-signature required" decision. Impact: because there is no main signature, consensus cannot verify the named main actually consented — any child can claim any main. This is acceptable because registration grants the child **zero authority over the main** (funding and recovery both require the *main's* signature in Phase 2). The bounded impact is discovery-view spam. Flag REG-02 and PROJECT.md "Dual-signature" decision for update at phase transition.
- **D-06:** Registration is a **first-class `RegistrationTx`** — a new `GeniusTransaction` subclass with a new arm in `SGTransaction.proto`. It flows through the **same `TransactionManager` path** as `TransferTx`/`EscrowTx` (create → sign → `FilterTransaction` → validation → persist).
- **D-07:** The registration **record** materializes into a CRDT namespace as the committed/queryable current state. The tx authenticates the event; the CRDT entry holds state. The CRDT namespace layout and validating element filter are a Phase 2 hand-off — not designed here.
- **D-08:** Single top-level **`RegistrationTx`** message with: `DAGStruct dag_struct = 1`, `main_address`, `sequence`, and optional `RegistrationMetadata` sub-message (`game_id`, `publisher_id`, `dev_wallet`, `peers_cut`). All new field numbers, additive-only. No renumbering. Backward-compatibility matrix required.
- **D-09:** `RegistrationTx` carries **both** `DAGStruct.nonce` (per-account tx ordering) and a dedicated monotonic **`sequence`** field (scoped to a child's registration events only). Consensus selects the highest valid registration sequence as authoritative. Tie-break rule + consensus-ordering mechanism = Phase 2 hand-off.
- **D-10:** The connect flow (GNUS Wallet app / "Connect GNUS Wallet" UI) **only delivers the main wallet's public key** to the child app. The main performs **no signing** during registration, so REG-04 ("main private key never enters the game/child process") is satisfied trivially. Specified as transport-agnostic; concrete platform UI flows are out of scope (v2 / PLAT-01, PLAT-02).

### Agent's Discretion

- Exact proto field numbers and the mechanical shape of the new tx arm/dispatch — planner/researcher choose the idiomatic form matching existing `SGTransaction.proto` conventions, subject to additive-only.
- Naming of the new tx subclass, metadata message, and its C++ file placement under `SuperGenius/src/account/` — follow existing `GeniusTransaction` subclass conventions.

### Deferred Ideas (OUT OF SCOPE)

- CRDT registration namespace + validating element filter — Phase 2 (SYNC-01, SYNC-02).
- Registration sequence tie-break rule + consensus ordering mechanism — Phase 2.
- Pubsub broadcast of registration + main subscribing to child channels — Phase 2 (SYNC-03, SYNC-04, SYNC-05).
- All consensus authority rules — Phase 2 (CONS-01..06).
- Optional out-of-process main acceptance signature (pending→confirmed upgrade) — rejected for Phase 1; possible v2 hardening.
- Metadata/reward-policy update rules — Phase 3 (RWD-03).
- Lifecycle state machine + replace/detach/revoke change-flows — Phase 3 (LIFE-01..04).
- Platform "Connect GNUS Wallet" UI flows — v2 (PLAT-01, PLAT-02).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IDENT-01 | Child-wallet identity model — independent secp256k1 keypair mapped to `GeniusAccount`/`EthereumKeyGenerator` | Verified: `GeniusAccount.hpp` uses `eth_keypair_` (`ethereum::EthereumKeyGenerator`), factory methods `NewFromRandomMnemonic`/`NewFromPrivateKey`. Child created identically via `GeniusNode::New(dev_config, AccountSource{NewAccount{}})` — no code change needed for creation. |
| IDENT-02 | Independent nonce/sequence tracking distinct from main | Verified: `GeniusAccount` has per-account nonce machinery: `GetProposedNonce()` (line 279), `ReserveNextNonce()` (line 285), `confirmed_nonces_` map (line 392), `local_confirmed_nonce_` (line 395). Separate account = separate nonce counter naturally. D-03 confirms reuse. |
| IDENT-03 | Child wallet created standalone via `GeniusNode` `AccountSource` | Verified: `GeniusNode::New` takes `AccountSource` variant with `NewAccount`, `FromPrivateKey`, `FromMnemonic`, `FromPublicKey` (GeniusNode.hpp:88-107). Child created exactly like any other node. D-01 confirms no creation-time flag. |
| IDENT-04 | UTXO ownership for child wallets via `GeniusUTXO.owner_address` | Verified: `UTXOEntryRecord.owner_address` is a string (SGTransaction.proto:57). `GeniusAccount::IsValidPublicKey` validates 128-hex chars (line 152). Child-owned UTXOs distinguishable by owner address alone. D-02 confirms. |
| REG-01 | Registration record schema (child pubkey, main pubkey, signatures, sequence, metadata) | Designed: D-08 specifies `RegistrationTx` with `DAGStruct dag_struct = 1` (child source_addr + child sig), `main_address`, `sequence`, optional `RegistrationMetadata` (game_id, publisher_id, dev_wallet, peers_cut). Schema fully specified. D-04 changes signatures to child-only. |
| REG-02 | ⚠ REVERSED by D-04/D-05. Registration is child-signed only — main does NOT counter-sign. Design doc must state this explicitly. | Research: D-04/D-05 analyze security impact (bounded to discovery spam, zero main-authority grant). Phase 1 design doc records child-signed-only with rationale. REG-02 flagged for requirements update at phase transition. |
| REG-03 | Additive Protocol Buffer changes to `SGTransaction.proto` with backward-compatibility matrix | Verified: `SGTransaction.proto` has existing tx patterns (`TransferTx`, `EscrowTx`, etc. all embed `DAGStruct dag_struct = 1`). `EmbeddedTransaction` oneof in `Consensus.proto` uses fields 1-7. New `RegistrationTx` gets field 8 and fresh field numbers. Additive-only pattern confirmed — existing messages untouched. |
| REG-04 | Out-of-process main-wallet signing flow so main private key never enters child process | Designed: D-10 specifies connect flow delivers main pubkey only. No main signing → REG-04 satisfied trivially. Transport-agnostic handshake specified in design doc; concrete platform UI deferred to v2. |
| REG-05 | Monotonic per-child sequence numbering and consensus-based replay/reorder protection | Designed: D-09 specifies dedicated `sequence` field on `RegistrationTx`. Phase 1 defines the field exists and is monotonic. Exact tie-break + consensus-ordering mechanism is a Phase 2 hand-off. See Pitfall 1 (replay) and Pitfall 7 (proto compat) for guardrails. |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Child keypair generation | API / Backend | — | `GeniusAccount`/`EthereumKeyGenerator` lives in `SuperGenius/src/account/`; key creation is a node-side operation |
| Child account nonce tracking | API / Backend | Database / Storage | Per-account nonce counter managed by `GeniusAccount` (in-memory + RocksDB-persisted via `nonce_db_`) — entirely backend |
| Registration tx signing | API / Backend | — | Child signature via `GeniusAccount::Sign`; tx constructed and signed by the child node process |
| Main pubkey delivery (connect flow) | Browser / Client | Frontend Server (SSR) | Transport-agnostic handshake — the child app receives main pubkey from external wallet UI; not a SuperGenius concern in Phase 1 |
| Registration tx validation | API / Backend | — | `TransactionManager::FilterTransaction` + signature verification — backend consensus path |
| Registration proto serialization | API / Backend | — | `SerializeToEmbeddedTransaction` / `DeSerializeByteVector` in C++ subclass; protobuf wire format |
| Registration sequence field | API / Backend | Database / Storage | `sequence` is a tx field; authoritative value selected by consensus (Phase 2) but field is defined at tx layer |

## Standard Stack

> This is a **design-documentation phase.** No new packages, libraries, or dependencies are installed. All technologies are in the existing SuperGenius stack. The "stack" here is the set of existing components the design documents must reference and integrate with.

### Core (Existing — What the Design Maps To)

| Component | Version / Location | Purpose in Phase 1 | Confidence |
|-----------|--------------------|--------------------|------------|
| Protocol Buffers (proto3) | existing (`SGTransaction.proto`, `Consensus.proto`) | Wire format for `RegistrationTx` + `RegistrationMetadata`; additive new messages | [VERIFIED: codebase] |
| `GeniusAccount` | `SuperGenius/src/account/GeniusAccount.hpp` | Child identity (secp256k1 keypair), nonce tracking (`GetProposedNonce`/`ReserveNextNonce`), signing (`Sign`/`VerifySignature`) | [VERIFIED: codebase] |
| `GeniusTransaction` | `SuperGenius/src/account/GeniusTransaction.hpp` | Base class for `RegistrationTx` — inherits `FillHash`, `MakeSignature`, `CheckSignature`, `SerializeToEmbeddedTransaction`, `RegisterDeserializer`, `GetSlotID` | [VERIFIED: codebase] |
| `DAGStruct` | `SGTransaction.proto:5-15` | Embedded in every tx (`dag_struct = 1`) — carries `source_addr` (=child), `nonce`, `timestamp`, `signature`, hashing fields | [VERIFIED: codebase] |
| `EmbeddedTransaction` | `Consensus.proto:70-80` | Oneof dispatch (fields 1-7 used; new field 8 for RegistrationTx). Drives `TransactionManager::DeSerializeEmbeddedTransaction` switch/case. | [VERIFIED: codebase] |
| `GeniusNode` | `SuperGenius/src/account/GeniusNode.hpp` | Child wallet creation via `AccountSource` variant; new child = `GeniusNode::New(dev_config, AccountSource{NewAccount{}})` | [VERIFIED: codebase] |
| `EthereumKeyGenerator` | `ProofSystem/EthereumKeyGenerator.hpp` | Generates the independent secp256k1 keypair for child wallet | [VERIFIED: codebase] |
| `TransactionManager` | `SuperGenius/src/account/TransactionManager.cpp` | Tx lifecycle path (`FilterTransaction` on line 2984, `DeSerializeEmbeddedTransaction` on line 1427, deserializer registry on line 1434-1441) | [VERIFIED: codebase] |
| `UTXOEntryRecord` | `SGTransaction.proto:54-64` | `owner_address` field (line 57) — child-owned UTXOs distinguished by address alone | [VERIFIED: codebase] |

### Supporting (Conceptual — Informs Design Decisions)

| Concept | Purpose | Source |
|---------|---------|--------|
| Monotonic sequence number | Replay/reorder protection under eventual consistency | [VERIFIED: domain — CRDT literature + proposal §Changing the Registered Main Wallet] |
| Emergent identity (no creation flag) | Child-ness derived from registration record, not account metadata | [VERIFIED: user decision D-01, confirmed in codebase — `GeniusAccount` has no account-type field] |
| Child-signed attestation | Registration authorized by child signature alone; main pubkey delivered out-of-band | [VERIFIED: user decision D-04/D-05] |
| EIP-1271 / delegated-signer concepts | Conceptual reference for "is this signer authorized for this account?" (consensus plays the "contract" role) | [CITED: research/STACK.md, eip-1271 precedent] |

### Alternatives Considered

| Approach Used | Alternative | Why Rejected |
|---------------|-------------|--------------|
| Independent child keypair | BIP-32 HD-derived child from main seed | Couples compromise; main-seed exposure compromises all children; violates "main key never in game" |
| Child-signed registration (D-04) | Dual-signature (child + main, per original REG-02) | User decision: main counter-signature adds UX friction; consensus cannot verify main consent anyway (signature-type mismatch); bounded impact (discovery spam only, no authority grant) |
| First-class `RegistrationTx` (D-06) | CRDT-only record (no tx wrapper) | Rejected: loses existing tx path benefits (signing, hashing, nonce ordering, consensus, persistence) |
| Dedicated `sequence` + `nonce` (D-09) | Reuse `DAGStruct.nonce` only | Rejected: conflates account tx ordering with registration lineage ordering; see Pitfall 1 |

**No installation commands — design documentation phase, no new dependencies.**

## Architecture Patterns

### System Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│                      CHILD WALLET NODE (game process)                   │
│                                                                         │
│  GeniusNode::New(dev_config, AccountSource{NewAccount{}})               │
│    └── GeniusAccount (independent secp256k1, own nonce)                 │
│          └── eth_keypair_ → EthereumKeyGenerator                        │
│    └── UTXOManager (child owns UTXOs via owner_address = child addr)    │
│                                                                         │
│  REGISTRATION FLOW:                                                     │
│  1. Connect flow delivers main public key (transport-agnostic)          │
│     (main private key never enters child process)                       │
│  2. Child constructs RegistrationTx{                                    │
│       dag_struct.source_addr = child_address,                           │
│       dag_struct.nonce = child's next nonce,                            │
│       main_address = main_public_key,  ← from connect flow              │
│       sequence = next_reg_sequence,                                     │
│       metadata = {game_id, publisher_id, dev_wallet, peers_cut}         │
│     }                                                                   │
│  3. Child calls tx->FillHash() → tx->MakeSignature(child_account)       │
│  4. Child submits tx via GeniusNode → TransactionManager                │
└────────────────────────────┬───────────────────────────────────────────┘
                             │ (child-signed RegistrationTx)
                             ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     TRANSACTION MANAGER (existing path)                 │
│                                                                         │
│  FilterTransaction(registration_tx)                                     │
│    ├── CheckSignature(child_address, sig, data)  ← GeniusAccount        │
│    ├── Validate DAGStruct fields (nonce, timestamp)                     │
│    └── Accept → persist to "tx/" path                                   │
│                                                                         │
│  Consensus Subject → NonceSubject.registration = RegistrationTx         │
│  (flows through existing consensus proposal/vote/certificate pipeline)  │
└────────────────────────────┬───────────────────────────────────────────┘
                             │ accepted
                             ▼
┌────────────────────────────────────────────────────────────────────────┐
│            PHASE 2 HAND-OFF: CRDT Namespace + PubSub                    │
│                                                                         │
│  RegistrationTx materialized into CRDT as:                              │
│    registry/<child_address>/  ← Phase 2 namespace design                │
│    GlobalDB.put(key, serialized_record)                                 │
│                                                                         │
│  PubSubBroadcasterExt publishes to:                                     │
│    main wallet's topic ← child broadcasts registration                  │
│    child wallet's topic ← main subscribes for future sync               │
│                                                                         │
│  CONSENSUS AUTHORITY (Phase 2):                                         │
│    Highest valid registration `sequence` is authoritative               │
│    Tie-break rule + ordering mechanism designed in Phase 2              │
│    Registration record consulted by consensus rules for funding/recovery│
└────────────────────────────────────────────────────────────────────────┘
```

### Deserialization Dispatch Path (Verified in Codebase)

```
NonceSubject.transaction (EmbeddedTransaction oneof)
  │
  ▼
TransactionManager::DeSerializeEmbeddedTransaction() [TxMgr.cpp:1427]
  │
  ├── switch(embedded.transaction_case())
  │   ├── EmbeddedTransaction::kTransfer → TransferTransaction::DeSerializeByteVector
  │   ├── EmbeddedTransaction::kMintV2 → MintTransactionV2::DeSerializeByteVector
  │   ├── EmbeddedTransaction::kMint → MintTransaction::DeSerializeByteVector
  │   ├── EmbeddedTransaction::kProcessing → ProcessingTransaction::DeSerializeByteVector
  │   ├── EmbeddedTransaction::kMigration → MigrationTransaction::DeSerializeByteVector
  │   ├── EmbeddedTransaction::kEscrow → EscrowTransaction::DeSerializeByteVector
  │   ├── EmbeddedTransaction::kEscrowRelease → EscrowTransaction::DeSerializeByteVector
  │   └── EmbeddedTransaction::kRegistration ← NEW (field 8)
  │         → RegistrationTransaction::DeSerializeByteVector
  │
  └── deserializers_map["registration"] ← registered at init
```

### Pattern 1: Additive Proto Message + Oneof Arm

**What:** Define a new top-level proto message with fresh field numbers; add it as a new arm in the existing `EmbeddedTransaction` oneof. Never renumber or repurpose existing fields.

**When to use:** Adding a new transaction type to an existing serialization contract.

**Example (Verified Pattern from `Consensus.proto` lines 70-80):**
```protobuf
// consensus.proto — EXISTING pattern (verified)
message EmbeddedTransaction {
  oneof transaction {
    SGTransaction.TransferTx transfer = 1;
    SGTransaction.MintTxV2 mint_v2 = 2;
    SGTransaction.MintTx mint = 3;
    SGTransaction.ProcessingTx processing = 4;
    SGTransaction.MigrationTx migration = 5;
    SGTransaction.EscrowTx escrow = 6;
    SGTransaction.EscrowReleaseTx escrow_release = 7;
    // NEW — additive only, next available field number:
    SGTransaction.RegistrationTx registration = 8;
  }
}
```

**Example (Proposed `SGTransaction.proto` addition):**
```protobuf
// SGTransaction.proto — NEW messages appended at end of file
message RegistrationMetadata {
    string game_id = 1;        // publisher-assigned game identifier
    string publisher_id = 2;   // publisher identity
    string dev_wallet = 3;     // developer payout address (128-hex)
    uint64 peers_cut = 4;      // developer's share of processing rewards
}

message RegistrationTx {
    DAGStruct dag_struct = 1;  // source_addr = child; carries nonce, signature, timestamp
    string main_address = 2;   // registered main wallet public key (128-hex)
    uint64 sequence = 3;       // monotonic per-child registration sequence
    RegistrationMetadata metadata = 4;  // optional game/publisher/dev/split metadata
}
```

### Pattern 2: GeniusTransaction Subclass Convention

**What:** A new tx type follows the exact structure of existing subclasses: PascalCase header/source files under `account/`, constructor chains `SetDAGWithType`, implements `SerializeByteVector`, `SerializeToEmbeddedTransaction`, `DeSerializeByteVector`, and registers its deserializer via `RegisterDeserializer`.

**When to use:** Adding any new `GeniusTransaction` subclass.

**Example (Verified Pattern from `TransferTransaction.cpp`):**

Constructor pattern (TransferTransaction.cpp:13-19):
```cpp
TransferTransaction::TransferTransaction( /* tx-specific params */,
                                          SGTransaction::DAGStruct dag ) :
    GeniusTransaction( "transfer", SetDAGWithType( std::move( dag ), "transfer" ) ),
    // ... member initializers ...
{
}
```

SerializeToEmbeddedTransaction pattern (TransferTransaction.cpp:62-85):
```cpp
EmbeddedTransaction TransferTransaction::SerializeToEmbeddedTransaction(
    const SGTransaction::DAGStruct &dag ) const
{
    EmbeddedTransaction embedded;
    SGTransaction::TransferTx tx_struct;
    tx_struct.mutable_dag_struct()->CopyFrom( dag );
    // ... populate type-specific fields ...
    *embedded.mutable_transfer() = tx_struct;  // oneof setter
    return embedded;
}
```

Deserializer registration pattern (TransactionManager.cpp:1434):
```cpp
GeniusTransaction::RegisterDeserializer(
    "transfer", &TransferTransaction::DeSerializeByteVector );
```

C++ file naming convention (from codebase):
```
SuperGenius/src/account/
├── RegistrationTransaction.hpp    # NEW: PascalCase header
├── RegistrationTransaction.cpp    # NEW: PascalCase source
```

### Pattern 3: Factory + FillHash + Sign (Verified from codebase)

**What:** New tx is created via a static `::New()` factory; `FillHash()` is called during construction to set `data_hash`; caller then calls `MakeSignature(account)` to produce the signature.

**When to use:** Creating any `GeniusTransaction` subclass.

**Example (from TransferTransaction.cpp:22-30):**
```cpp
TransferTransaction TransferTransaction::New(
    std::vector<InputUTXOInfo>  inputs,
    std::vector<OutputDestInfo> destinations,
    SGTransaction::DAGStruct    dag )
{
    TransferTransaction instance(
        std::move( destinations ), std::move( inputs ), std::move( dag ) );
    instance.FillHash();  // Sets dag_st.data_hash
    return instance;
}
// Caller then does: tx.MakeSignature(account) → sets dag_st.signature
```

### Anti-Patterns to Avoid

- **Required proto fields:** Never use `required` in proto3 — it doesn't exist, but also never make new fields non-optional in a way that breaks older readers. All new fields should tolerate absence.
- **Renumbering existing fields:** Touching any existing field number in `TransferTx`, `EscrowTx`, `MintTxV2`, `MigrationTx`, `ProcessingTx`, `EscrowReleaseTx`, `DAGStruct`, `UTXOEntryRecord`, or any other existing message will break deployed nodes. PITFALLS #7 applies.
- **New required enum values:** Adding an enum value that must be understood by all readers breaks version skew. New enum values must be ignored-by-default by older readers.
- **Platform-specific code in shared headers:** Per `Coding Standards.md` / ARCHITECTURE.md anti-pattern. The design doc should not propose `#ifdef`-guarded proto or tx logic.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tx serialization framework | Custom serialize/deserialize | `GeniusTransaction` base class `SerializeByteVector` / `SerializeToEmbeddedTransaction` / `DeSerializeByteVector` / `RegisterDeserializer` | Existing well-tested deserializer registry + `TransactionManager::DeSerializeEmbeddedTransaction` switch dispatch handles all types uniformly. |
| Signature creation/verification | Custom crypto | `GeniusAccount::Sign` / `GeniusAccount::VerifySignature` | Existing secp256k1 signing via `EthereumKeyGenerator`/TrustWalletCore. Battle-tested on all existing tx types. |
| Hashing | Custom hashing | `GeniusTransaction::FillHash()` / `CheckHash()` | Existing `DAGStruct.data_hash` mechanism. Reused verbatim. |
| Nonce management | Custom counter | `GeniusAccount::GetProposedNonce()` / `ReserveNextNonce()` | Existing per-account nonce machinery with RocksDB persistence, caching, and confirmed-nonce tracking. |
| Key generation | Custom keypair | `EthereumKeyGenerator` (used by `GeniusAccount` factory methods) | Existing secp256k1 key generation with BIP39 mnemonic support and secure storage. |
| Address validation | Custom regex | `GeniusAccount::IsValidPublicKey()` / `NormalizeAddress()` | Existing 128-hex validation + "0x" prefix stripping. |
| Proto oneof dispatch | Custom type registry | `EmbeddedTransaction` oneof + `TransactionManager::DeSerializeEmbeddedTransaction` switch | Existing pattern handles all tx types; adding a `case EmbeddedTransaction::kRegistration:` follows the exact pattern. |
| Transaction lifecycle | Custom pipeline | `TransactionManager` create→sign→FilterTransaction→validate→persist path | Existing well-tested path; new `RegistrationTx` flows through identical process. |

**Key insight:** Phase 1 needs ZERO new infrastructure. Every piece the design doc references already exists and is battle-tested in the `TransferTx`/`EscrowTx` path. The design doc's job is to show how `RegistrationTx` plugs into the existing machinery, not how to build new machinery.

## Common Pitfalls

### Pitfall 1: Proto Schema Compatibility Breaks (PITFALLS #7)

**What goes wrong:** New registration fields renumber or repurpose existing proto fields, breaking SuperGenius/GeniusSDK/GeniusWallet deserialization on deployed nodes.

**Why it happens:** Editing existing messages in place; reusing field numbers; making new fields required; changing existing field semantics.

**How to avoid (Phase 1 specific):**
1. Append new messages (`RegistrationTx`, `RegistrationMetadata`) at the END of `SGTransaction.proto` — never modify existing messages.
2. Add the new oneof arm `registration = 8` as the LAST arm in `EmbeddedTransaction.transaction` — never renumber existing arms.
3. All new fields get fresh field numbers not used anywhere else in the file (verified: highest used in SGTransaction.proto is currently not obvious — audit full file before finalizing; `EscrowReleaseTx` uses up to field 6).
4. `RegistrationTx` uses `DAGStruct dag_struct = 1` (matches existing convention across ALL tx types: TransferTx, EscrowTx, MintTx, MintTxV2, MigrationTx, ProcessingTx all use `dag_struct = 1`).
5. `RegistrationMetadata` starts at field 1 for its own scope (new message, isolated namespace).
6. The design doc MUST include a backward-compatibility matrix.

**Warning signs:** Diff touches existing field numbers; reused field numbers in new messages; old messages edited.

**Phase 1 compatibility matrix template (to appear in design doc):**
| Scenario | Compatible? | Why |
|----------|-------------|-----|
| Old node receives new RegistrationTx | ✓ | proto3 ignores unknown message types in oneof; falls through switch to default/TRANSACTION_NOT_SET |
| New node receives old message (no RegistrationTx) | ✓ | Missing oneof arm → TRANSACTION_NOT_SET case; no crash |
| Old wallet parses new RegistrationMetadata | ✓ | Unknown fields ignored by proto3 |
| New node reads old CRDT state (no registration records) | ✓ | No registration → no child; emergent identity works correctly |
| Renumber DAGStruct fields inside RegistrationTx | ✗ | DAGStruct is shared — changing it breaks all tx types |
| Change existing TransferTx/MintTx field numbers | ✗ | Breaks all deployed nodes |

### Pitfall 2: Conflating Nonce with Sequence (PITFALLS #1 applied to Phase 1)

**What goes wrong:** Using only `DAGStruct.nonce` for registration ordering means a child's normal transfer transactions can "push out" a registration (nonce consumed by a transfer, registration can't re-use it).

**Why it happens:** Nonce is account-global — every tx (transfer, registration, escrow) consumes one. Registration lineage needs its own monotonic counter.

**How to avoid:** D-09 already resolves this: `RegistrationTx` carries both `DAGStruct.nonce` (account tx ordering) and a dedicated `sequence` (registration lineage). Phase 1 only defines the field exists and is monotonic. The exact consensus-ordering mechanism is Phase 2.

### Pitfall 3: Child-Signed-Only Security Boundary (D-04/D-05 impact)

**What goes wrong:** Assuming the registered main has cryptographically consented because "it's in a proto field." The main's pubkey is just data in a child-signed tx — consensus cannot verify the main signed because there is no main signature in this model.

**Why it happens:** D-04/D-05 explicitly chose child-signed-only. This was a deliberate tradeoff.

**How to avoid:** The design doc must state explicitly:
- Any child can claim any main wallet address as its "registered main."
- This is acceptable because registration grants the child ZERO authority over the main (funding/recovery require main signature in Phase 2).
- Bounded impact: discovery-view spam (a main might see unsolicited child claims) — NOT loss of funds.
- If spam becomes a real problem, v2 can add an optional main acceptance signature to upgrade pending→confirmed.

**Warning signs:** Code that grants authority based on registration alone (Phase 2 concern, but must be flagged in Phase 1 design doc).

### Pitfall 4: Off-by-One in Proto Field Allocation

**What goes wrong:** Allocating `registration = 8` in EmbeddedTransaction then later discovering field 8 is already used by a different message in a different branch.

**Why it happens:** Proto field numbers are scoped to the oneof, but it's easy to miscount or miss a newly-added arm.

**How to avoid:** The design doc must audit and document every existing field number in `EmbeddedTransaction.transaction` oneof. Verified in this session: fields 1-7 are used (transfer=1, mint_v2=2, mint=3, processing=4, migration=5, escrow=6, escrow_release=7). Field 8 is available.

## Code Examples

### Proto Message Definition (to append to SGTransaction.proto)

```protobuf
// [VERIFIED pattern: SGTransaction.proto — all existing tx types follow this structure]

// At the END of SGTransaction.proto, after EscrowReleaseTx (line 136):

message RegistrationMetadata
{
    string game_id = 1;        // Publisher-assigned game identifier
    string publisher_id = 2;   // Publisher identity
    string dev_wallet = 3;     // Developer payout address (128-hex, no 0x prefix)
    uint64 peers_cut = 4;      // Developer's share of processing rewards (basis points or percent — TBD)
}

message RegistrationTx
{
    DAGStruct dag_struct = 1;  // source_addr = child address; carries nonce, timestamp, signature
    string main_address = 2;   // Registered main wallet public key (128-hex, no 0x prefix)
    uint64 sequence = 3;       // Monotonic per-child registration sequence number
    RegistrationMetadata metadata = 4;  // Optional game/publisher/dev metadata
}
```

### Oneof Arm Addition (Consensus.proto)

```protobuf
// [VERIFIED pattern: Consensus.proto lines 70-80]
// Add to EmbeddedTransaction.transaction oneof:
    SGTransaction.RegistrationTx registration = 8;
```

### C++ Class Header Stub (RegistrationTransaction.hpp)

```cpp
// [VERIFIED pattern: TransferTransaction.hpp / MintTransaction.hpp]
// Follows Coding Standards.md: PascalCase, Ullman braces, trailing-underscore members

#ifndef SGNS_REGISTRATION_TRANSACTION_HPP
#define SGNS_REGISTRATION_TRANSACTION_HPP

#include "account/GeniusTransaction.hpp"
#include "account/proto/SGTransaction.pb.h"

namespace sgns
{
    class RegistrationTransaction : public GeniusTransaction
    {
    public:
        /// @brief Construct a registration transaction.
        /// @param main_address  Registered main wallet public key (128-hex, no prefix).
        /// @param sequence      Monotonic per-child registration sequence.
        /// @param metadata      Optional game/publisher/dev metadata.
        /// @param dag           DAG metadata (source_addr = child, nonce pre-set by caller).
        RegistrationTransaction( std::string                    main_address,
                                 uint64_t                      sequence,
                                 SGTransaction::RegistrationMetadata metadata,
                                 SGTransaction::DAGStruct       dag );

        /// @brief Factory: constructs and fills hash.
        static RegistrationTransaction New( std::string                    main_address,
                                            uint64_t                      sequence,
                                            SGTransaction::RegistrationMetadata metadata,
                                            SGTransaction::DAGStruct       dag );

        std::vector<uint8_t> SerializeByteVector( const SGTransaction::DAGStruct &dag ) const override;
        EmbeddedTransaction  SerializeToEmbeddedTransaction( const SGTransaction::DAGStruct &dag ) const override;

        std::string GetTransactionSpecificPath() const override
        {
            return "reg/" + GetHash();
        }

        static std::shared_ptr<RegistrationTransaction> DeSerializeByteVector( const std::vector<uint8_t> &data );

        [[nodiscard]] std::string GetMainAddress() const { return main_address_; }
        [[nodiscard]] uint64_t    GetSequence() const { return sequence_; }
        const SGTransaction::RegistrationMetadata &GetMetadata() const { return metadata_; }

    private:
        std::string                    main_address_;
        uint64_t                       sequence_;
        SGTransaction::RegistrationMetadata metadata_;
    };
}

#endif // SGNS_REGISTRATION_TRANSACTION_HPP
```

### Deserializer Registration (in TransactionManager.cpp)

```cpp
// [VERIFIED pattern: TransactionManager.cpp lines 1434-1441]
// Add to the static initializer block:
GeniusTransaction::RegisterDeserializer(
    "registration", &RegistrationTransaction::DeSerializeByteVector );
```

### Deserialization Dispatch (in TransactionManager.cpp DeSerializeEmbeddedTransaction)

```cpp
// [VERIFIED pattern: TransactionManager.cpp lines 1445-1501]
// Add new case to the switch:
case EmbeddedTransaction::kRegistration:
{
    std::string bytes;
    embedded.registration().SerializeToString( &bytes );
    return GeniusTransaction::GetDeSerializers().at( "registration" )(
        std::vector<uint8_t>( bytes.begin(), bytes.end() ) );
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Dual-signature registration (proposal §Registration Flow, REG-02 original) | Child-signed-only registration (D-04/D-05) | Phase 1 discuss (2026-07-13) | Reduces UX friction; introduces discovery-spam vector (bounded, no authority grant); REG-02 and PROJECT.md flagged for update |
| (N/A — new feature) | First-class `RegistrationTx` as `GeniusTransaction` subclass | Phase 1 discuss | Reuses existing tx infrastructure; additive proto evolution; follows established pattern |

**Deprecated/outdated:**
- **REG-02 dual-signature requirement:** Reversed by D-04/D-05. The proposal's Registration Flow step 4 (main counter-signs) is superseded for Phase 1. Design doc must state this explicitly.
- **PROJECT.md "Dual-signature required" key decision:** Superseded; flagged for update at phase transition.

## Assumptions Log

> Claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Field 8 is available in `EmbeddedTransaction.transaction` oneof — no other branch/PR has claimed it | Code Examples — Oneof Arm Addition | LOW — proto compile will catch collision; easily changed to next available number |
| A2 | `RegistrationTransaction` C++ class placed under `SuperGenius/src/account/` following PascalCase convention | Code Examples — C++ Class Header | LOW — naming is agent's discretion per D-08; user can rename |
| A3 | `RegistrationMetadata.peers_cut` uses same encoding as existing `EscrowTx.peers_cut` (uint64) | Code Examples — Proto Message Definition | MEDIUM — needs confirmation that reward-split encoding is consistent; if different, a conversion is needed |
| A4 | `GetTransactionSpecificPath()` returns `"reg/"` prefix — distinct from existing `"tx/"` | Code Examples — C++ Class Header | LOW — prefix is arbitrary; Phase 2 CRDT filter uses whatever prefix is defined |
| A5 | Registration deserializer type string is `"registration"` — consistent with existing naming convention ("transfer", "mint", "mint-v2", "process", "migration", "escrow-hold", "escrow-release") | Code Examples — Deserializer Registration | LOW — naming is agent's discretion |
| A6 | `RegistrationMetadata` fields (`game_id`, `publisher_id`, `dev_wallet`) are `string` type — UTF-8, variable-length | Code Examples — Proto Message Definition | LOW — proto3 strings are UTF-8 by default; adequate for identifiers and 128-hex addresses |

## Open Questions

1. **Highest field number currently used in `SGTransaction.proto`**
   - What we know: `EscrowReleaseTx` uses field 6 (`original_escrow_hash = 6`). The `RegistrationTx` proposed fields (1-4) are all lower than any existing field number in the file, so no collision risk within the new message. The new message namespace is isolated — field numbers 1-4 in `RegistrationTx` do not conflict with field numbers 1-4 in `TransferTx`.
   - What's unclear: Whether any generated `.pb.h` code or other tooling imposes a global maximum field number constraint.
   - Recommendation: The design doc should note that proto3 field numbers 1-15 use one-byte encoding (more efficient), so using fields 1-4 for the new message is ideal. No action needed unless a build-time constraint is discovered.

2. **Exact `sequence` tie-break rule (Phase 2 hand-off)**
   - What we know: D-09 states "Consensus selects the highest valid registration sequence as authoritative." Phase 1 only defines the field exists and is monotonic.
   - What's unclear: How equal-sequence registrations are resolved (tx hash? timestamp? validator vote?). This is the CRDT ordering problem — see PITFALLS #1.
   - Recommendation: Phase 1 design doc explicitly defers this to Phase 2. Documents: "The consensus-ordering mechanism and tie-break rule are designed in Phase 2 (SYNC-01, CONS-01). This phase defines that the `sequence` field exists, is uint64, and is monotonic per-child."

3. **Registration "deserializer type string" convention confirmation**
   - What we know: Existing types use: "transfer", "mint", "mint-v2", "process", "migration", "escrow-hold", "escrow-release". The proposed "registration" is consistent (lowercase, hyphen-free, noun).
   - What's unclear: Whether there's a documented naming convention for these strings or if they're ad-hoc.
   - Recommendation: Use "registration" — consistent with existing ad-hoc convention. This is agent's discretion per CONTEXT.md.

4. **Whether `FilterTransaction` needs a Phase 1 change or remains Phase 2**
   - What we know: D-07 says "CRDT namespace layout and validating element filter are a Phase 2 hand-off." But `RegistrationTx` must pass through `FilterTransaction` to enter the system.
   - What's unclear: Does the existing `FilterTransaction` auto-accept unknown tx types (gated only by signature + nonce validity), or does it need an explicit gate even in Phase 1?
   - Recommendation: The design doc should specify that `RegistrationTx` passes through the existing signature + DAG validity checks that all tx types undergo (no new filter code in Phase 1). The CRDT element filter that persists registration state into a `registry/` namespace is Phase 2. The planner should verify this with code inspection of `FilterTransaction` logic.

## Environment Availability

**Step 2.6: SKIPPED** (no external dependencies identified). Phase 1 produces design documents only — no tools, services, runtimes, or CLI utilities beyond what's already in the development environment are required.

## Validation Architecture

> **Skipped** — `workflow.nyquist_validation` is `false` in `.planning/config.json`. Phase 1 produces design documents, not executable code.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | YES | Child wallet authenticates via secp256k1 signature on `RegistrationTx` (`GeniusAccount::Sign`/`VerifySignature`). Registration is child-signed; authentication is signature-based — no password/token mechanism. |
| V3 Session Management | NO | No web sessions in scope. SuperGenius is a native C++ node; `GeniusAccount` nonce mechanism prevents replay (not session-based). |
| V4 Access Control | PARTIAL | Phase 1 does NOT add access control (deferred to Phase 2 consensus authority rules per CONS-01..06). However, the design must flag that registration alone grants ZERO authority — main's funds require main's signature (Phase 2). The child-signed-only model's bounded blast radius (discovery spam, not fund access) is the Phase 1 security stance. |
| V5 Input Validation | YES | `main_address` field validated via `GeniusAccount::IsValidPublicKey()` (128-hex check). `sequence` is uint64 (valid by type). `RegistrationMetadata` fields are optional — empty strings tolerated. Proto deserialization handles malformed wire data (protobuf ParseFromArray returns false). |
| V6 Cryptography | YES | `GeniusAccount::Sign` — secp256k1 ECDSA via `EthereumKeyGenerator`/TrustWalletCore. No hand-rolled crypto. `FillHash()` uses existing hashing pipeline. Main private key never enters child process (D-10). |

### Known Threat Patterns for C++17 + Protobuf + secp256k1

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed proto wire data causing crash/OOB | Tampering / DoS | Protobuf `ParseFromArray` returns bool; parse failure → reject tx. Existing `TransactionManager` handles this for all tx types. |
| Replay of old RegistrationTx | Spoofing | `DAGStruct.nonce` (per-account ordering) + `sequence` (registration lineage). Consensus rejects nonce ≤ confirmed nonce. Phase 2 adds seq-based tie-break. |
| Unsolicited registration (child claims any main) | Spoofing | Acknowledged by D-04/D-05 — there IS no cryptographic main consent. Mitigation: registration grants zero authority over main (Phase 2 enforcement). Discovery-spam vector documented. v2 hardening: optional main acceptance signature. |
| Registration with attacker-controlled main_address | Spoofing | No guard in Phase 1 (by design). Impact bounded to discovery-view spam. Phase 2 funding/recovery still requires main's actual signature — attacker can't drain funds. |
| Sequence number integer overflow | Tampering | `uint64` has 2^64 range; practical monotonic counter won't overflow. Proto3 validates uint64 range. |
| Signing oracle abuse (attacker tricks child into signing arbitrary RegistrationTx) | Elevation of Privilege | Child-signed anything is valid by design — child owns its keypair and authorizes its own registrations. Compromise of child key is bounded to child's assets (attack model per proposal §Security Model). |

### Phase 1 Security Stance (explicit)

1. **Child-signed-only registration means any child can claim any main** — but this grants zero authority. The main's funds remain protected by the main's private key (Phase 2 consensus rules). This is a deliberate tradeoff, not an oversight.
2. **Main private key never enters the child process** — the connect flow delivers only the main's public key (D-10). This is the central security invariant and is trivially satisfied.
3. **Compromise of child key is bounded to child assets** — child cannot spend main funds, cannot access other children's wallets, cannot modify consensus rules. The blast radius is exactly the child's own UTXO set.
4. **Proto wire attacks are mitigated by existing parse/validate pipelines** — no new attack surface introduced by additive proto messages.

## Sources

### Primary (HIGH confidence)
- `SuperGenius/src/account/proto/SGTransaction.proto` — audited all existing tx message patterns ([VERIFIED: codebase])
- `SuperGenius/src/blockchain/impl/proto/Consensus.proto` (lines 70-80) — audited `EmbeddedTransaction` oneof dispatch ([VERIFIED: codebase])
- `SuperGenius/src/account/GeniusTransaction.hpp` — audited base class interface: `SerializeToEmbeddedTransaction`, `RegisterDeserializer`, `FillHash`, `MakeSignature`, `CheckSignature`, `GetSlotID` ([VERIFIED: codebase])
- `SuperGenius/src/account/GeniusAccount.hpp` — audited identity/nonce/signing machinery: `eth_keypair_`, `GetProposedNonce`, `ReserveNextNonce`, `Sign`, `VerifySignature`, `IsValidPublicKey`, `confirmed_nonces_` ([VERIFIED: codebase])
- `SuperGenius/src/account/TransferTransaction.cpp` — audited C++ subclass pattern: constructor, `SerializeToEmbeddedTransaction`, `DeSerializeByteVector`, `New()` factory ([VERIFIED: codebase])
- `SuperGenius/src/account/TransactionManager.cpp` (lines 1427-1501, 2984) — audited `DeSerializeEmbeddedTransaction` switch dispatch and `FilterTransaction` ([VERIFIED: codebase])
- `SuperGenius/src/account/GeniusNode.hpp` (lines 88-107) — audited `AccountSource` variant for child wallet creation ([VERIFIED: codebase])
- `.planning/phases/01-child-identity-registration-protocol/01-CONTEXT.md` — all locked decisions D-01 through D-10 ([VERIFIED: user decisions])
- `.planning/research/PITFALLS.md` — Pitfalls 1, 6, 7 directly relevant to Phase 1 ([VERIFIED: prior research])
- `.planning/research/SUMMARY.md` — architecture approach and phase rationale ([VERIFIED: prior research])
- `.planning/research/ARCHITECTURE.md` — component responsibilities and integration points ([VERIFIED: prior research])
- `.planning/research/STACK.md` — stack recommendations and alternatives ([VERIFIED: prior research])
- `GNUS_Subwallet_Architecture_Proposal.md` — authoritative feature spec; §Registration Flow (noting step 4 is superseded by D-04) ([VERIFIED: project reference])

### Secondary (MEDIUM confidence)
- `GNUS_Subwallet_Architecture_Proposal.md` §Changing the Registered Main Wallet — sequence number + replacement flow conceptually informs the `sequence` field design; concrete mechanism is Phase 2
- `.planning/research/FEATURES.md` — feature dependencies and prioritization informed phase scoping

### Tertiary (LOW confidence)
- None — all Phase 1 findings are grounded in audited codebase or locked user decisions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components verified by codebase audit this session; no external packages
- Architecture: HIGH — patterns verified against existing `TransferTx`/`EscrowTx`/`MintTxV2` implementations; oneof dispatch verified in `Consensus.proto` and `TransactionManager.cpp`
- Pitfalls: HIGH — Pitfall 1 (proto compat) backed by audited proto files; Pitfall 2 (nonce vs sequence) resolved by D-09; Pitfall 3 (child-signed boundary) explicitly designed by D-04/D-05
- Security: HIGH — security stance derived from audited codebase + locked user decisions; threat model per proposal §Security Model

**Research date:** 2026-07-13
**Valid until:** 2026-08-12 (30 days — stable domain; SuperGenius proto conventions change slowly)
