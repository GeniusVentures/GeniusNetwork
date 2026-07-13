# Registration Protocol

**Version:** 1.0
**Status:** Draft — Phase 01, Plan 01-02
**Date:** 2026-07-13

## 1. Overview

The `RegistrationTx` is a first-class `GeniusTransaction` subclass that records a child wallet's intent to register under a main wallet. It is **child-signed-only** (per D-04/D-05 — the main wallet does NOT counter-sign). The message carries the child's DAG metadata (`source_addr`, `nonce`, `signature`), the main wallet's public key (delivered via the connect flow, see §5.5), a monotonic registration sequence number, and optional game/publisher/dev metadata.

### First-Class Transaction

Per D-06, `RegistrationTx` flows through the existing `TransactionManager` path identically to `TransferTx`, `EscrowTx`, and all other transaction types:

```
create (RegistrationTransaction::New factory)
  → FillHash
  → MakeSignature (child signs)
  → FilterTransaction
  → validation
  → persist
```

It reuses `DAGStruct` hashing, signing, nonce ordering, and the existing tx persistence path. No new transaction infrastructure is needed.

### CRDT Hand-Off

Per D-07, after acceptance, the `RegistrationTx` materializes into a CRDT namespace as committed/queryable state. The CRDT namespace layout and validating element filter are designed in Phase 2 — this document defines the tx that carries the registration event, not the CRDT entry that holds the persisted state.

### Traceability

REG-01 (registration record schema) is satisfied by sections 1–3 of this document. The full proto schema is specified in §2, the oneof dispatch in §3, and the C++ subclass in §4.

### Design Authority

This document is grounded in:

- **`GNUS_Subwallet_Architecture_Proposal.md`** §Registration Flow — authoritative feature requirements (note: proposal step 4, main counter-signs, is superseded by D-04/D-05)
- **`SuperGenius/src/account/proto/SGTransaction.proto`** — where the additive proto messages are appended
- **`SuperGenius/src/blockchain/impl/proto/Consensus.proto`** — where the `EmbeddedTransaction` oneof arm is added
- **`SuperGenius/src/account/GeniusTransaction.hpp`** — base class interface for the new `RegistrationTransaction` subclass
- **Phase 01 Context (`01-CONTEXT.md`)** — decisions D-04 through D-10 define the registration model
- **Phase 01 Identity Model (`docs/child-wallet-identity-model.md`)** — defines the child keypair, nonce, UTXO ownership that RegistrationTx builds upon

---

## 2. Proto Schema — SGTransaction.proto Additions

Two new messages are appended at the **end** of `SGTransaction.proto` (after `EscrowReleaseTx` at line 136). No existing message is modified. No existing field number is renumbered or repurposed.

### Code Audit — Current File State

`SuperGenius/src/account/proto/SGTransaction.proto` (136 lines) was audited on 2026-07-13. Key findings:

| Item | Finding |
|------|---------|
| All existing tx types | `TransferTx`, `ProcessingTx`, `MintTx`, `MintTxV2`, `MigrationTx`, `EscrowTx`, `EscrowReleaseTx` |
| Shared DAG convention | Every tx type embeds `DAGStruct dag_struct = 1` (lines 83, 89, 99, 106, 114, 122, 130) |
| Highest field in `EscrowReleaseTx` | `original_escrow_hash = 6` (line 135) |
| File ends at | Line 136 (closing `}` of `EscrowReleaseTx`) |
| `DAGStruct` definition | Lines 5–15: `type = 1`, `previous_hash = 2`, `source_addr = 3`, `nonce = 4`, `timestamp = 5`, `uncle_hash = 6`, `data_hash = 7`, `signature = 8` — **untouched** |

### RegistrationMetadata

```protobuf
// Appended at end of SGTransaction.proto, after EscrowReleaseTx message

message RegistrationMetadata {
    string game_id = 1;        // publisher-assigned game identifier (optional)
    string publisher_id = 2;   // publisher identity (optional)
    string dev_wallet = 3;     // developer payout address, 128-hex, no "0x" prefix (optional)
    uint64 peers_cut = 4;      // developer's share of processing rewards, uint64 (optional)
}
```

**Field-by-field explanation:**

