# Reward Policy & Lifecycle Design

**Phase 3, Plan 2** | **Status:** Complete | **Version:** 1.0

This document specifies per-child processing-reward policy for both standalone and registered children, hold-time pinning via existing EscrowTransaction immutability, authenticated policy updates via child-signed RegistrationTx at higher sequence, the four-state lifecycle model with all valid transitions, detach/revoke/replace-main change-flows with supersedes-sequence conflict resolution, and the main-replacement policy fork decision. Every concept is mapped to concrete SuperGenius anchor points — `EscrowTransaction`, `HoldEscrow`/`PayEscrow`, `GeniusNode`, `TransactionManager`, `FilterRegistration`, `CheckParentChildAuthority`, and the `sgns.nonce.v1` consensus subject — so a future implementer can proceed directly from this document.

---

## 1. Overview

Per-child processing-reward policy defines where developer payouts go (`dev_wallet`) and what fraction peers receive (`peers_cut`) when a child wallet earns GNUS from AI processing work. The policy source depends on the child's registration status — standalone children use the SDK's `DevConfig_st`, while registered children use the `RegistrationMetadata.dev_wallet` and `RegistrationMetadata.peers_cut` from their certified `reg/{child_addr}` CRDT record.

### 1.1 Two-Mode Architecture

1. **Standalone mode:** `GeniusNode::ProcessImage` reads `dev_config_.Addr` and `dev_config_.Cut` at HoldEscrow time — identical to today's behavior. No registration means no per-child policy; the game publisher's SDK defaults apply. The `DevConfig_st` struct (`GeniusNode.hpp:59-66`) carries `Addr` (developer payout address), `Cut` (peer payout fraction), and `TokenID` (token identifier).

2. **Registered mode:** After the child's registration is certified (D-26), `GeniusNode::ProcessImage` reads `RegistrationMetadata.dev_wallet` and `RegistrationMetadata.peers_cut` from the certified `reg/{child_addr}` CRDT record. These values supersede `DevConfig_st` for all NEW escrows created after certification. Existing escrows retain the policy pinned at their original HoldEscrow time.

Per D-31: "Registration policy supersedes DevConfig only for escrows created after certification. Escrows created before certification use the DevConfig policy that was active at HoldEscrow time — they are NOT retroactively updated."

**Key anchor points:**
- `GeniusNode.hpp:59-66` — `DevConfig_st` definition: `Addr`, `Cut`, `TokenID`
- `GeniusNode.cpp:1977-1985` — current `HoldEscrow` reads `dev_config_`
- `01-01-SUMMARY.md` — `RegistrationMetadata` schema: `game_id`, `publisher_id`, `dev_wallet`, `peers_cut`
- Phase 2 `02-01-PLAN.md` — CRDT `reg/` namespace (D-11/D-12), certified status (D-26)

**Traceability:** D-30 (standalone: DevConfig at HoldEscrow), D-31 (registered: RegistrationMetadata supersedes DevConfig for new escrows)

---

## 2. Reward Policy Resolution Flow

**Requirement:** RWD-01

The policy-source selection happens at the `GeniusNode` level — the caller of `TransactionManager::HoldEscrow`. `TransactionManager::HoldEscrow` is policy-agnostic: it receives `dev_addr` and `peers_cut` as parameters and constructs the `EscrowTransaction`. The caller (GeniusNode) chooses the source. No change to `TransactionManager` is needed.

### 2.1 Policy-Source Selection Logic

Before calling `HoldEscrow(amount, dev_addr, peers_cut, job_id)`, the `GeniusNode` caller determines the reward policy source:

1. If the child has a certified `reg/{child_addr}` CRDT record: read `RegistrationMetadata.dev_wallet` → `dev_addr`, `RegistrationMetadata.peers_cut` → `peers_cut`.
2. If the child has NO certified `reg/{child_addr}` record (standalone): read `dev_config_.Addr` → `dev_addr`, `dev_config_.Cut` → `peers_cut`.
3. Call `TransactionManager::HoldEscrow(amount, resolved_dev_addr, resolved_peers_cut, job_id)`.

The certified-status check (D-26) is critical: uncertified registrations are treated as "no registration" → DevConfig fallback. This prevents an attacker from injecting a false `dev_wallet` via an uncertified CRDT delta (see Threat Model, T-03-06).

### 2.2 HoldEscrow Signature (Policy-Agnostic)

`TransactionManager::HoldEscrow` (`TransactionManager.hpp:172-175`) receives `dev_addr` and `peers_cut` as explicit parameters:

```
HoldEscrow(uint64_t amount, const std::string &dev_addr, uint64_t peers_cut, const std::string &job_id)
```

The implementation at `TransactionManager.cpp:778-810` constructs the `EscrowTransaction` with these values, passing them directly to the `EscrowTransaction::New()` factory. The caller (GeniusNode) chooses the source; `TransactionManager` is policy-agnostic.

### 2.3 Current DevConfig Path

The existing code path at `GeniusNode.cpp:1977-1985` demonstrates the standalone policy resolution:

- `dev_config_.Cut` is parsed via `sgns::TokenAmount::ParseMinions(dev_config_.Cut)`
- `dev_config_.Addr` is passed as the `dev_addr` parameter
- `HoldEscrow(funds, std::string(dev_config_.Addr), cut.value(), uuidstring)` is called with these DevConfig values

This path remains unchanged for standalone children. For registered children, the policy source resolution step (step 1 above) is inserted before the HoldEscrow call — reading from `reg/{child_addr}` CRDT instead of `dev_config_`.

### 2.4 Certified-Status Gate

The certified-status check (D-26, Phase 2) is the gate that determines whether a `reg/{child_addr}` record is authoritative for policy resolution. An uncertified registration — one that exists in CRDT but has not been confirmed by consensus — MUST be treated as "no registration" for policy resolution purposes. This prevents T-03-06: an attacker injecting a false `dev_wallet` via an uncertified CRDT delta.

