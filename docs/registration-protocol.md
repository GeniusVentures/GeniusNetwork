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
