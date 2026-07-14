# Consensus Parent-Child Authority Rules

**Version:** 1.0
**Status:** Draft — Phase 02, Plan 02-02
**Date:** 2026-07-13
**Depends on:** `docs/02-crdt-registry-pubsub.md` (Plan 02-01) — CRDT `reg/` namespace, `FilterRegistration`, certified status flag

## 1. Overview

This design specifies how parent-child authority is enforced by consensus through a new `CheckParentChildAuthority` gate in `ValidateTransactionForConsensus`. It defines all six rules (CONS-01 through CONS-06) mapped to concrete SuperGenius pipeline stages, and resolves the architectural question of where hierarchical authority lives relative to UTXO ownership checks.

### Authority Model Summary

1. **Today, all authorization is purely cryptographic** — `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` checks only the tx signature. There is no hierarchical or role-based account authority in the consensus pipeline.

2. **This document introduces `CheckParentChildAuthority`** — the first state-dependent authority gate — which reads CRDT `reg/` records to determine parent-child relationships (per the `docs/02-crdt-registry-pubsub.md` design). The gate applies consensus-enforced rules for delegated authority transactions while leaving all non-delegated transactions unchanged.

3. **The gate slots between `CheckTransactionAuthorization` and `CheckTransactionTimestamp`** in the `ValidateTransactionForConsensus` pipeline at `TransactionManager.cpp:4250-4303` (D-19). Positioned after cryptographic signature verification but before timestamp and replay checks, it adds authority validation as a distinct, separable step.

4. **Only fires for `"transfer"` tx type** — all other types (`"registration"`, `"mint"`, `"escrow-hold"`, `"escrow-release"`, `"processing"`, `"migration"`) pass through the gate unmodified with an immediate `Approve()`.

5. **Keeps delegated authority orthogonal to UTXO ownership** (CONS-06 per D-23): the existing `ValidateWitness` owner_address check at `GeniusInputValidator.cpp:419` is UNCHANGED. Parent-child authority authorizes the main wallet to act ON a child's UTXOs; it does NOT authorize a child to act AS the main wallet.

6. **Most child→\* rules (CONS-03, CONS-04) are already handled** by existing validation and pass through the gate unchanged — documented as invariants, not new code. The gate only adds enforcement for the two delegated-authority rules: main→child fund (CONS-01) and main-recover-from-child (CONS-02).

7. **The gate reads `reg/{child_addr}` from CRDT** (per `docs/02-crdt-registry-pubsub.md` §2 for key layout, §6 for certified status) and MUST check certified status before applying authority rules (D-26). Uncertified registrations are treated as no relationship — the gate returns `Approve()` and lets downstream UTXO ownership checks handle the transaction.

### Requirements Covered

| Requirement | Description |
|-------------|-------------|
| CONS-01 | Main→child fund: main signature + child registered to that main (certified) |
| CONS-02 | Main-recover-from-child: main signature + destination restricted to registered main address (D-21) |
| CONS-03 | Child→arbitrary and child→main transfers: child signature suffices, passes through gate unchanged |
| CONS-04 | Child→developer wallet: child-signed transfer, existing `PayDev` path handles it |
| CONS-05 | Child-cannot-spend-main: enforced by existing `ValidateWitness` owner_address check at `GeniusInputValidator.cpp:419-432` (invariant, no new code) |
| CONS-06 | Hierarchical authority separate from UTXO ownership: `CheckParentChildAuthority` is a new gate; `CheckTransactionAuthorization` and `ValidateWitness` unchanged |

### Design Authority

This document is grounded in:

- **Phase 2 CONTEXT.md** — locked decisions D-19 through D-23, agent's discretion items
- **Phase 2 RESEARCH.md** — all 6 CONS requirements with research support, architectural responsibility map, pitfalls 2/4/5
- **Phase 2 PATTERNS.md** — code-pattern mapping of `ValidateTransactionForConsensus` pipeline (lines 415-484), `CheckTransactionAuthorization` gate template (lines 420-457), `CheckParentChildAuthority` declaration pattern (lines 449-457), six-rule reference implementation (lines 501-537), CONS-05 invariant (lines 540-570), `CheckTransactionTypeRules` pattern (lines 574-636)
- **`GNUS_Subwallet_Architecture_Proposal.md`** §Consensus Rules (lines 40-113) — authoritative rules 1-5
- **Code anchor points audited in each section:**
  - `SuperGenius/src/account/TransactionManager.cpp` — `ValidateTransactionForConsensus` (line 4234), `CheckTransactionAuthorization` (line 4361), `CheckTransactionTypeRules` (line 4558), `HandleNonceConsensusSubject` (line 3901)
  - `SuperGenius/src/account/TransactionManager.hpp` — gate declarations (lines 691-692)
  - `SuperGenius/src/account/GeniusInputValidator.cpp` — `ValidateWitness` owner_address check + escrow exception (lines 419-432)
  - `SuperGenius/src/blockchain/Consensus.hpp` — `ValidationResult` struct (lines 145-180)

### Cross-Reference to CRDT Design

This document depends on the CRDT registry infrastructure designed in `docs/02-crdt-registry-pubsub.md` (Plan 02-01):

- **§2 — CRDT Key Layout:** The `reg/{child_addr}` single-key-per-child design enables O(1) lookup during `CheckParentChildAuthority`.
- **§3 — FilterRegistration:** The CRDT element filter provides the first validation gate for RegistrationTx at the CRDT intake level.
- **§6 — Certified Status Flag:** The certified status/flag (`CONFIRMED` in `tx_processed_m`) determines whether a `reg/` record is authoritative. The authority gate MUST verify certification before applying rules (D-26).
- **§7 — Ordering Resolution:** First-to-consensus wins for competing registrations. The gate reads the authoritative (certified) record.

### Deferred to Phase 3

The following concerns are explicitly out of scope for this document and deferred to Phase 3:

- **Discovery/monitoring actions** (DISC-01, DISC-02, DISC-03) — main-wallet UI listing registered children
- **Reward policy** (RWD-01, RWD-02, RWD-03) — per-child processing reward distribution, dev_wallet/peers_cut resolution
- **Lifecycle state machine** (LIFE-01, LIFE-02, LIFE-03, LIFE-04) — replace, detach, revoke, close change-flows; "supersedes seq N" mechanics; main-replacement policy fork
- **Platform "Connect GNUS Wallet" UI flows** — v2 (PLAT-01, PLAT-02)
- **Aggregated registry topic** for publisher-scale child fan-out — v2 (ADV-02)

---

## 2. Gate Integration & Pipeline Extension

### D-19: Insertion Point

The new `CheckParentChildAuthority` gate slots **between `CheckTransactionAuthorization` and `CheckTransactionTimestamp`** in `ValidateTransactionForConsensus` at `TransactionManager.cpp:4250-4303`.

The existing pipeline at `TransactionManager.cpp:4234-4303` is:

```cpp
// Source: TransactionManager.cpp:4234-4303 (audited 2026-07-13)
ConsensusManager::ValidationResult TransactionManager::ValidateTransactionForConsensus(
    const std::shared_ptr<GeniusTransaction> &tx) const
{
    if (!tx) return ConsensusManager::ValidationResult::Reject();

    if (!CheckTransactionWellFormed(*tx))           // Gate 1
        return ConsensusManager::ValidationResult::Reject();
    if (!CheckTransactionAuthorization(*tx))         // Gate 2: signature only
        return ConsensusManager::ValidationResult::Reject();
    // ★★★ NEW: Gate 2.5 — insert CheckParentChildAuthority here ★★★
    if (!CheckTransactionTimestamp(*tx))             // Gate 3
        return ConsensusManager::ValidationResult::Reject();
    auto replay_result = EvaluateTransactionReplayProtection(*tx); // Gate 4
    if (replay_result.validation.check != ConsensusManager::Check::Approve)
        return replay_result.validation;
    if (!CheckTransactionTypeRules(tx))              // Gate 5
        return ConsensusManager::ValidationResult::Reject();

    return ConsensusManager::ValidationResult::Approve(); // Gate 6
}
```

### Extended 7-Gate Pipeline

After the addition, the full pipeline becomes:

| Gate | Name | File:Line | Responsibility | Modified? |
|------|------|-----------|----------------|-----------|
| 1 | `CheckTransactionWellFormed` | `TransactionManager.cpp:4306-4358` | Type registered in `transaction_parsers`, hash valid, source non-empty, timestamp non-zero | No |
| 2 | `CheckTransactionAuthorization` | `TransactionManager.cpp:4361-4383` | Signature verification (`tx.CheckSignature()` or `tx.CheckDAGSignatureLegacy()`). Purely cryptographic. | **No** |
| **2.5** | **`CheckParentChildAuthority`** | `TransactionManager.cpp` (new method) | State-dependent authority check reading CRDT `reg/` records. Returns `Approve()` for all non-delegated txs; `Reject()` for unauthorized delegated txs. **Only fires for `"transfer"` tx type.** | **NEW** |
| 3 | `CheckTransactionTimestamp` | `TransactionManager.cpp:4255` (call site) | Timestamp within acceptable range | No |
| 4 | `EvaluateTransactionReplayProtection` | `TransactionManager.cpp:4257-4259` (call site) | Nonce-chain replay check | No |
| 5 | `CheckTransactionTypeRules` | `TransactionManager.cpp:4558-4593` | Type-specific rules: UTXO params validation, RegistrationTx field validation (§6) | *Recommended addition* (§6) |
| 6 | `return ValidationResult::Approve()` | `TransactionManager.cpp:4261` | Transaction valid for consensus | No |

### Gate 2.5 Declaration

Add to `TransactionManager.hpp` after line 691 (after `CheckTransactionAuthorization` declaration, before `CheckTransactionTimestamp` declaration at line 692):

```cpp
// Source: TransactionManager.hpp:691 (existing)
bool CheckTransactionAuthorization( const GeniusTransaction &tx ) const;

// NEW — add after line 691:
ConsensusManager::ValidationResult CheckParentChildAuthority(
    const GeniusTransaction &tx ) const;

// Source: TransactionManager.hpp:692 (existing)
bool CheckTransactionTimestamp( const GeniusTransaction &tx ) const;
```

**Return type:** `ConsensusManager::ValidationResult` (not `bool`) — defined at `Consensus.hpp:145-180`. Supports three outcomes:

- `Approve()` — transaction passes authority check; pipeline continues
- `Reject()` — transaction violates authority rule; pipeline stops
- `Pending(deps, retry)` — CRDT dependency not yet available; retry after propagation

The `Pending` return supports the case where the gate needs a `reg/{child_addr}` CRDT record that has not yet synced to the validator's local state. The consensus engine re-queues the transaction for retry after the specified interval.

### D-23: Orthogonal Authority (CONS-06)

The new `CheckParentChildAuthority` gate is **orthogonal to UTXO ownership checks**. This separation is fundamental to the design:

1. **`CheckTransactionAuthorization` (`TransactionManager.cpp:4361-4383`) remains purely cryptographic** — it is NOT modified to read `reg/` entries. It verifies only that the tx signature matches the declared source address.

2. **`ValidateWitness` at `GeniusInputValidator.cpp:419-432` remains unchanged** — the owner_address check (`payload_owner == src_address`) with the escrow exception at line 421 (`delegated_escrow_spend`) as the sole deviation.

3. **Parent-child authority authorizes the main to act ON a child's UTXOs** — it does NOT authorize a child to act AS the main. The child's UTXOs are still owned by the child's address; the main's delegated authority is a layer above UTXO ownership that consensus validates independently.

4. **The escrow exception** (`GeniusInputValidator.cpp:421-424` — `delegated_escrow_spend`) remains the **only** place where `payload_owner != src_address` is allowed in `ValidateWitness`. Parent-child authority does NOT add a second exception — it operates through a separate gate entirely.

### Gate Activation Rule (D-20)

The gate only fires for `tx.GetType() == "transfer"`. For all other tx types, it immediately returns `Approve()`:

```cpp
if (tx.GetType() != "transfer")
    return ConsensusManager::ValidationResult::Approve();
```

This is because parent-child authority only affects fund movement — transfer transactions. RegistrationTx, MintTx, EscrowTx, ProcessingTx, and MigrationTx all pass through without any authority check. The `"transfer"` type is reused — no new tx types are needed (D-20).

---

## 3. Rule Dispatch Logic

### D-20: Deterministic Classification

The gate deterministically checks three things to classify the transaction and dispatch the correct rule:

1. **Who signed the tx?** — `tx.GetSrcAddress()` is the signer. `CheckTransactionAuthorization` (gate 2) already verified the signature matches this address.

2. **Is there a `reg/` record linking the addresses?** — Read `reg/{child_addr}` from CRDT using `GlobalDB::Get(HierarchicalKey(reg_key))` at `globaldb.hpp:115`. If the source address is registered as a child (`FetchedRegisteredMain(src)` returns a main address), the relationship exists. If the destination is a child, the `reg/` record links it to its registered main.

3. **Is the registration certified?** — Call `IsRegistrationCertified(child_addr)` per D-26. Uncertified registrations are treated as no relationship → gate returns `Approve()` and lets downstream checks handle the tx (which will reject if delegated authority is required but the main is not the UTXO owner).

### Signer Classification

| Signer | Condition | Implication |
|--------|-----------|-------------|
| **Main** | `src_address` is the main address AND source signed the tx (verified by gate 2) | Main is the UTXO owner for its own funds. For main-signed txs where src is a child address: the main claims delegated authority. |
| **Child** | `src_address` is a child address found in `reg/{child_addr}` AND source signed the tx | Child is the UTXO owner for its own funds. Child-signed txs do NOT need parent-child authority checking — existing auth handles them. |
| **Ordinary** (no registration) | Neither src nor dst has a `reg/` record | No parent-child authority applies → `Approve()`. Normal tx processing continues. |

### Direction Classification for Main-Signed Txs

When the main signed the transaction, the gate determines direction:

- **Main→Child fund (CONS-01):** `src == main_address_from_reg_record` AND `dst` is a child registered to that main → The gate verifies the `reg/{dst_child}` record links the child to this main and the registration is certified → `Approve()`. This is a normal main-signed transfer; the reg/ check is a **consistency validation**, not an access-control gate for the main's funds.

- **Main-recover-from-child (CONS-02):** `src` is a child registered to the signing main AND `src != main_address` → The gate reads `reg/{src_child}`, verifies the main signed AND `main_address_from_reg == dst` (D-21 destination restriction) → `Approve()` if `dst == main_address`, `Reject()` otherwise.

### Child-Signed Txs (CONS-03, CONS-04)

Child-signed txs pass through the gate unmodified — the gate effectively short-circuits: "child signed its own tx → child controls its own funds → approve." No CRDT lookup is needed for child-signed txs. The existing chain handles the rest:

- Gate 2 (`CheckTransactionAuthorization`) verified the child's signature
- `ValidateWitness` at `GeniusInputValidator.cpp:419` verifies child owns the UTXOs
- `EvaluateTransactionReplayProtection` verifies nonce ordering

### Decision Flowchart

```
                    ┌─────────────────────────┐
                    │ Gate 2.5: Entry         │
                    │ tx passed gate 2 (sig)  │
                    └───────────┬─────────────┘
                                │
                                ▼
                    ┌──────────────────────────┐
                    │ tx.GetType() ==           │
                    │ "transfer"?               │
                    └──────┬──────────┬────────┘
                           │ NO       │ YES
                           ▼          ▼
                    ┌──────────┐  ┌────────────────────────┐
                    │ Approve()│  │ Who signed the tx?      │
                    │ (pass    │  │ (src_address == signer) │
                    │  through)│  └─────┬────────────┬─────┘
                    └──────────┘        │            │
                                  CHILD │            │ MAIN
                                        ▼            ▼
                              ┌──────────────┐  ┌─────────────────────────┐
                              │ Approve()    │  │ Is there a certified     │
                              │ (child-signed│  │ reg/ record linking      │
                              │  tx; existing│  │ addr(s) to this main?   │
                              │  auth handles│  └──────┬──────────┬───────┘
                              │  it)         │         │ NO       │ YES
                              └──────────────┘         ▼          ▼
                                                ┌──────────┐  ┌──────────────────────┐
                                                │ Approve()│  │ Direction?            │
                                                │ (ordinary│  │ src == main OR        │
                                                │  tx, no  │  │ src == child?         │
                                                │  parent- │  └────┬──────────┬──────┘
                                                │  child   │       │          │
                                                │  auth)   │  FUND │          │ RECOVER
                                                └──────────┘       ▼          ▼
                                                             ┌──────────┐ ┌──────────────────┐
                                                             │ Approve()│ │ dst == main_addr │
                                                             │ (CONS-01)│ │ (from reg/       │
                                                             │ main→    │ │ record)?         │
                                                             │ child    │ └────┬──────┬──────┘
                                                             │ fund)    │      │ YES  │ NO
                                                             └──────────┘      ▼      ▼
                                                                         ┌────────┐ ┌──────────┐
                                                                         │Approve │ │ Reject() │
                                                                         │(CONS-02│ │(D-21:   │
                                                                         │recover)│ │ recovery │
                                                                         └────────┘ │ ≠ seizure│
                                                                                    └──────────┘
```