| Field | Type | Number | Purpose |
|-------|------|--------|---------|
| `game_id` | `string` | 1 | Publisher-assigned game identifier. Optional — empty string in proto3 default. Allows the main wallet to group children by game. |
| `publisher_id` | `string` | 2 | Publisher identity. Optional — empty string in proto3 default. Enables publisher-level aggregation and reputation. |
| `dev_wallet` | `string` | 3 | Developer payout address. 128 hex characters, no "0x" prefix, validated via `GeniusAccount::IsValidPublicKey`. Optional — a child may register without specifying a developer wallet. |
| `peers_cut` | `uint64` | 4 | Developer's share of processing rewards. Uses the same encoding as `EscrowTx.peers_cut` (`SGTransaction.proto:126`). Optional — 0 in proto3 default means no developer cut. Authenticated update rules (RWD-03) are Phase 3. |

All fields are proto3 `optional` by default (empty string for `string`, 0 for `uint64`). A child may register without metadata; metadata may be added or changed in a later registration with an incremented `sequence`.

### RegistrationTx

```protobuf
// Appended at end of SGTransaction.proto, after RegistrationMetadata

message RegistrationTx {
    DAGStruct dag_struct = 1;              // source_addr = child address; carries nonce, timestamp, signature
    string main_address = 2;               // registered main wallet public key, 128-hex, no "0x" prefix
    uint64 sequence = 3;                   // monotonic per-child registration sequence number
    RegistrationMetadata metadata = 4;     // optional game/publisher/dev metadata sub-message
}
```

**Field-by-field explanation:**

| Field | Type | Number | Purpose |
|-------|------|--------|---------|
| `dag_struct` | `DAGStruct` | 1 | Reuses the shared `DAGStruct` message used by ALL existing tx types (`TransferTx`, `EscrowTx`, `MintTx`, `MintTxV2`, `MigrationTx`, `ProcessingTx` all use `DAGStruct dag_struct = 1`). The `source_addr` field carries the child wallet's address. The `nonce` field carries the child's per-account nonce (per IDENT-02). The `signature` field carries the child's ECDSA signature over the `data_hash` (per D-04). The `timestamp` and hashing fields (`previous_hash`, `uncle_hash`, `data_hash`) work identically to all other tx types. |
| `main_address` | `string` | 2 | The main wallet's public key, supplied via the connect flow (see §5.5). 128 hex characters, no "0x" prefix, validated via `GeniusAccount::IsValidPublicKey`. This field is **data** in the child-signed tx — consensus does NOT verify that the main signed this value (per D-04/D-05). |
| `sequence` | `uint64` | 3 | Monotonic per-child registration counter. Separate from `DAGStruct.nonce` (which is account-global per-tx ordering). `sequence` tracks registration lineage: the first registration = 1, replacements increment the sequence. The tie-break rule for equal-sequence registrations is a Phase 2 hand-off (see §6). This document defines that the field exists and is `uint64` monotonic. |
| `metadata` | `RegistrationMetadata` | 4 | Optional `RegistrationMetadata` sub-message. All fields within are optional (proto3 default = empty string / 0). A child may register without metadata; metadata may be added or changed in a later registration with an incremented `sequence`. The authenticated update rules for `dev_wallet`/`peers_cut` are Phase 3 (RWD-03). |

### Additive-Only Guarantee

- All field numbers (1–4 in `RegistrationTx`, 1–4 in `RegistrationMetadata`) are **fresh** within their respective message scopes. No existing field number in any existing message is renumbered or repurposed.
- `DAGStruct` is **referenced** (not duplicated), so its internal field numbers (1–8) are unchanged.
- The new messages are **appended** after the last existing message (`EscrowReleaseTx`). No existing message's field order, numbering, or semantics is altered.
- Proto3 field numbers 1–4 use one-byte wire encoding — the most compact representation.

---

## 3. Oneof Dispatch — Consensus.proto EmbeddedTransaction

A single additive line is inserted in the `EmbeddedTransaction.transaction` oneof in `Consensus.proto`.

### Code Audit — EmbeddedTransaction Oneof

`SuperGenius/src/blockchain/impl/proto/Consensus.proto` lines 70–80 was audited on 2026-07-13:

```protobuf
message EmbeddedTransaction {
  oneof transaction {
    SGTransaction.TransferTx transfer = 1;           // verified present
    SGTransaction.MintTxV2 mint_v2 = 2;              // verified present
    SGTransaction.MintTx mint = 3;                   // verified present
    SGTransaction.ProcessingTx processing = 4;       // verified present
    SGTransaction.MigrationTx migration = 5;         // verified present
    SGTransaction.EscrowTx escrow = 6;               // verified present
    SGTransaction.EscrowReleaseTx escrow_release = 7;// verified present
  }
}
```

**Audit result:** Fields 1 through 7 are all in use. Field **8** is the next genuinely available field number.

### Oneof Addition

```protobuf
message EmbeddedTransaction {
  oneof transaction {
    SGTransaction.TransferTx transfer = 1;
    SGTransaction.MintTxV2 mint_v2 = 2;
    SGTransaction.MintTx mint = 3;
    SGTransaction.ProcessingTx processing = 4;
    SGTransaction.MigrationTx migration = 5;
    SGTransaction.EscrowTx escrow = 6;
    SGTransaction.EscrowReleaseTx escrow_release = 7;
    SGTransaction.RegistrationTx registration = 8;   // ← NEW, additive only
  }
}
```

Single line inserted after `escrow_release = 7`. No existing oneof arm is renumbered, removed, or modified.

### Deserialization Dispatch

Proto3 auto-generates `EmbeddedTransaction::kRegistration` when `registration = 8` is added to the oneof. The `TransactionManager::DeSerializeEmbeddedTransaction` switch statement adds a `case EmbeddedTransaction::kRegistration:` following the pattern of all existing cases (see §4 for the exact C++ dispatch code).

### Additive-Only Guarantee

- **Field audit recorded:** Fields 1–7 verified used in `EmbeddedTransaction.transaction` oneof at `Consensus.proto:71-78`. Field 8 is genuinely available.
- **No existing oneof arm is renumbered or removed.** The addition is purely additive.
- **Old nodes receive new RegistrationTx:** proto3 ignores unknown message types in a oneof — the unknown arm is treated as if it were not set. Deserialization falls through the `DeSerializeEmbeddedTransaction` switch to the `TRANSACTION_NOT_SET` default case, returning `std::errc::invalid_argument`. The old node does not crash, corrupt state, or misinterpret the message.
- **New nodes receive old messages:** The `EmbeddedTransaction.transaction_case()` returns `TRANSACTION_NOT_SET` when no known oneof arm matches. The new node's switch falls through to the default case, identical to existing handling for unknown/empty transactions.

### Traceability

REG-03 (additive proto changes with backward-compatibility) is satisfied by sections 2–3 (proto changes defined) and the full backward-compatibility matrix in §7.

---

## 4. C++ Subclass — RegistrationTransaction

The `RegistrationTransaction` class is a new `GeniusTransaction` subclass under `SuperGenius/src/account/`, following the exact conventions of the existing `MintTransaction` (simplest subclass — no UTXOs, just scalar + string fields).

### File Placement

```
SuperGenius/src/account/
├── RegistrationTransaction.hpp    # PascalCase header
├── RegistrationTransaction.cpp    # PascalCase source
```

Following the PascalCase file naming convention used by all existing transaction subclasses (`MintTransaction`, `TransferTransaction`, `EscrowTransaction`, `ProcessingTransaction`, `MigrationTransaction`).

### Class Structure

**Inheritance:** `class RegistrationTransaction final : public GeniusTransaction`

**Constructor:** Chains `GeniusTransaction("registration", SetDAGWithType(std::move(dag), "registration"))` — following the exact pattern of `MintTransaction::MintTransaction` at `MintTransaction.cpp:11-20`. The type string `"registration"` is consistent with the existing lowercase, hyphen-free convention (`"mint"`, `"transfer"`, `"escrow-hold"`, `"escrow-release"`).

**Member variables** (trailing underscore per Coding Standards.md):