The check is:
1. Read `reg/{child_addr}` from CRDT.
2. If the record exists AND `tx_processed_m` (or equivalent certified flag) is `CONFIRMED`: use `RegistrationMetadata` for policy.
3. Otherwise: fall back to `DevConfig_st`.

**Certified-status anchors:**
- `TransactionManager.cpp:3655-3764` — `OnConsensusCertificate` sets CONFIRMED status
- `TransactionManager.cpp:3901-3960` — `HandleNonceConsensusSubject` processes nonce consensus
- Phase 2 `02-02-PLAN.md` — `CheckParentChildAuthority` gate (D-19) validates certification before granting authority

### 2.5 Integration Surface

| Component | Current Behavior | Phase 3 Change |
|-----------|-----------------|----------------|
| `GeniusNode::ProcessImage` | Reads `dev_config_` for all children | Adds `reg/{child_addr}` CRDT lookup before HoldEscrow; uses RegistrationMetadata if certified, falls back to DevConfig |
| `TransactionManager::HoldEscrow` | Receives `dev_addr`/`peers_cut` as params — policy-agnostic | No change |
| `EscrowTransaction` constructor | Pins `dev_addr_`/`peers_cut_` at construction | No change |

**References:**
- `TransactionManager.hpp:172-175` — HoldEscrow signature
- `TransactionManager.cpp:778-810` — HoldEscrow implementation (receives params)
- `GeniusNode.cpp:1977-1985` — current DevConfig source path
- `GeniusNode.hpp:59-66` — DevConfig_st struct
- Phase 2 `02-01-PLAN.md` — reg/ CRDT namespace (D-11/D-12), certified status (D-26)

**Traceability:** RWD-01

---

## 3. Hold-Time Pinning

**Requirement:** RWD-02

Per D-32: "The reward policy (`dev_addr`, `peers_cut`) is pinned at `HoldEscrow` time. The `EscrowTransaction` stores these values in its own fields (`dev_addr_`, `peers_cut_`), NOT as a reference to a reg/ record that could change. This is existing behavior and requires no design change."

### 3.1 EscrowTransaction Immutability Chain

The immutability chain has three links:

**Link 1 — Construction:** The `EscrowTransaction` constructor (`EscrowTransaction.hpp:122-131`) stores `dev_addr_` (line 130), `peers_cut_` (line 131), and `amount_` (line 129) as member variables. These are set once at construction time and never modified thereafter. The constructor signature receives all policy values as parameters:

```
EscrowTransaction(UTXOTxParameters params, uint64_t amount,
                  std::string dev_addr, uint64_t peers_cut,
                  SGTransaction::DAGStruct dag)
```

**Link 2 — PayEscrow stored reads:** `PayEscrow` (`TransactionManager.cpp:846-875`) reads the stored values, NOT live CRDT state:
- Line 848: `escrow_tx->GetPeersCut()` — reads `peers_cut_` member
- Line 875: `escrow_tx->GetDevAddress()` — reads `dev_addr_` member

**Link 3 — No re-read from CRDT:** `PayEscrow` has zero awareness of the current `reg/{child}` CRDT record. It operates solely on the `EscrowTransaction` object that was constructed at HoldEscrow time. Live CRDT changes (new `RegistrationTx` with updated `RegistrationMetadata`) cannot retroactively affect in-progress escrows.

### 3.2 Mid-Flight Policy Change Scenario

If a child updates its reward policy mid-flight — i.e., issues a new `RegistrationTx` at higher sequence with different `dev_wallet`/`peers_cut` values — in-progress escrows are UNAFFECTED. The sequence is:

1. Escrow A is created at HoldEscrow time T₁ with policy P₁ (pinned in `EscrowTransaction`)
2. Child issues `RegistrationTx` at sequence N+1 with new policy P₂ at time T₂
3. Escrow B is created at HoldEscrow time T₃ with policy P₂ (new policy for new escrows)
4. When Escrow A reaches `PayEscrow`, it reads P₁ (the stored values from T₁), NOT P₂
5. When Escrow B reaches `PayEscrow`, it reads P₂ (the stored values from T₃)

### 3.3 Design Impact

**This satisfies RWD-02 with ZERO Phase 3 changes to `EscrowTransaction`.** The model is already correct per the existing SuperGenius architecture. The design doc documents this as a verified invariant, not a new implementation.

**References:**
- `EscrowTransaction.hpp:122-131` — constructor pins `dev_addr_`, `peers_cut_`, `amount_`
- `EscrowTransaction.hpp:129-131` — member variable declarations
- `TransactionManager.cpp:846-875` — PayEscrow reads stored values
- `TransactionManager.cpp:848` — `escrow_tx->GetPeersCut()` (stored read)
- `TransactionManager.cpp:875` — `escrow_tx->GetDevAddress()` (stored read)
- RESEARCH.md Pitfall 3 — "already enforced by EscrowTransaction immutability"

**Traceability:** RWD-02

---

## 4. Authenticated Policy Updates

**Requirement:** RWD-03

Per D-33: "Reward policy updates are child-only via a new `RegistrationTx` with a higher `sequence` number and updated `RegistrationMetadata` (dev_wallet, peers_cut). The child signs the updated RegistrationTx; consensus accepts it because the child's signature is valid over its own registration (same model as D-04/D-05)."

### 4.1 Update Flow

1. **Child constructs a new `RegistrationTx`** with:
   - Same `main_address` (if staying with same main)
   - **Higher** `sequence` (current sequence + 1)
   - Updated `RegistrationMetadata` with new `dev_wallet` and/or `peers_cut` values
   - `supersedes_sequence` = current registration's `sequence` (D-38 linkage)

2. **Child signs** the `RegistrationTx` with its own keypair (D-04/D-05: child-signed-only). No main co-signature is required.

3. **CRDT Filter Gate validation** (`FilterRegistration`, Phase 2 D-13):
   - Gate 2: child signature valid (`CheckTransactionAuthorization`, `TransactionManager.cpp:4361-4383`)
   - Gate 3: `sequence > current.sequence` (sequence monotonicity)
   - Gate 3b (Phase 3 extension, D-38): `supersedes_sequence == current.sequence`

