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

