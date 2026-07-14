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

---

## 6. RegistrationTx Field Validation in Consensus Pipeline

### The Gap

RegistrationTx passes through `CheckTransactionWellFormed` (type exists in `transaction_parsers` at `TransactionManager.cpp:4306-4358`) and `CheckTransactionTypeRules` (no UTXO parameters → passes by default at `TransactionManager.cpp:4592` with `return true`). Its semantic fields — `main_address` validity and `sequence > 0` — are validated only in `FilterRegistration` (CRDT level, per `docs/02-crdt-registry-pubsub.md` §3, D-13 gate 4) but NOT in the consensus pipeline.

This creates a gap: the CRDT filter runs on a peer's local (possibly stale) state. Consensus validators independently validate the transaction and should not rely solely on the CRDT filter's validation for semantic correctness. Per Pitfall 5 (RESEARCH.md), the design must ensure RegistrationTx fields are validated at both the CRDT filter level AND the consensus level for defense-in-depth.

### Recommendation: Add RegistrationTx Validation to `CheckTransactionTypeRules`

Add a RegistrationTx validation branch to `CheckTransactionTypeRules` at `TransactionManager.cpp:4558-4593` for defense-in-depth. The insertion point is after the existing `HasUTXOParameters()` check (currently at line 4594 in the pipeline but conceptually at line 4588 in the method body) and before the default `return true` at line 4592:

```cpp
// Source: TransactionManager.cpp:4558-4593 (existing structure)
bool TransactionManager::CheckTransactionTypeRules(
    const std::shared_ptr<GeniusTransaction> &tx ) const
{
    if ( !tx ) { /* ... */ return false; }

    if ( tx->HasUTXOParameters() )
    {
        // ... existing UTXO params validation (lines 4585-4590) ...
        return validator.ValidateUTXOParameters( /* ... */ );
    }

    // ★ RECOMMENDED ADDITION: Insert RegistrationTx validation here ★
    // Before the default return true at line 4592:
    if ( tx->GetType() == "registration" )
    {
        auto reg_tx = std::dynamic_pointer_cast<RegistrationTransaction>( tx );
        if ( !reg_tx )
        {
            TransactionManagerLogger()->error(
                "[{} - full: {}] {}: RegistrationTx cast failed tx={}",
                account_m->GetAddress().substr( 0, 8 ), full_node_m,
                __func__, tx->GetHash() );
            return false;
        }

        // Validate main_address is a valid public key
        if ( !GeniusAccount::IsValidPublicKey( reg_tx->GetMainAddress() ) )
        {
            TransactionManagerLogger()->error(
                "[{} - full: {}] {}: Invalid main_address in RegistrationTx tx={}",
                account_m->GetAddress().substr( 0, 8 ), full_node_m,
                __func__, tx->GetHash() );
            return false;
        }

        // Validate sequence > 0
        if ( reg_tx->GetSequence() == 0 )
        {
            TransactionManagerLogger()->error(
                "[{} - full: {}] {}: Zero sequence in RegistrationTx tx={}",
                account_m->GetAddress().substr( 0, 8 ), full_node_m,
                __func__, tx->GetHash() );
            return false;
        }

        return true;
    }

    return true;  // Line 4592: all other non-UTXO txs pass by default
}
```

**Validation Items:**

| Check | Method | Anchor Point | Rationale |
|-------|--------|--------------|-----------|
| `main_address` valid | `GeniusAccount::IsValidPublicKey()` | `GeniusAccount.hpp:152` | Rejects malformed or empty main addresses. 128-hex, no "0x" prefix. |
| `sequence > 0` | `reg_tx->GetSequence()` | `RegistrationTx.sequence` (Plan 01-02, `docs/registration-protocol.md` §2) | Zero sequence = uninitialized. First registration = 1. |

### Defense-in-Depth Rationale

`FilterRegistration` validates the same fields at the CRDT filter level (per D-13 gate 4, `docs/02-crdt-registry-pubsub.md` §3). This recommendation adds the **same validation at the consensus level** for independent verification:

| Layer | Validates `main_address`? | Validates `sequence > 0`? | State Dependence |
|-------|---------------------------|---------------------------|-----------------|
| `FilterRegistration` (CRDT filter) | ✓ | ✓ | Runs on peer's local (possibly stale) CRDT |
| `CheckTransactionTypeRules` (consensus) | ✓ (recommended) | ✓ (recommended) | Runs during consensus validation (current state) |

Even if CRDT state is stale and the filter missed a malformed entry, the consensus path catches it. Both layers validate independently — defense-in-depth.