4. **CRDT accepts the update in-place** at `reg/{child_addr}`. The updated policy takes effect for all new `HoldEscrow` calls going forward. Existing escrows are unaffected (§3 Hold-Time Pinning).

### 4.2 Trust Model

Per D-33: "Publishers must trust the child not to redirect payouts — this is a UX/social contract, not a cryptographic constraint."

| Actor | Can Update Policy? | Constraint |
|-------|-------------------|------------|
| Child wallet | Yes — via RegistrationTx at higher sequence | Must hold valid keypair; signature is verified |
| Main wallet | No | Main cannot sign on behalf of child (D-04/D-05) |
| Publisher (via SDK) | No | Cannot update without child's cooperation; SDK only sets initial DevConfig |
| Consensus validators | No | Validate signature, sequence monotonicity, supersedes linkage — do not evaluate policy correctness |

The child controls its own registration lifecycle (per D-04/D-05). The main cannot update the child's reward policy unilaterally. The publisher cannot update it without the child's cooperation. This is consistent with the child-owned identity model: the child is the sovereign controller of its own registration data.

### 4.3 Sequence Ordering

The `sequence` field provides the ordering: CRDT merges keep the highest-sequence RegistrationTx as authoritative, so the latest child-signed update wins. The `sequence` monotonicity gate (Phase 2 D-13, gate 3) ensures only higher-sequence updates are accepted, preventing replay of stale policy values at lower sequences.

### 4.4 Proto Fields Used

The policy update reuses existing `RegistrationTx` fields without requiring new proto additions specifically for reward policy:

| Field | Number | Phase | Purpose in Policy Update |
|-------|--------|-------|--------------------------|
| `metadata` | 4 | Phase 1 | Carries `RegistrationMetadata.dev_wallet` and `RegistrationMetadata.peers_cut` — the updated reward policy values |
| `sequence` | 3 | Phase 1 | Monotonic counter — ensures the update is newer than the current registration |
| `supersedes_sequence` | 6 | Phase 3 (D-38) | Links to the registration being replaced — prevents fork attacks |

The `RegistrationMetadata` sub-message (Phase 1 D-08) carries `game_id`, `publisher_id`, `dev_wallet`, and `peers_cut`. A policy update RegistrationTx may change only `dev_wallet` and/or `peers_cut` while keeping `game_id` and `publisher_id` unchanged. The full `RegistrationMetadata` is submitted — the CRDT merge replaces the entire sub-message, so all fields must be present even if only some values change.

### 4.5 Conflict Scenario: Competing Policy Updates

If the child issues two competing policy-update RegistrationTx entries (e.g., one redirecting payouts to wallet A, another to wallet B, both at the same supersedes_sequence), the conflict is resolved deterministically:

1. Each RegistrationTx flows through the nonce chain (`sgns.nonce.v1`, `Consensus.hpp:37`).
2. The first to reach consensus at its nonce wins — its `sequence` is committed.
3. The second reaches `FilterRegistration` gate 3b: its `supersedes_sequence` no longer matches the now-updated `current.sequence` → REJECTED.

This is the same conflict resolution mechanism as lifecycle updates (§9). The nonce chain provides total ordering; the supersedes_sequence gate provides fork detection. Combined: deterministic first-to-consensus-wins.

**References:**
- Phase 2 `02-01-PLAN.md` — FilterRegistration gate (D-13) with 3 existing gates
- `TransactionManager.cpp:2984-3039` — `FilterTransaction` `do{...}while(0)` template
- `TransactionManager.cpp:4361-4383` — `CheckTransactionAuthorization` (signature-only)
- `Consensus.hpp:37` — `NONCE_SUBJECT_TYPE = "sgns.nonce.v1"`
- `TransactionManager.cpp:149-159` — nonce handler registration
- RESEARCH.md §Pattern 2 — CRDT Filter Gate for supersedes_sequence
- `03-CONTEXT.md` — D-33 (child-only updates, publisher trust model)

**Traceability:** RWD-03

---

## 5. PayDev Path for Registered Children

For registered children, the developer payout path (`PayDev`) must resolve the target developer wallet from `RegistrationMetadata.dev_wallet` (from the certified `reg/{child_addr}` CRDT record) instead of `dev_config_.Addr`.

### 5.1 Current Path

`GeniusNode::PayDev` (`GeniusNode.hpp:520-521`, `GeniusNode.cpp:2261-2264`) currently reads `dev_config_.Addr`:

```
GeniusNode::PayDev(uint64_t amount, TokenID token_id) {
    return TransferFunds(amount, dev_config_.Addr, token_id);
}
```

This is correct for standalone children — the developer address is configured via the SDK's `DevConfig_st`.

### 5.2 Registered Child Extension

For registered children, the `PayDev` method (or a wrapper at the `GeniusNode` level) should resolve the developer wallet as follows:

1. Look up the certified `reg/{child_addr}` CRDT record.
2. If the child is registered (certified record exists, `main_address` non-empty, `detach_flag == false`): read `RegistrationMetadata.dev_wallet` for the payout destination.
3. If the child is standalone (no certified reg/ record): fall back to `dev_config_.Addr` (current behavior).
4. Call `TransferFunds(amount, resolved_dev_wallet, token_id)`.

This is a `GeniusNode`-level change — the caller chooses the target address based on child registration status. No change to the `TransferFunds` method or the underlying transaction infrastructure is needed.

### 5.3 Integration Point

This mirrors the HoldEscrow policy-source selection (§2): both `HoldEscrow` (reward policy at escrow creation time) and `PayDev` (developer payout at escrow release time) must resolve the correct target address from the child's registration status. The same two-mode lookup (certified reg/ → RegistrationMetadata; no reg/ → DevConfig) applies at both integration points.

### 5.4 PayDev vs HoldEscrow: Two Integration Points