| Member | Type | Purpose |
|--------|------|---------|
| `main_address_` | `std::string` | The registered main wallet public key (128-hex, no prefix). Set via `set_main_address()` in serialization. |
| `sequence_` | `uint64_t` | Monotonic per-child registration sequence. Set via `set_sequence()` in serialization. |
| `metadata_` | `SGTransaction::RegistrationMetadata` | Optional game/publisher/dev metadata sub-message. Set via `mutable_metadata()->CopyFrom()` in serialization. |

### Key Methods

**`New()` factory:** Static factory method that constructs, calls `FillHash()`, and returns by value (not `shared_ptr`). Following the `MintTransaction::New` pattern (`MintTransaction.cpp:85-93`):

```cpp
static RegistrationTransaction New(
    std::string                    main_address,
    uint64_t                       sequence,
    SGTransaction::RegistrationMetadata metadata,
    SGTransaction::DAGStruct       dag );
```

The caller then calls `tx.MakeSignature(*child_account)` to produce the child's secp256k1 ECDSA signature over the `data_hash`.

**`SerializeToEmbeddedTransaction`:** Creates an `SGTransaction::RegistrationTx` proto struct, copies `dag_struct`, calls `set_main_address()`, `set_sequence()`, `mutable_metadata()->CopyFrom()`, then `*embedded.mutable_registration() = tx_struct`. Follows the `MintTransaction::SerializeToEmbeddedTransaction` pattern (`MintTransaction.cpp:41-52`) with string field serialization modeled on `EscrowTransaction` (`EscrowTransaction.cpp:60-62`):

- `tx_struct.set_main_address(main_address_)` — mirrors `set_dev_addr(dev_addr_)`
- `tx_struct.set_sequence(sequence_)` — mirrors `set_peers_cut(peers_cut_)`
- `*tx_struct.mutable_metadata()->CopyFrom(metadata_)` — proto3 sub-message copy
- `*embedded.mutable_registration() = tx_struct` — sets the `registration = 8` oneof arm

**`SerializeByteVector`:** Same proto population as `SerializeToEmbeddedTransaction`, then `SerializeToArray` into `std::vector<uint8_t>`. Follows the `MintTransaction::SerializeByteVector` pattern (`MintTransaction.cpp:22-39`).

**`DeSerializeByteVector` (static):** Parses `SGTransaction::RegistrationTx` from byte vector via `ParseFromArray`. Extracts `main_address()`, `sequence()`, `metadata()` from the parsed proto. Returns `std::make_shared<RegistrationTransaction>(...)` on success. Parse failure → `std::cerr` + return `nullptr` — consistent with all existing subclasses (`MintTransaction.cpp:54-68`, `EscrowTransaction.cpp:102-139`).

**`GetTransactionSpecificPath()`:** Returns `"reg/" + GetHash()` — distinct from the existing `"tx/"` prefix used by `GeniusTransaction::GetTransactionFullPath()`. This separates registration storage from general transaction storage. Alternatively, may follow the `GetType()` pattern returning `"registration"` — the exact prefix is at implementer's discretion.

**Static `Register()`:** Calls `RegisterDeserializer("registration", &RegistrationTransaction::DeSerializeByteVector)` with inline `static bool registered = Register()` — following the exact pattern of `MintTransaction.hpp:105-114`.

### Deserializer Registration and Dispatch

Two insertion points in `TransactionManager.cpp`:

**1. Static initializer block** (`TransactionManager.cpp` line ~1434): Add one line to the existing deserializer registration lambda:

```cpp
GeniusTransaction::RegisterDeserializer(
    "registration", &RegistrationTransaction::DeSerializeByteVector );
```

Appended after the `escrow-release` entry. The type string `"registration"` must match the string in the constructor chain.

**2. `DeSerializeEmbeddedTransaction` switch** (`TransactionManager.cpp` line ~1445): Add a new case following the exact pattern of all existing cases:

```cpp
case EmbeddedTransaction::kRegistration:
{
    std::string bytes;
    embedded.registration().SerializeToString( &bytes );
    return GeniusTransaction::GetDeSerializers().at( "registration" )(
        std::vector<uint8_t>( bytes.begin(), bytes.end() ) );
}
```

`EmbeddedTransaction::kRegistration` is auto-generated by proto3 when `registration = 8` is added to the oneof. `embedded.registration()` returns `const SGTransaction::RegistrationTx&` (auto-generated accessor). The `default: case TRANSACTION_NOT_SET: return std::errc::invalid_argument` already handles old nodes gracefully — no RegistrationTx → falls through.