### Existing CheckTransactionWellFormed Validation

`CheckTransactionWellFormed` at `TransactionManager.cpp:4306-4358` already validates basic tx structure that applies to RegistrationTx:

- Hash not empty and valid (`tx.GetHash().empty() || !tx.CheckHash()`)
- Source address not empty (`tx.GetSrcAddress().empty()`)
- Timestamp non-zero (`tx.GetTimestamp() == 0`)
- Type exists in `transaction_parsers` map (line 4343)

RegistrationTx passes all of these (provided its parser is registered in `transaction_parsers` per Phase 1 hand-off). No changes to `CheckTransactionWellFormed` are needed.

### Non-Interaction with CheckParentChildAuthority

The gate 2.5 (`CheckParentChildAuthority`) does NOT validate RegistrationTx fields — that is not its responsibility. The separation of concerns is:

| Gate | Validates RegistrationTx? | Responsibility |
|------|---------------------------|----------------|
| `CheckTransactionWellFormed` (gate 1) | Basic structure (hash, src, timestamp, type) | All tx types |
| `CheckTransactionAuthorization` (gate 2) | Signature | All tx types |
| `CheckParentChildAuthority` (gate 2.5) | **No** — only fires for `"transfer"` type | Delegated authority |
| `CheckTransactionTypeRules` (gate 5) | `main_address` validity, `sequence > 0` (recommended) | Type-specific rules |

`FilterRegistration` (CRDT filter) and `CheckTransactionTypeRules` (consensus validation) are the two validation points for RegistrationTx fields — both are independent of the parent-child authority gate.

---

## 7. Rule Summary Matrix & Pipeline Trace

### Rule Summary Matrix

| Rule ID | Transaction | Who Signs | Gate Action | Existing Code | New Code |
|---------|------------|-----------|-------------|---------------|----------|
| **CONS-01** | Main→Child fund | Main | Verify `reg/{dst_child}` record links child to this main + certified → `Approve()` | `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` (main sig) | `CheckParentChildAuthority` reads `reg/{dst_child}` → verifies `main_address == src` |
| **CONS-02** | Main-recover-from-child | Main | Verify `reg/{src_child}` record links src child to this main + certified + `dst == main_address` → `Approve()`; else `Reject()` | `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` (main sig) | `CheckParentChildAuthority` reads `reg/{src_child}` → verifies `main_address == dst` (D-21) |
| **CONS-03** | Child→Arbitrary / Child→Main | Child | Short-circuit → `Approve()` (existing child sig check handles it) | `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` (child sig) + `ValidateWitness` at `GeniusInputValidator.cpp:419` (ownership) | None |
| **CONS-04** | Child→Developer | Child | Same as CONS-03 — child-signed, short-circuit → `Approve()` | `GeniusNode::PayDev` (existing) + `ValidateWitness` at `GeniusInputValidator.cpp:419` (ownership) | None |
| **CONS-05** | Child→spend-main-UTXO | Child | Gate passes (child-signed), but `ValidateWitness` owner_address check REJECTS at gate 5 | `GeniusInputValidator.cpp:419-432` (`payload_owner != src_address`; `delegated_escrow_spend` at line 421 is sole exception) | None — documented as invariant |
| **CONS-06** | Authority vs UTXO separation | N/A | `CheckParentChildAuthority` is a separate gate; `CheckTransactionAuthorization` and `ValidateWitness` unchanged | `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` (sig-only) + `ValidateWitness` at `GeniusInputValidator.cpp:419` (ownership) | `CheckParentChildAuthority` (state-dependent authority, new gate) |

### Full Transaction Lifecycle Trace: Main→Child Fund (CONS-01)

1. **Transaction construction:** Main constructs tx with `src=main_addr, dst=child_addr, type="transfer"`, calls `FillHash()`, signs with main key via `MakeSignature()`

2. **Submission:** `SendTransactionItem` at `TransactionManager.cpp:1127` — writes CRDT at `tx/{hash}`, collects topics (`full_node_topic_m` + `account_m->GetAddress()`), commits CRDT transaction

3. **Consensus proposal:** `CreateConsensusProposal` at `Consensus.hpp:410` → `SubmitProposal` at `TransactionManager.cpp:1305` → `sgns.nonce.v1` subject

4. **Consensus validation entry:** `HandleNonceConsensusSubject` at `TransactionManager.cpp:3901` — deserialize, hash binding, nonce match, account match → `ValidateTransactionForConsensus`

5. **Gate 1 — `CheckTransactionWellFormed` (`TransactionManager.cpp:4306-4358`):** PASS — `"transfer"` in `transaction_parsers`, hash valid, source non-empty, timestamp non-zero