| Integration Point | Timing | Policy Source | Stored In | Changed? |
|-------------------|--------|---------------|-----------|----------|
| `HoldEscrow` | Escrow creation | RegistrationMetadata (registered) or DevConfig (standalone) | `EscrowTransaction.dev_addr_` / `peers_cut_` | Yes — adds `reg/` CRDT lookup before HoldEscrow call |
| `PayDev` | Escrow release (developer payout) | RegistrationMetadata (registered) or DevConfig (standalone) | Not stored — read at payout time | Yes — adds `reg/` CRDT lookup in `GeniusNode::PayDev` |

The key distinction: `HoldEscrow` pins the policy at creation time (immutable per §3); `PayDev` reads the policy at payout time. For `PayDev`, the policy at payout time is the authoritative one — the developer wallet address is resolved fresh from the current registration state. This means a child updating its `dev_wallet` mid-flight (after escrow creation but before payout) would redirect the developer payout to the new address. This is intentional per D-33: the child controls its own reward policy, and `PayDev` reads the current policy, not a pinned snapshot.

**References:**
- `GeniusNode.hpp:520-521` — PayDev signature
- `GeniusNode.cpp:2261-2264` — current PayDev reads `dev_config_.Addr`
- PATTERNS.md Analog 3c — PayDev extension pattern
- Phase 2 `02-01-PLAN.md` — certified `reg/{child_addr}` CRDT lookup


---

## 6. Lifecycle State Machine

**Requirement:** LIFE-01

Per D-34: "The lifecycle state machine has four states. States are derived from the `reg/{child_addr}` CRDT record's fields — no separate state-machine engine is needed."

### 6.1 State Definitions

| State | CRDT Condition | Description |
|-------|---------------|-------------|
| **Unregistered (standalone)** | No `reg/{child_addr}` record exists | Child operates independently. Reward policy from SDK DevConfig (D-30). Can receive, hold, transfer assets. No main-wallet association. |
| **Registered** | `reg/{child_addr}` exists with non-empty `main_address` AND `detach_flag == false` | Main has recovery authority (CONS-02). Child broadcast is active (D-15/D-16). Reward policy from RegistrationMetadata (or DevConfig fallback for pre-certification escrows). Main subscribes to child pubsub channels for state sync (D-17). |
| **Detached** | `reg/{child_addr}` exists with `detach_flag == true` AND initiator was the child (child-signed RegistrationTx with detach_flag) | Main has read-only visibility (inspect history/balance), zero recovery authority. Child retains all UTXOs. Former main can inspect the audit trail. |
| **Revoked** | `reg/{child_addr}` exists with `detach_flag == true` AND initiator was the main (main-signed RevokeTx) | Same CRDT outcome as Detached (same `detach_flag`), different initiator. Main has read-only visibility, zero recovery authority. Child can re-register at any time (D-36). |

### 6.2 Design Rationale: States NOT Present

Per D-34, two states from the original architecture proposal are intentionally excluded:

- **No "registration-pending" state:** With child-signed-only registration (D-04/D-05), registration is immediate upon certification — there is no main-consent gate that would create a pending window. The child signs, the CRDT stores, consensus certifies — no waiting for external approval.
- **No "closed" state:** Child wallets are accounts with keypairs; they don't "close." If the key is lost, funds are unrecoverable (inherent property of the keypair model, not a lifecycle transition). The `reg/` record is retained as an audit trail — it is never deleted.

### 6.3 Valid Transitions

| From | To | Initiator | Mechanism | D-# |
|------|----|-----------|-----------|-----|
| Unregistered | Registered | Child | Child signs `RegistrationTx`; CRDT writes to `reg/{child_addr}`; consensus certifies (D-06, D-26) | D-34 |
| Registered | Detached | Child | Child signs new `RegistrationTx` with higher `sequence`, `detach_flag = true`, `supersedes_sequence = current.sequence` (§7) | D-35, D-38 |
| Registered | Revoked | Main | Main signs `RevokeTx`; consensus validates main sig + `main_address` match + Registered state (§8) | D-36 |
| Detached | Registered | Child | Child signs new `RegistrationTx` with higher `sequence`, new/updated `main_address`, `supersedes_sequence = current.sequence` (re-registration) | D-38, D-39 |
| Revoked | Registered | Child | Same as Detached → Registered — child re-registers with higher `sequence` (D-36: "child can re-register at any time") | D-38, D-39 |

Per D-39: "Detached/Revoked do NOT transition back to Unregistered — the `reg/` record is retained as an audit trail. The child re-registers directly to Registered with a new `main_address`."

### 6.4 State Machine Diagram

```
                    ┌──────────────┐
                    │              │
                    │ UNREGISTERED │  (standalone)
                    │              │
                    └──────┬───────┘
                           │ child signs RegistrationTx
                           │ (D-06, D-26)
                           ▼
                    ┌──────────────┐
         ┌─────────│              │──────────┐
         │         │  REGISTERED  │          │
         │         │              │          │
         │         └──────────────┘          │
         │                │                  │
         │ child signs    │                  │ main signs
         │ RegistrationTx │                  │ RevokeTx
         │ (detach_flag)  │                  │ (D-36)
         │ (D-35)         │                  │
         ▼                │                  ▼
  ┌──────────────┐        │         ┌──────────────┐
  │              │        │         │              │
  │  DETACHED    │        │         │   REVOKED    │
  │              │        │         │              │
  └──────┬───────┘        │         └──────┬───────┘
         │                │                │
         │ child re-registers              │ child re-registers
         │ (higher sequence,               │ (higher sequence,
         │  new main_address)              │  new main_address)
         │ (D-38, D-39)                    │ (D-38, D-39)
         │                │                │
         └────────────────┼────────────────┘
                          │
                          ▼
                   ┌──────────────┐
                   │  REGISTERED  │  (re-registered)
                   └──────────────┘
```

**References:**
- Phase 2 `02-01-PLAN.md` — `reg/` CRDT namespace (D-11/D-12)
- `SGTransaction.proto` — `RegistrationTx` message, fields 1-6
- Phase 1 `01-01-SUMMARY.md` — RegistrationTx schema
- `03-CONTEXT.md` — D-34 (four states, no pending/closed)