**Decision nodes count: 5+** — entry gate, transfer-type check, signer classification, certification check, direction dispatch, destination restriction.

---

## 4. Rule Specifications 1–4: Main→Child Fund, Recover, Child→Arbitrary, Child→Developer

### CONS-01 — Main→Child Fund

**Rule:** Main wallet can fund a registered child wallet using an ordinary `"transfer"` transaction. The gate performs a consistency validation: the child must be registered to the signing main.

**Gate Action:**
1. Verify tx signed by main (gate 2 at `TransactionManager.cpp:4361` already verified)
2. Read `reg/{dst_child}` from CRDT (key format per `docs/02-crdt-registry-pubsub.md` §2: `/bc-{net}/reg/{child_addr}`)
3. Confirm `record.main_address == src` (the child registered this main)
4. Confirm registration is certified (D-26)
5. If all pass → `Approve()`; if no `reg/` record or registration not certified → `Approve()` (treat as ordinary transfer without parent-child authority; main can still send to any address — funding is an unrestricted transfer)

**Consensus Verifies:** Main signature (gate 2) + child registered to that main (gate 2.5, consistency validation).

**Treating Unregistered Child:** The main can still send funds to any address — funding is an unrestricted transfer. The `reg/` check for funding is a consistency validation (the main intended to fund a registered child), not an access-control restriction. An unregistered address receives the funds normally.

**Anchor Points:**
- `CheckParentChildAuthority` reads `reg/{dst_child}` from CRDT
- `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` — main signature verification
- `globaldb.hpp:115` — `Get(HierarchicalKey)` for CRDT read
- RegistrationTx `main_address` field defined in `docs/registration-protocol.md` §2

### CONS-02 — Main-Recover-from-Child (D-21)

**Rule:** Main wallet can recover funds from a registered child wallet. The transaction is an ordinary `"transfer"` type. **Destination is restricted by consensus rule: `dst` MUST be the registered main address.**

**Gate Action:**
1. Verify tx signed by main (gate 2 at `TransactionManager.cpp:4361` already verified)
2. Read `reg/{src_child}` from CRDT (src is a child address; the reg/ record links it to a main)
3. Confirm `record.main_address` matches the signing main
4. Confirm registration is certified (D-26)
5. **D-21 Hard Restriction:** verify `dst == main_address` (from the certified `reg/` record)
6. If `dst != main_address` → `Reject()`
7. If all pass → `Approve()`

**Gate Logic (pseudocode):**
```
main_signed_the_tx == true
IsChildRegistered(src, main_from_reg) == true
registration_is_certified == true
main_from_reg == dst → Approve()
main_from_reg != dst → Reject()  // D-21: recovery ≠ seizure
```

**Security Rationale:** D-21 implements Pitfall 3 protection (recovery-as-seizure from RESEARCH.md). A compromised main wallet can drain all registered children to itself (recovery) but cannot redirect child funds to an attacker's address. This is the intended trust model: main compromise = bounded loss of child funds to the main address, not to an arbitrary attacker.

**Reuses `"transfer"` tx type** — the main constructs a normal transfer with `src = child_address, dst = main_address` and signs with its own key. The gate identifies this as a recovery by observing: main signed + src is a registered child of that main.

**Anchor Points:**
- `CheckParentChildAuthority` reads `reg/{src_child}` from CRDT — verifies `record.main_address == dst`
- `TransactionManager.cpp:4361` — main signature verification (gate 2)
- `docs/02-crdt-registry-pubsub.md` §2 — `reg/{child_addr}` key layout
- `docs/02-crdt-registry-pubsub.md` §6 — certified status flag
- `GeniusInputValidator.cpp:419-432` — `ValidateWitness` (see §5 for main-recover interaction)