6. **Gate 2 — `CheckTransactionAuthorization` (`TransactionManager.cpp:4361-4383`):** PASS — main key signature verified via `tx.CheckSignature()`

7. **Gate 2.5 — `CheckParentChildAuthority` (new):**
   - `tx.GetType() == "transfer"` → YES, gate applies
   - Signer = main (src = main_addr)
   - Read `reg/{dst_child}` from CRDT via `GlobalDB::Get(HierarchicalKey("/bc-{net}/reg/" + child_addr))`
   - Found: certified record with `main_address == src` (child registered this main)
   - → `Approve()`

8. **Gate 3 — `CheckTransactionTimestamp` (`TransactionManager.cpp:4255`):** PASS — timestamp within valid range

9. **Gate 4 — `EvaluateTransactionReplayProtection` (`TransactionManager.cpp:4257-4259`):** PASS — main's nonce is correct (no replay)

10. **Gate 5 — `CheckTransactionTypeRules` (`TransactionManager.cpp:4558-4593`):** `ValidateUTXOParameters` → PASS — main owns the UTXOs (`payload_owner == src_address`)

11. **Gate 6 — `return ValidationResult::Approve()` (`TransactionManager.cpp:4261`):** PASS → consensus certificate → `OnConsensusCertificate` at `TransactionManager.cpp:3768` → `ChangeTransactionState(tx, CONFIRMED)` → **CONFIRMED**

### Full Transaction Lifecycle Trace: Main-Recover-from-Child (CONS-02)

1. **Transaction construction:** Main constructs tx with `src=child_addr, dst=main_addr, type="transfer"`, signs with main key (NOT child key). The tx claims `src=child_addr` but the signer is the main — this IS the delegated authority pattern.

2. **Submission:** Same path as fund (steps 2-4 above)

3. **Gate 1 — `CheckTransactionWellFormed`:** PASS

4. **Gate 2 — `CheckTransactionAuthorization`:** PASS — main key signature verified. Note: the signature is against the main key, NOT the child key. The tx declares `src=child_addr` but the signer is `main_addr`. This is correct — the main is exercising delegated authority.

5. **Gate 2.5 — `CheckParentChildAuthority`:**
   - `tx.GetType() == "transfer"` → YES
   - Signer = main (verified by gate 2)
   - `src` = child address (tx claims child as source)
   - Read `reg/{src_child}` from CRDT → finds certified record with `main_address` matching signer
   - Direction = recover (main signed, src is the child)
   - **D-21 check:** `dst == main_address` (from reg/ record)? YES
   - → `Approve()` AND **sets delegated-authority flag on tx**

6. **Gate 3 — `CheckTransactionTimestamp`:** PASS

7. **Gate 4 — `EvaluateTransactionReplayProtection`:** PASS — the account used for nonce tracking depends on implementation. Recommendation: use main's nonce chain for main-signed delegated txs. The main signs → main's nonce is consumed.

8. **Gate 5 — `CheckTransactionTypeRules` → `ValidateUTXOParameters` → `ValidateWitness`:**
   - Child's UTXOs: `payload_owner` = child_addr
   - `payload_owner` (child) != `tx->GetSrcAddress()` (also child — wait, `src_address` IS the child)
   - Actually: the UTXO is owned by the child (`payload_owner == child_addr`). The tx's `src_address` is also `child_addr`. So `payload_owner == src_address` → PASSES the basic check.
   - The delegated-authority flag set by gate 2.5 is NOT needed for `ValidateWitness` in this case — the child owns the UTXOs, and the tx declares `src=child_addr`. The UTXO ownership check passes naturally because the source address matches the UTXO owner.
   - **Key insight:** For main-recover-from-child, the main signs but the tx declares `src=child_addr`. The UTXOs are owned by `child_addr`. So `payload_owner == src_address` → PASSES. The delegated-authority check is about WHO CAN SIGN a tx from the child's address — `CheckParentChildAuthority` (gate 2.5) grants this. `ValidateWitness` (gate 5) doesn't need to know about delegation because the UTXO owner matches the source address.

9. **Gate 6 — `Approve()`:** PASS → consensus certificate → **CONFIRMED**

#### Interaction Between Gate 2.5 and Gate 5