**Traceability:** LIFE-01

---

## 7. Detach Flow — Child-Initiated

**Requirements:** LIFE-01 (detach transition), LIFE-02 (supersedes_sequence linkage)

Per D-35: "The child issues a new `RegistrationTx` with a higher `sequence` number and a `detach_flag = true`. The `reg/` CRDT record is updated in-place."

### 7.1 Detach Procedure

1. **Child constructs `RegistrationTx`** with:
   - `main_address` cleared (or set to zero-address) — severs the parent-child link
   - `sequence = current.sequence + 1` — monotonic increment
   - `detach_flag = true` — marks the lifecycle transition
   - `supersedes_sequence = current.sequence` — chain-of-custody linkage (D-38)
   - Remaining `RegistrationMetadata` fields retained (game_id, publisher_id, dev_wallet, peers_cut preserved for audit)

2. **Child signs** with its own keypair (D-04/D-05). No main signature is required.

3. **`FilterRegistration` validates** (see Phase 2 `02-01-PLAN.md`, D-13):
   - Gate 2: child signature valid (`CheckTransactionAuthorization`, `TransactionManager.cpp:4361-4383`)
   - Gate 3: `sequence > current.sequence` (monotonicity)
   - Gate 3b (Phase 3 extension): `supersedes_sequence == current.sequence` (fork prevention, D-38)

4. **Nonce chain** (`sgns.nonce.v1`, `Consensus.hpp:37`) prevents double-detach at same nonce: only one transaction per nonce slot can be certified, and the nonce chain tracks consumed nonces.

5. **CRDT updates** `reg/{child_addr}` in-place: `main_address` cleared, `detach_flag = true`, `sequence` incremented.

### 7.2 Post-Detach State

- Child retains all UTXOs — no transfer or burn occurs during detach.
- Child can continue transacting independently (create transfers, receive funds, earn processing rewards).
- Former main has **read-only visibility**: can inspect the child's history and balance via CRDT sync (D-17), but has **zero recovery authority**.
- The `reg/` record is retained as an audit trail — it is NOT deleted.

### 7.3 Detach Protections

| Protection | Mechanism | Anchor |
|-----------|-----------|--------|
| Fork prevention | `supersedes_sequence == current.sequence` (gate 3b) | `TransactionManager.cpp:2984-3039` (filter template) |
| Replay prevention | `sequence > current.sequence` (gate 3) + nonce chain | Phase 2 D-13 (gate 3), `Consensus.hpp:37` (`sgns.nonce.v1`) |
| Unauthorized detach | Child signature verification (gate 2) | `TransactionManager.cpp:4361-4383` (`CheckTransactionAuthorization`) |

**Traceability:** LIFE-01 (detach transition), LIFE-02 (supersedes_sequence linkage)

---

## 8. Revoke Flow — Main-Initiated

**Requirements:** LIFE-01 (revoke transition), LIFE-02 (supersedes_sequence linkage)

Per D-36: "The main issues a main-signed consensus transaction that targets the child's `reg/` record and sets the `detach_flag`."

### 8.1 RevokeTx Design Recommendation

**Recommendation: First-class `RevokeTx` as a new `GeniusTransaction` subclass** — NOT a flagged transfer.

**Rationale:**
- Keeps authority actions separate from value transfers — cleaner audit trail
- Avoids overloading the transfer type with lifecycle semantics
- Follows the same design pattern as `RegistrationTx` (Phase 1 D-06)
- Dedicated validation path in `CheckParentChildAuthority` (gate 2.5)

### 8.2 RevokeTx Proto Message

```
message RevokeTx {
    DAGStruct dag_struct = 1;            // Standard tx field 1
    bytes child_address = 2;             // Address of child wallet being revoked
    uint64 registration_sequence = 3;    // Sequence of reg/ record being revoked
}
```

New `EmbeddedTransaction` oneof arm in `Consensus.proto:70-80`:
```
revoke = 9   // Phase 3 (NEW)
```

### 8.3 Consensus Validation Pipeline

The `RevokeTx` flows through `ValidateTransactionForConsensus` (`TransactionManager.cpp:4234-4304`):

| Gate | Name | Validation | Anchor |
|------|------|-----------|--------|
| 1 | Well-Formed | Proto deserialization succeeds; `dag_struct`, `child_address`, `registration_sequence` present | `TransactionManager.cpp:4250` |
| 2 | Authorization | **Main's signature** is valid over the `RevokeTx` | `TransactionManager.cpp:4259`, `4361-4383` |
| 2.5 | CheckParentChildAuthority | `reg/{child_address}.main_address == signer` AND `reg/{child_address}` is in Registered state (`detach_flag == false`, `main_address != empty`) | Phase 2 D-19 |
| 3 | Timestamp | Within consensus drift tolerance | `TransactionManager.cpp:4268` |
| 4 | Replay Protection | Nonce chain (`sgns.nonce.v1`) prevents double-revoke | `TransactionManager.cpp:4277`, `Consensus.hpp:37` |
| 5 | Type Rules | `registration_sequence` matches `reg/{child_address}.sequence` | `TransactionManager.cpp:4288` |

### 8.4 Post-Revoke State

- `detach_flag = true` set on `reg/{child_address}` CRDT record.
- Main has **zero recovery authority** thereafter — revocation is final for THAT main.
- The child retains all UTXOs and can transact independently (§10).
- "The child can re-register (to the same or a different main) at any time with a new RegistrationTx at higher sequence — revocation is final for THAT main, not for the child wallet" (D-36).

### 8.5 Revoke vs Detach