### CONS-03 — Child→Arbitrary Address / Child→Main

**Rule:** Child wallet can transfer its own assets to ANY address (including its registered main wallet). Already handled by existing child signature check. No new consensus rule needed.

**Gate Action:** Child signed → gate returns `Approve()` immediately. The gate does NOT read CRDT for child-signed txs — child controls its own funds; no parent-child authority check is needed.

**Existing Enforcement Chain:**
1. `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` verifies child's signature
2. `ValidateWitness` at `GeniusInputValidator.cpp:419` verifies child owns the UTXOs (`payload_owner == src_address`)
3. `EvaluateTransactionReplayProtection` verifies nonce ordering at `TransactionManager.cpp:4257-4259`

**No reg/ lookup needed** — child-signed txs are short-circuited at the gate entry (see §3 decision flowchart). The registered main does not need to approve child transfers.

**Anchor Points:**
- `CheckParentChildAuthority` does NOT read CRDT for child-signed txs
- `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` — child signature verification
- `ValidateWitness` at `GeniusInputValidator.cpp:419` — UTXO ownership check

### CONS-04 — Child→Registered Developer Wallet

**Rule:** A normal child-signed transfer to the developer wallet address. No special consensus rule needed. The existing `PayDev` path handles it.

**Gate Action:** Same as CONS-03 — child signed → `Approve()`. The destination is the developer wallet from `DevConfig_st` (existing configuration), not from `reg/` record metadata.

**Existing Code:** `GeniusNode::PayDev` (existing transfer-to-developer path) constructs a normal transfer to `dev_wallet` address and signs it with the child key. The developer wallet address comes from `DevConfig_st` — this is existing configuration, not a `reg/` record field.

**No reg/ lookup needed** — no special authority rule applies. Child controls its own funds and can transfer to any address, including the developer wallet.

**Anchor Points:**
- `GeniusNode::PayDev` — existing transfer-to-developer path
- `DevConfig_st` — developer wallet address configuration
- `CheckParentChildAuthority` — child-signed tx, short-circuited `Approve()`

---

## 5. Rule Specification 5: Child-Cannot-Spend-Main Invariant (CONS-05)

### D-22: Already Enforced — No New Code Needed

The rule that **no child-signed transaction can spend main-wallet UTXOs** is already enforced by the existing `GeniusInputValidator::ValidateWitness` owner_address check at `GeniusInputValidator.cpp:419-432`. This document formalizes the enforcement as an explicit invariant and provides a negative test specification. **NO NEW CODE IS NEEDED.** The file `GeniusInputValidator.cpp` is NOT modified by this design.

### Existing Enforcement Mechanism

`ValidateWitness` at `GeniusInputValidator.cpp:419-432` extracts `payload_owner` from the UTXO payload at offset `OWNER_ADDRESS_OFFSET` and checks it against the transaction's source address:

```cpp
// Source: GeniusInputValidator.cpp:419-432 (audited 2026-07-13)
const std::string payload_owner( payload.data() + OWNER_ADDRESS_OFFSET,
                                 payload.data() + OWNER_ADDRESS_OFFSET + owner_len );

// The ONLY place where payload_owner != tx->GetSrcAddress() is allowed:
const bool delegated_escrow_spend =
    payload_owner != tx->GetSrcAddress() &&
    tx->GetType() == TRANSFER_TX_TYPE &&
    input.output_idx_ == ESCROW_LOCK_OUTPUT_INDEX &&
    utxo_address::IsEscrowLockAddress( payload_owner ) &&
    tx->GetUncleHash() == payload_owner;

// CONS-05 is enforced here:
if ( payload_owner != tx->GetSrcAddress() && !delegated_escrow_spend )
{
    logger->debug( "ValidateWitness(Genius) owner mismatch for tx={} owner={} src={}",
                   PreviewValue( tx->GetHash() ),
                   PreviewValue( payload_owner ),
                   PreviewValue( tx->GetSrcAddress() ) );
    return false;  // REJECT: child can't spend main's UTXOs
}
```