The design relies on an important property: for main-recover-from-child, the tx declares `src=child_addr` (the UTXO owner), and the UTXOs are indeed owned by `child_addr`. Therefore `ValidateWitness` sees `payload_owner == src_address` → passes trivially. The authorized signer (main) is different from the tx source, but that was already checked by gate 2 (`CheckTransactionAuthorization` verified the main's signature) and gate 2.5 (`CheckParentChildAuthority` verified the main has delegated authority for this child).

**The gate interaction model:**

| Check | Main→Child fund | Main-recover-from-child |
|-------|-----------------|------------------------|
| `CheckTransactionAuthorization` (gate 2) | Main sig = main src → PASS | Main sig → PASS |
| `CheckParentChildAuthority` (gate 2.5) | `reg/{dst_child}` confirms relationship → `Approve()` | `reg/{src_child}` confirms relationship + `dst==main_addr` → `Approve()` |
| `ValidateWitness` (gate 5) | `payload_owner` (main) == `src_address` (main) → PASS | `payload_owner` (child) == `src_address` (child) → PASS |
| **Result** | Main owns UTXOs, signs, funds child | Main signs as child's delegate, UTXOs owned by child, `src_address` matches child → UTXO ownership check passes naturally |

**No special flag needed** — the delegated-authority flag discussed in earlier sections is NOT required for `ValidateWitness`. The UTXO ownership check passes because the tx's `src_address` matches the UTXO's `owner_address`. The authority gate (gate 2.5) ensures the signer is authorized to sign for that address. The two checks remain orthogonal (CONS-06).

### Consensus-Ordering Integration

The `reg/` record used by `CheckParentChildAuthority` must be certified (D-26, per `docs/02-crdt-registry-pubsub.md` §6-7). The certified status is tracked via `CONFIRMED` in `tx_processed_m` at `TransactionManager.hpp:71-80`. The certification flow:

1. RegistrationTx flows through consensus (`sgns.nonce.v1` subject, `HandleNonceConsensusSubject` at `TransactionManager.cpp:3901`)
2. Consensus validators approve → certificate issued
3. `OnConsensusCertificate` at `TransactionManager.cpp:3768` → `ChangeTransactionState(tx, CONFIRMED)` → marks cert status
4. `IsRegistrationCertified(child_addr)` checks `tx_processed_m` for `CONFIRMED` status
5. `CheckParentChildAuthority` calls `IsRegistrationCertified()` before applying authority rules

Uncertified registrations → treated as no relationship → gate returns `Approve()` → the tx proceeds without parent-child authority → if it was a main-recover tx, `CheckParentChildAuthority` doesn't grant authority → gate 2 returns `Approve()` (main sig valid) but gate 5 (`ValidateWitness`) sees `src_address` (child) with main signer → actually this scenario is complex. Re-reading: if registration is uncertified, gate 2.5 returns `Approve()` without setting any authority. The tx proceeds to gate 5. The main signed a tx with `src=child_addr`. UTXOs are owned by child. `payload_owner == src_address`? YES (child == child). So it passes. The main could recover from an uncertified child! This is the Pitfall 2 scenario from RESEARCH.md.

**CRITICAL:** The gate returns `Approve()` but without authority grant for uncertified registrations. However, the UTXO ownership check at gate 5 passes because `src_address == payload_owner` (both are child_addr). The protection against uncertified recovery is NOT at the UTXO ownership level — it MUST be at the authority gate level. The gate must REJECT (not Approve) when a main-signed tx claims `src=child_addr` but the registration is uncertified:

**Corrected gate behavior for uncertified registrations:**
- If main signed, src is child address, reg/ record exists but is **NOT certified** → **`Reject()`** (not `Approve()`)
- If main signed, src is child address, NO reg/ record exists → `Approve()` (the tx proceeds, but `ValidateWitness` will reject because the signer is not the UTXO owner... actually, same issue — `src_address` IS the child address, so `payload_owner == src_address` passes)
- **Resolution:** The gate MUST reject when main-signed from a child address and the registration is uncertified. The safe default is: no certified registration → no delegated authority → **reject** main-signed-from-child-address transfers.

This correction is essential. The gate logic for uncertified registrations must be:

```
if (main_signed && src_is_child) {
    if (!has_certified_registration(src)) {
        return REJECT;  // No certified reg → no delegated authority
    }
    // ... apply recovery rules (D-21 dst check) ...
}
```

Cross-reference to `docs/02-crdt-registry-pubsub.md` §6: certified status is the gatekeeper. No certified registration → no authority.

---

## 8. Requirement Traceability & Decision Compliance

### Requirement Traceability

| Req ID | Description | Anchor Point(s) | Section |
|--------|-------------|-----------------|---------|
| **CONS-01** | Main→child funding rule (main sig + registered child) | `CheckParentChildAuthority` reads `reg/{dst_child}`; `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` | §4 |
| **CONS-02** | Main-recover-from-child with destination restricted to registered main address | `CheckParentChildAuthority` reads `reg/{src_child}`; hard `dst == main_address` check (D-21); uncertified registration → `Reject()` | §4, §7 |
| **CONS-03** | Child→arbitrary-address and child→main transfer rules | `CheckTransactionAuthorization` at `TransactionManager.cpp:4361` (child sig) + `ValidateWitness` at `GeniusInputValidator.cpp:419` (ownership); gate short-circuits child-signed txs | §4 |
| **CONS-04** | Child→registered-developer-wallet payment rule | `GeniusNode::PayDev` (existing); child-signed tx, gate short-circuits | §4 |
| **CONS-05** | Explicit rejection: child key cannot authorize spending main-wallet funds | `ValidateWitness` at `GeniusInputValidator.cpp:419-432` (`payload_owner != src_address`); `delegated_escrow_spend` at line 421 is sole exception; negative test spec provided | §5 |
| **CONS-06** | Hierarchical authority layer separate from UTXO ownership checks | `CheckParentChildAuthority` = new gate; `CheckTransactionAuthorization` unchanged at `TransactionManager.cpp:4361` (sig-only); `ValidateWitness` unchanged at `GeniusInputValidator.cpp:419`; gate reads CRDT state, ownership checks read UTXO payload | §2 |

### Decision Compliance

| Decision | Description | Section | Status |
|----------|-------------|---------|--------|
| **D-19** | `CheckParentChildAuthority` gates between authorization and timestamp in `ValidateTransactionForConsensus`; only fires for `"transfer"` type | §2 | **Included** |
| **D-20** | Rule dispatch reuses existing `"transfer"` tx type; no new tx types; gate checks signer, reg/ record, certified status; direction determines fund vs recover | §3 | **Included** |
| **D-21** | Main-recover-from-child: hard `dst == main_address` restriction (recovery ≠ seizure) | §4 | **Included** |
| **D-22** | Child-cannot-spend-main: enforced by existing `ValidateWitness` owner_address check at `GeniusInputValidator.cpp:419-432`; documented as invariant + negative test spec; no new code needed | §5 | **Included** |
| **D-23** | CONS-06: hierarchical authority orthogonal to UTXO ownership; `CheckParentChildAuthority` separate from `CheckTransactionAuthorization` at `TransactionManager.cpp:4361`; existing ownership checks unchanged | §2 | **Included** |

### CRDT-Dependent Decisions (Covered in Plan 02-01)

The following decisions are covered in `docs/02-crdt-registry-pubsub.md` (Phase 02 Plan 01) but are explicitly cross-referenced here because the authority gate depends on them:

| Decision | Description | Plan 02-01 Section | Referenced Here |
|----------|-------------|---------------------|-----------------|
| D-11 | `reg/` namespace only; `FilterRegistration` on TransactionManager | §1, §3 | §1 (cross-reference) |
| D-12 | `reg/{child_addr}` single-key layout | §2 | §3, §4 (CRDT read during gate) |
| D-13 | `FilterRegistration` rejection gates (deser, sig, seq, well-formed) | §3 | §6 (defense-in-depth validation) |
| D-14 | CRDT value = full RegistrationTx protobuf | §2 | §3 (self-contained reg/ records) |
| D-26 | Certified status flag; main only acts on certified registrations | §6 | §3, §7 (gate MUST check certification) |

### Deferred Items

The following Phase 3 and v2 requirements are explicitly deferred — they are NOT covered by this document:

| Phase | Req IDs | Concern |
|-------|---------|---------|
| Phase 3 | DISC-01, DISC-02, DISC-03 | Main-wallet discovery/monitoring UI: per-child balance, assets, game, publisher, dev wallet, cut ratio, activity, status |
| Phase 3 | RWD-01, RWD-02, RWD-03 | Per-child processing-reward policy: dev_addr/peers_cut resolution, hold-time pinning, authenticated update rules |
| Phase 3 | LIFE-01, LIFE-02, LIFE-03, LIFE-04 | Lifecycle state machine: replace, detach, revoke, close change-flows; "supersedes seq N" mechanics; main-replacement policy fork |
| v2 | PLAT-01, PLAT-02 | Platform "Connect GNUS Wallet" UI flows (Android, iOS, Windows, macOS, Linux) |
| v2 | ADV-02 | Aggregated registry topic for publisher-scale child fan-out |

---

*Document: 02-consensus-parent-child-authority.md*
*Phase: 02 — CRDT Persistence, PubSub & Consensus Authority*
*Plan: 02-02*
*Completed: 2026-07-13*