| Aspect | Detach | Revoke |
|--------|--------|--------|
| Initiator | Child (child-signed `RegistrationTx`) | Main (main-signed `RevokeTx`) |
| Mechanism | `RegistrationTx` with `detach_flag = true`, `supersedes_sequence` | First-class `RevokeTx` (new `GeniusTransaction` subclass) |
| Proto | `RegistrationTx.detach_flag = 5`, `RegistrationTx.supersedes_sequence = 6` | `RevokeTx` message, `EmbeddedTransaction.revoke = 9` |
| Consensus Gate | `FilterRegistration` gates 2, 3, 3b | `ValidateTransactionForConsensus` gates 1-5 + gate 2.5 |
| CRDT Outcome | Same (`detach_flag = true`) | Same (`detach_flag = true`) |
| Audit Trail | Record retained | Record retained |

**References:**
- `Consensus.proto:70-80` — `EmbeddedTransaction` oneof (existing arms 1-7; RegistrationTx=8; RevokeTx=9)
- `TransactionManager.cpp:4234-4304` — 5-gate consensus pipeline
- `TransactionManager.cpp:4361-4383` — `CheckTransactionAuthorization` (signature-only)
- RESEARCH.md §Open Question #3 — first-class `RevokeTx` recommendation
- PATTERNS.md §2 Proto Additive — RevokeTx message shape, Analog 2c
- PATTERNS.md §4 — `ValidateTransactionForConsensus` pipeline with RevokeTx gate path

**Traceability:** LIFE-01 (revoke transition), LIFE-02 (supersedes_sequence linkage via registration_sequence check)

---

## 9. Replace Main + Policy Fork Decision

**Requirements:** LIFE-02 (supersedes sequence linkage), LIFE-03 (main replacement policy fork)

### 9.1 Main Replacement Flow

Per D-37: "Main replacement is child-only — no consent signature is required from the old main."

1. **Child constructs `RegistrationTx`** with:
   - New `main_address` (different from current)
   - `sequence = current.sequence + 1`
   - `detach_flag = false` (this is a replacement, not a detach)
   - `supersedes_sequence = current.sequence`

2. **Child signs** with its own keypair (D-04/D-05).

3. **`FilterRegistration` validates:**
   - Gate 2: child signature
   - Gate 3: `sequence > current.sequence`
   - Gate 3b: `supersedes_sequence == current.sequence`

4. **Old main loses recovery rights** over future balances; **new main gains recovery rights** going forward. Existing escrows are unaffected (§3).

### 9.2 Policy Fork Decision (LIFE-03)

**Decision: Child-only replacement** — no consent signature is required from the old main.

**Rationale (D-37):**
- **Deadlock avoidance:** Requiring old-main consent would create a deadlock if the old main's key is lost — the child would be permanently bound to an unreachable main.
- **Child-owned identity model:** Consistent with D-04/D-05 — registration is child-signed-only and grants the main zero authority over the child's UTXOs. Recovery requires the main's own signature at spend time (D-21). The main's authority is bounded to specific, signature-gated actions (fund, recover, revoke).
- **Publisher independence:** A publisher who registers a child through one main wallet may later need to re-register through a different main without the first main's cooperation.

**Alternatives considered and rejected:**
- **Dual-signature replacement (child + old main):** Rejected — creates deadlock risk; contradicts child-owned identity model.
- **Main-only replacement:** Rejected — main cannot sign on behalf of child (D-04/D-05); grants main excessive control over child's registration lifecycle.

### 9.3 Conflict Resolution: Supersedes Sequence + Nonce Chain

Per D-38: "Every lifecycle-change RegistrationTx carries a `supersedes_sequence` field referencing the `sequence` of the registration it replaces."

**CRDT Filter Gate 3b (FilterRegistration extension):**

When `RegistrationTx.supersedes_sequence != 0`, the filter rejects the update unless `supersedes_sequence == current_registration.sequence()`. This prevents race-condition forks where two competing updates both try to replace the same base registration.

```
// Gate 3b pseudocode (inserted after existing sequence monotonicity gate):
if (new_registration.has_supersedes_sequence() &&
    new_registration.supersedes_sequence() != 0) {
    auto current = ReadRegistrationFromCRDT(child_addr);
    if (!current || current.sequence() != new_registration.supersedes_sequence()) {
        // REJECT — fork detected
        break;
    }
}
```

**Nonce Chain Total Ordering (`sgns.nonce.v1`):**

RegistrationTx flows through `HandleNonceConsensusSubject` (`TransactionManager.cpp:149-159`). The nonce chain allows only one transaction per nonce slot. Two RegistrationTx updates at different nonces but the same `supersedes_sequence` cannot both be certified — the first to reach consensus at its nonce wins; the second fails at the CRDT filter because the current `sequence` has already been bumped by the first.

**Result:** Deterministic **first-to-consensus-wins** — NOT first-to-CRDT-wins. Consensus ordering, not CRDT arrival order, determines the winner.

### 9.4 Replay Attack Prevention

Per T-03-12: If an attacker replays an old lifecycle RegistrationTx at a higher nonce:
- **Gate 3:** `sequence > current.sequence` — the old tx has a lower or equal sequence → REJECTED.
- **Nonce chain:** Reuse of an already-consumed nonce → REJECTED by `HandleNonceConsensusSubject`.

Combined: neither old sequences nor old nonces pass validation.

**References:**
- `TransactionManager.cpp:2984-3039` — `FilterTransaction` `do{...}while(0)` template
- `TransactionManager.cpp:149-159` — nonce handler registration (`sgns.nonce.v1`)
- `Consensus.hpp:37` — `NONCE_SUBJECT_TYPE = "sgns.nonce.v1"`
- `03-CONTEXT.md` — D-37 (child-only replacement, deadlock rationale), D-38 (supersedes sequence)
- PATTERNS.md §5 Analog 5c — supersedes_sequence gate pseudocode

**Traceability:** LIFE-02 (supersedes_sequence linkage + conflict resolution), LIFE-03 (main replacement policy fork)

---

## 10. Detach Semantics

**Requirement:** LIFE-04

Per D-39: "Detaching (or being revoked) leaves the child wallet as a valid standalone wallet. The child's UTXOs, keypair, and nonce are unaffected — only the `reg/` record's status changes."

### 10.1 What Is Unaffected