The key insight: the escrow exception at line 421 (`delegated_escrow_spend`) is the **sole deviation** from the `payload_owner == src_address` rule. This exception is narrow — it applies only to escrow-lock UTXOs spent with the matching uncle hash. Parent-child registration (CONS-01/CONS-02) does NOT create a second exception.

### The Invariant

> **No child-signed transaction can spend UTXOs owned by the main wallet — enforced by the existing `ValidateWitness` owner_address check at `GeniusInputValidator.cpp:419-432`. The escrow exception at line 421 is the sole deviation from `payload_owner == src_address`. Parent-child registration does NOT create a new exception path.**

A child key does not own main UTXOs — UTXOs are owned by `owner_address` per Phase 1 D-02 (`GeniusUTXO::owner_address_` at `GeniusUTXO.hpp:154`). Any child-signed tx attempting to spend a main UTXO fails the `payload_owner != tx->GetSrcAddress()` check and is rejected.

### Explicit Rejection Sequence

To verify the invariant, trace a child-signed tx attempting to spend main UTXOs through the full pipeline:

1. **Transaction constructed:** Child signs tx with `src = child_addr`, input pointing to main-owned UTXO
2. **Gate 1 — `CheckTransactionWellFormed`:** PASS — transfer tx, type in `transaction_parsers`, hash valid, source non-empty
3. **Gate 2 — `CheckTransactionAuthorization`:** PASS — child signature is valid (child signed)
4. **Gate 2.5 — `CheckParentChildAuthority`:** PASS — child-signed tx, gate returns `Approve()` (short-circuit). Parent-child authority is NOT checked for child-signed txs.
5. **Gate 3 — `CheckTransactionTimestamp`:** PASS — timestamp within range
6. **Gate 4 — `EvaluateTransactionReplayProtection`:** PASS — child nonce is correct
7. **Gate 5 — `CheckTransactionTypeRules` → `ValidateUTXOParameters` → `ValidateWitness`:**
   - Extracts `payload_owner` (main address) from UTXO
   - `payload_owner` (main) != `tx->GetSrcAddress()` (child)
   - `delegated_escrow_spend` is false (not an escrow lock)
   - `return false` → **REJECTED at `GeniusInputValidator.cpp:419-432`**

The rejection is **independent of parent-child authority** — it is a pure UTXO-ownership check. The gate 2.5 short-circuit for child-signed txs is correct: the child is not claiming delegated authority, so there is nothing for `CheckParentChildAuthority` to verify. The UTXO ownership check at gate 5 catches the violation.

### Negative Test Specification

**Test scenario:** Child-cannot-spend-main-UTXO

1. Create a child wallet (`child_addr`) with independent keypair
2. Create a main wallet (`main_addr`) with UTXOs owned by `main_addr`
3. Create a `"transfer"` tx with: `src = child_addr`, input UTXO owned by `main_addr`, `dst = arbitrary_addr`, signed with child key
4. Run through `ValidateTransactionForConsensus` pipeline
5. **Expected:** `ValidateWitness` at `GeniusInputValidator.cpp:419-432` rejects with owner mismatch. The rejection message is: `"ValidateWitness(Genius) owner mismatch for tx={hash} owner={main_addr} src={child_addr}"`.
6. **Verify:** Rejection occurs at gate 5, NOT at gate 2.5. The `CheckParentChildAuthority` gate returns `Approve()` for child-signed txs — it does not inspect UTXO ownership.
7. **Regression:** Confirm that if a main-signed recover tx (CONS-02) flows through the same pipeline, the gate 2.5→gate 5 interaction handles it correctly (see §7 lifecycle trace).

### `GeniusInputValidator.cpp` Is UNCHANGED

This design does NOT modify `GeniusInputValidator.cpp`. No line is added, removed, or altered. The file is documented as-is for traceability — to satisfy CONS-05, we point at the existing enforcement and add a test, not modify the validator.

The escrow exception at `GeniusInputValidator.cpp:421-424` remains the sole deviation from `payload_owner == src_address`. The main-recover-from-child flow (CONS-02) introduces a scenario where the signer (main) is NOT the UTXO owner (child), but this exception is handled through the gate 2.5→gate 5 signaling mechanism described in §7 — it does NOT modify GeniusInputValidator.cpp's validation logic.