### Design Rule: No New Infrastructure

Per D-06, `RegistrationTransaction` flows through the existing `TransactionManager` path identically to `TransferTx`/`EscrowTx`. No new transaction infrastructure is needed:

- `GeniusTransaction` base class provides `FillHash()`, `MakeSignature()`, `CheckSignature()`, `GetSlotID()` (`GeniusTransaction.hpp:243-277`)
- `TransactionManager` provides `FilterTransaction`, validation, and persistence path
- `RegisterDeserializer` / `GetDeSerializers()` provide the type-dispatch registry
- `DAGStruct` provides nonce ordering, hashing, and signature slots

### Traceability

REG-01 (schema → C++ mapping) and REG-03 (proto → deserializer dispatch) are reinforced by the C++ subclass design: the proto messages defined in §2 have a concrete deserialization path through `RegistrationTransaction::DeSerializeByteVector` → `RegisterDeserializer("registration", ...)` → `TransactionManager::DeSerializeEmbeddedTransaction` → `case EmbeddedTransaction::kRegistration`.

---

## 5. Signing Protocol — Child-Signed-Only (REG-02 Reversal)

This section documents the signing protocol, the REG-02 reversal (D-04/D-05), and the connect flow for main-pubkey delivery. It is the security architecture statement for registration.

### 5.1 What REG-02 Originally Required

The original requirement REG-02 (from `.planning/REQUIREMENTS.md`) states:

> "Design specifies the dual-signature registration protocol requiring both child and main signatures over the canonical record."

The original proposal (`GNUS_Subwallet_Architecture_Proposal.md` §Registration Flow, step 4) assumed that the main wallet counter-signs the registration record to cryptographically prove consent.

**This requirement is ⚠ REVERSED by decisions D-04 and D-05 (`01-CONTEXT.md`).** Registration is child-signed-only. Flag REG-02 and PROJECT.md "Dual-signature required" key decision for update at phase transition.

### 5.2 The Child-Signed-Only Model

The child wallet constructs a `RegistrationTx` using the `RegistrationTransaction::New()` factory, which calls `FillHash()` to compute the `data_hash` over the serialized transaction content. The child then calls `tx.MakeSignature(*child_account)` to produce a secp256k1 ECDSA signature over the `data_hash` using the child's own private key (`GeniusAccount::Sign` at `GeniusAccount.hpp:216`).

Consensus validates the signature via `GeniusAccount::VerifySignature(child_address, sig, data)` (`GeniusAccount.hpp:207`) — the same verification path used by all existing transaction types. The main wallet performs **no cryptographic operation** during registration.

The main wallet's public key (`main_address` field) is supplied to the child process via the connect flow (see §5.5). It is **data** in the child-signed tx — consensus does NOT verify that the main wallet signed this transaction or that the named main consented to the registration.

**The entire registration is:**

```
1. Child obtains main_address from connect flow (transport-agnostic pubkey delivery)
2. Child constructs RegistrationTx(main_address, sequence, metadata, dag)
3. Child calls tx.FillHash() → data_hash computed
4. Child calls tx.MakeSignature(*child_account) → secp256k1 ECDSA signature
5. Child submits through existing TransactionManager path
6. Consensus validates: child's signature, child's nonce, DAG integrity
```

No step involves the main wallet's private key or a main-wallet signing operation.

### 5.3 Security Impact Analysis (per D-05)

The child-signed-only model has a specific, bounded security impact. This section documents it explicitly.

#### 5.3.1 Any Child Can Claim Any Main

Because there is no main signature, consensus **cannot cryptographically verify** that the named main wallet actually consented to the registration. A malicious child could construct a `RegistrationTx` claiming **any** main wallet address as its `main_address` — the child simply sets `main_address` to the target main's public key (which is publicly visible on the ledger) and signs with its own key.

#### 5.3.2 Impact Is Bounded to Discovery Spam

This is acceptable because registration grants the child **zero authority** over the main wallet:

| Capability | Requires | Phase |
|------------|----------|-------|
| Main→child fund | Main's signature | Phase 2 (CONS-01) |
| Main-recover-from-child | Main's signature + destination = registered main | Phase 2 (CONS-02) |
| Child→main transfer | Child's signature + UTXO ownership | Existing (CONS-03) |
| Spend main's funds | **Impossible** — requires main's signature | Phase 2 (CONS-05) |

The child cannot spend the main's funds, cannot recover assets to any address other than the registered main, and cannot modify consensus rules. The **only practical impact** is discovery-view spam: a main wallet might see unsolicited "claimed child" entries when listing its registered children.

#### 5.3.3 v2 Hardening Path

If discovery spam becomes a real problem in production, an optional main acceptance signature can be added as a v2 upgrade:

1. The main wallet submits a signed `RegistrationAcceptance` message.
2. The acceptance message moves a pending registration from "claimed" to "confirmed" state.
3. Only confirmed registrations appear in the main wallet's discovery view.

This is **deferred** — not designed in Phase 1.

### 5.4 Why NOT Dual-Signature (Rationale)

Dual-signature was considered and deliberately rejected (D-04, D-05) for the following reasons:

| Concern | Impact |
|---------|--------|
| **UX friction** | Dual-signature requires the user to approve a signing request in the GNUS Wallet app during the registration flow — the user must be online and actively respond. |
| **Private key exposure** | The main's private key must be accessible during a game session or child-app initialization. This violates the central security invariant: "main private key never enters the game/child process." |
| **Unnecessary for security** | Registration grants zero authority over the main. The main's consent is expressed at the UX level (connect flow approval), not cryptographically. Cryptographic consent would protect against something (discovery spam) that is better addressed by a lighter UX filter. |

The child-signed-only model eliminates the friction and keeps the main's private key entirely out of the game/child process — satisfying REG-04 trivially.

### 5.5 Connect Flow — Main Pubkey Delivery (REG-04)

Per D-10, the connect flow (GNUS Wallet app / "Connect GNUS Wallet" UI) delivers **only** the main wallet's public key to the child app. The main performs **no signing** during registration.

#### Transport-Agnostic Handshake

The connect flow is specified as a transport-agnostic handshake:

1. **Initiate:** The child app (game/SDK) initiates a "connect to main wallet" flow. The exact trigger is platform-specific (button in game UI, SDK API call, etc.) — out of scope for Phase 1.
2. **Approve:** The user approves the connection in the GNUS Wallet app. The approval is a UX action (tap "Connect"), not a cryptographic operation.
3. **Deliver pubkey:** The GNUS Wallet app returns the main wallet's public key to the child app. The pubkey is a 128-hex string, no "0x" prefix, validated via `GeniusAccount::IsValidPublicKey`.
4. **Use pubkey:** The child app uses this public key as `main_address` in the `RegistrationTx` it constructs and signs (see §5.2).

#### Platform UI Deferred

The concrete "Connect GNUS Wallet" platform UI flows (Android, iOS, Windows, macOS, Linux) are **out of scope for Phase 1** (deferred to v2 / PLAT-01, PLAT-02). This document specifies the transport-agnostic handshake only: the child receives the main's public key via an out-of-process channel. The `main_address` field is populated from whatever pubkey the connect flow delivered — the SuperGenius node does not know or care which transport was used.

#### Security Invariant

> **The main private key never enters the game/child process.**

This invariant is satisfied trivially because the main wallet performs zero cryptographic operations during registration. The connect flow delivers only the public key — a value that is, by definition, public. A compromised child process learns nothing it could not learn from the public ledger.

REG-04 is satisfied by this section: the design specifies the out-of-process pubkey-delivery handshake, the main private key never enters the child process, and the transport-agnostic specification defers platform implementation to v2.

### Traceability

| Requirement | Section | Decision |
|-------------|---------|----------|
| REG-02 | §5.1–5.4 | ⚠ REVERSED — child-signed-only; main does NOT counter-sign. Security impact analysis documents bounded risk (discovery spam only, zero authority grant). Flag for requirements update at phase transition. |
| REG-04 | §5.5 | Connect flow delivers main pubkey only; transport-agnostic handshake; main private key never enters child process. Platform UI deferred to v2 (PLAT-01, PLAT-02). |