| Child Asset | Status After Detach/Revoke | Rationale |
|-------------|---------------------------|-----------|
| **Address** | Unchanged | The child's secp256k1 keypair (`eth_keypair_` in `GeniusAccount`) is independent of registration status |
| **Keypair** | Unchanged | Keypair is generated at wallet creation (IDENT-01); detach does not rotate, revoke, or invalidate it |
| **Nonce counter** | Unchanged | `confirmed_nonces_`, `GetProposedNonce`, `ReserveNextNonce` are internal to the child's `GeniusAccount` — registration status does not affect nonce state |
| **UTXOs** | Unchanged | All UTXOs remain owned by the child's address (`UTXOEntryRecord.owner_address == child_address`) — no UTXO transfer or burn occurs during detach/revoke |
| **Escrow transactions** | Unchanged | In-progress escrows continue to completion per §3 — immutable policy pinned at HoldEscrow time |
| **Transaction history** | Unchanged | All prior transactions remain in the child's CRDT namespace — detach does not purge history |

### 10.2 What Changes

| Aspect | Before Detach/Revoke | After Detach/Revoke |
|--------|---------------------|---------------------|
| **reg/ record** | `detach_flag == false` | `detach_flag == true` |
| **Main's recovery authority** | Granted (CONS-02) | Revoked — zero authority |
| **Main's read access** | Granted (D-17, pubsub sync) | Read-only visibility retained (inspect history) |
| **Reward policy source** | RegistrationMetadata (if registered) or DevConfig | Returns to DevConfig (standalone) for new escrows |
| **Registration lifecycle** | In Registered state | Can re-register at any time with higher sequence |

### 10.3 Design Invariants

1. **Detach/revoke does NOT destroy the child wallet** — it only severs the parent-child authority relationship. The child's address, keypair, nonce, UTXOs, and transaction history are all preserved.

2. **The detached/revoked `reg/` record serves as an audit trail** — it preserves the history of the parent-child relationship, including the original registration timestamp, all lifecycle transitions, and the final state. The record is retained indefinitely; it is never deleted.

3. **Re-registration continues from the current `sequence`** — if the child later re-registers (to the same or a different main), the `reg/` record is updated in-place with `sequence = current.sequence + 1`, `detach_flag = false`, and the new `main_address`. The prior registration history is preserved in the record's earlier CRDT deltas.

4. **Standalone operation is always valid** — the child wallet can create transfers, receive funds, and earn processing rewards independently, with or without a registered main. Registration is an opt-in capability that adds main-wallet association without changing the child's fundamental account properties.

**References:**
- Phase 1 `01-01-PLAN.md` — IDENT-01 (keypair model), IDENT-02 (nonce tracking), IDENT-04 (UTXO ownership)
- `GeniusAccount.hpp` — `eth_keypair_`, `confirmed_nonces_`, `GetProposedNonce`, `ReserveNextNonce`
- `GeniusUTXO.hpp`, `UTXOStructs.hpp` — `UTXOEntryRecord.owner_address`
- `03-CONTEXT.md` — D-39 (detach leaves child as valid standalone wallet)

**Traceability:** LIFE-04

---

## 11. Proto Evolution Summary

All Phase 3 proto changes are additive — no existing field numbers are modified, no existing messages are removed. Backward compatibility is maintained: nodes that haven't upgraded ignore unknown fields (protobuf default behavior) and ignore unknown `EmbeddedTransaction` oneof arms.

### 11.1 RegistrationTx Extension (SGTransaction.proto)

| Field | Number | Type | Phase | Purpose |
|-------|--------|------|-------|---------|
| `dag_struct` | 1 | `DAGStruct` | Phase 1 | DAG linking (standard tx field 1) |
| `main_address` | 2 | `bytes` | Phase 1 | Main wallet address (empty = standalone) |
| `sequence` | 3 | `uint64` | Phase 1 | Monotonic registration counter |
| `metadata` | 4 | `RegistrationMetadata` | Phase 1 | Game/publisher/dev-wallet/peers-cut sub-message (D-08) |
| `detach_flag` | 5 | `bool` | Phase 3 | Child-initiated detach (D-35) |
| `supersedes_sequence` | 6 | `uint64` | Phase 3 | Chain-of-custody linkage — references `sequence` being replaced; 0 = new registration (D-38) |

### 11.2 RevokeTx Message (SGTransaction.proto)

| Field | Number | Type | Purpose |
|-------|--------|------|---------|
| `dag_struct` | 1 | `DAGStruct` | DAG linking (standard tx field 1) |
| `child_address` | 2 | `bytes` | Address of child wallet being revoked |
| `registration_sequence` | 3 | `uint64` | Sequence of `reg/` record being revoked |

### 11.3 EmbeddedTransaction Oneof (Consensus.proto)

| Oneof Arm | Field Number | Message | Phase |
|-----------|-------------|---------|-------|
| `transfer` | 1 | `TransferTx` | Existing |
| `mint_v2` | 2 | `MintTxV2` | Existing |
| `mint` | 3 | `MintTx` | Existing |
| `processing` | 4 | `ProcessingTx` | Existing |
| `migration` | 5 | `MigrationTx` | Existing |
| `escrow` | 6 | `EscrowTx` | Existing |
| `escrow_release` | 7 | `EscrowReleaseTx` | Existing |
| `registration` | 8 | `RegistrationTx` | Phase 1 |
| `revoke` | **9** | `RevokeTx` | **Phase 3 (NEW)** |

### 11.4 Backward Compatibility

- Proto field numbers 1-4 in `RegistrationTx` are unchanged — existing Phase 1 fields are preserved.
- Fields 5 (`detach_flag`) and 6 (`supersedes_sequence`) are appended after existing fields — protobuf wire format is self-describing; older nodes deserialize fields they understand and skip unknown fields.
- `EmbeddedTransaction` oneof arm 9 (`revoke`) is appended after arm 8 (`registration`) — older nodes that receive a `RevokeTx` will not match any known oneof arm and will treat the `EmbeddedTransaction` as having an unknown transaction type (standard protobuf behavior for unknown oneof arms).
- `RegistrationMetadata` sub-message (field 4) is unchanged — existing `dev_wallet` and `peers_cut` fields remain at their Phase 1 field numbers.
- No field renumbering, no message removal, no wire-format breaking changes.

---

## 12. Requirement Traceability

| Requirement | Section(s) | Key Anchor Points | Decision References |
|-------------|-----------|-------------------|---------------------|
| **RWD-01** | §2 Reward Policy Resolution Flow | `GeniusNode.cpp:1977-1985` (DevConfig path), `TransactionManager.cpp:778-810` (HoldEscrow params), `GeniusNode.hpp:59-66` (DevConfig_st), Phase 2 `02-01-PLAN.md` (reg/ CRDT) | D-30, D-31 |
| **RWD-02** | §3 Hold-Time Pinning | `EscrowTransaction.hpp:122-131` (immutability), `TransactionManager.cpp:846-875` (PayEscrow stored reads), `TransactionManager.cpp:848` (GetPeersCut), `TransactionManager.cpp:875` (GetDevAddress) | D-32 |
| **RWD-03** | §4 Authenticated Policy Updates | Phase 2 `02-01-PLAN.md` (FilterRegistration gate), `TransactionManager.cpp:2984-3039` (filter template), `TransactionManager.cpp:4361-4383` (CheckTransactionAuthorization), `Consensus.hpp:37` (nonce chain) | D-33 |
| **LIFE-01** | §6 Lifecycle State Machine, §7 Detach Flow, §8 Revoke Flow | `reg/{child_addr}` CRDT (Phase 2 D-11/D-12), `SGTransaction.proto` RegistrationTx (fields 1-6), `Consensus.proto:70-80` (EmbeddedTransaction oneof), `TransactionManager.cpp:4234-4304` (consensus pipeline) | D-34, D-35, D-36 |
| **LIFE-02** | §7 Detach Flow, §8 Revoke Flow, §9 Replace Main | `TransactionManager.cpp:2984-3039` (filter template, gate 3b superseedes), `Consensus.hpp:37` (NONCE_SUBJECT_TYPE), `TransactionManager.cpp:149-159` (nonce handler), `TransactionManager.cpp:4234-4304` (pipeline) | D-38 |
| **LIFE-03** | §9 Replace Main + Policy Fork | D-37 (child-only replacement with deadlock-avoidance rationale, child-owned identity consistency) | D-37 |
| **LIFE-04** | §10 Detach Semantics | D-39 (UTXOs/keypair/nonce unaffected, standalone validity retained), Phase 1 `01-01-PLAN.md` (IDENT-01/02/04), `GeniusAccount.hpp`, `GeniusUTXO.hpp` | D-39 |

---

## 13. Phase Hand-Offs

### 13.1 Dependencies

This document depends on design decisions and artifacts from prior phases:

| Phase | Document | What It Provides |
|-------|----------|-----------------|
| Phase 1 | `01-01-SUMMARY.md` | `RegistrationTx` schema: `dag_struct=1`, `main_address=2`, `sequence=3`, `RegistrationMetadata` at field 4 with `game_id`, `publisher_id`, `dev_wallet`, `peers_cut`. Child-signed-only model (D-04/D-05). |
| Phase 1 | `docs/child-wallet-identity-model.md` | Independent keypair (IDENT-01), nonce tracking (IDENT-02), UTXO ownership (IDENT-04). |
| Phase 2 | `docs/02-crdt-registry-pubsub.md` | CRDT `reg/` namespace (D-11/D-12), key format `/bc-{net}/reg/{child_addr}`, `FilterRegistration` gate (D-13) with 3 gates, pubsub broadcast (D-15/D-16), certified status (D-26). |
| Phase 2 | `docs/02-consensus-parent-child-authority.md` | `CheckParentChildAuthority` gate (D-19), 6 consensus rules (CONS-01 through CONS-06), main-signed transfer destination restriction (D-21). |
| Phase 3 | `docs/03-01-discovery-monitoring.md` | Discovery push/poll mechanism, per-child information aggregation, main-wallet action mappings (Fund, Recover, Inspect, Revoke, Detach). |

### 13.2 Integration Surface for Future Phases

This document's output provides the authoritative specification for implementation:

- **Policy resolution (§2):** `GeniusNode::ProcessImage` adds `reg/{child}` CRDT lookup before `HoldEscrow` call.
- **Hold-time pinning (§3):** No changes needed — existing `EscrowTransaction` immutability is verified.
- **Policy updates (§4):** `FilterRegistration` extends with gate 3b (`supersedes_sequence` validation).
- **Lifecycle transitions (§6-8):** `RegistrationTx.detach_flag=5`, `RegistrationTx.supersedes_sequence=6`, `RevokeTx` message, `EmbeddedTransaction.revoke=9`.
- **Conflict resolution (§9):** Gate 3b + nonce chain = first-to-consensus-wins.
- **Proto changes (§11):** 6 additive proto additions across 2 proto files — all backward-compatible.

### 13.3 Deferrals to v2

| Concern | v2 Requirement | Reason for Deferral |
|---------|---------------|---------------------|
| Platform "Connect GNUS Wallet" UI flows | PLAT-01, PLAT-02 | Conceptual only in Phase 3; concrete UI wiring in v2 |
| Aggregated registry topic for publisher-scale fan-out | ADV-02 | Current discovery supports many children per main; optimized aggregation layer deferred |
| Threshold/social-recovery scheme for main wallet | ADV-01 | Separate security concern; current auth model is sufficient for v1 |
| Token economics changes | — | Reuse existing escrow split mechanics; no token-economics changes in v1 |
| Optional main acceptance signature | — | Considered and rejected in Phase 1 (D-04/D-05); could be revisited as v2 hardening |

---

*Document version: 1.0*
*Phase: 03-discovery-rewards-lifecycle, Plan 02*
*Covers: RWD-01, RWD-02, RWD-03, LIFE-01, LIFE-02, LIFE-03, LIFE-04*

