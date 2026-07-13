# Pitfalls Research

**Domain:** Child-wallet + consensus authority over CRDT/pubsub/UTXO (GNUS SuperGenius)
**Researched:** 2026-07-13
**Confidence:** HIGH (domain-specific, grounded in SuperGenius audit + proposal)

> The dominant theme: **CRDT is eventually consistent with no total order, but replay/authority protection normally assumes a total order.** Nearly every hard pitfall below flows from that tension. The design docs must state how consensus imposes the ordering that plain CRDT deltas do not.

## Critical Pitfalls

### Pitfall 1: Registration replay / reorder under eventual consistency

**What goes wrong:**
An old registration delta (e.g., pointing to an attacker-favorable main, or an already-superseded state) re-merges into a peer's CRDT after a newer one, and is treated as current.

**Why it happens:**
CRDT deltas can arrive in any order and be re-gossiped indefinitely; there is no inherent "latest" without an explicit ordering key. Timestamps are spoofable and clocks skew.

**How to avoid:**
Every registration/change carries a strictly monotonic per-child sequence number. Consensus (not CRDT merge alone) selects the highest valid seq as authoritative; lower-seq records are ignored/tombstoned. The record is only authoritative after consensus validation, not upon CRDT arrival.

**Warning signs:**
Design resolves conflicts by timestamp; "last writer wins" without a seq; authority read directly from CRDT before consensus confirmation.

**Phase to address:** Consensus-rules design doc + Lifecycle/change-flow design doc.

---

### Pitfall 2: Main-wallet reassignment race / split-brain

**What goes wrong:**
Two registrations for the same child (e.g., two different mains, or replace-vs-detach) coexist; different nodes disagree on the child's current main.

**Why it happens:**
Concurrent registration transactions with the same or unordered seq; no defined tie-break; CRDT converges to a set, not a single winner.

**How to avoid:**
Define a deterministic total order: (seq, then a consensus-defined tie-break such as tx hash). Reject equal-seq competitors deterministically. Require the new registration to reference the prior seq it supersedes.

**Warning signs:**
Two "active" registrations materialize; replace flow lacks "supersedes seq N" linkage; no equal-seq tie-break rule.

**Phase to address:** Lifecycle/change-flow design doc.

---

### Pitfall 3: Recovery authority becomes seizure

**What goes wrong:**
"Main can recover from child" is designed as an unrestricted parent transfer, so a compromised main key (or over-broad rule) drains a child to an arbitrary destination.

**Why it happens:**
Recovery is modeled as generic delegated spend without destination constraints.

**How to avoid:**
Restrict main-recover-from-child so destination == registered main address (unless the protocol explicitly and deliberately widens it). Make the constraint a consensus rule, not a UI convention.

**Warning signs:**
Recovery transaction allows arbitrary destination; no destination check in the delegated-spend validator branch.

**Phase to address:** Consensus-rules design doc.

---

### Pitfall 4: Child-spends-main leakage via ownership conflation

**What goes wrong:**
Adding delegated authority accidentally lets a child key authorize spends of main-owned UTXOs.

**Why it happens:**
Existing ownership check is `payload_owner == src_address` (GeniusInputValidator.cpp:421). Bolting authority onto this path can invert the direction (child acting as main).

**How to avoid:**
Keep a separate, explicit authorization branch: main→child and main-recover are authorized by the *main* signature + registration; there is no rule that authorizes a child signature to move main funds. Add an explicit invariant test: "no child-signed tx can spend main UTXOs."

**Warning signs:**
Authority check is symmetric; a single code path handles both directions; missing negative test for child-spends-main.

**Phase to address:** Consensus-rules design doc (with an explicit rejection rule).

---

### Pitfall 5: Trusting pubsub topic membership as authorization

**What goes wrong:**
A malicious peer publishes a forged registration on the main's channel and it is accepted, or spoofs a child channel to feed false balances.

**Why it happens:**
Gossip topics are open; delivery ≠ authenticity. Designers conflate "arrived on the right topic" with "authorized."

**How to avoid:**
Authority derives ONLY from dual signatures + consensus validation. Pubsub is a transport for discovery/broadcast, never a trust boundary. Balance/asset display must be reconciled against consensus-validated CRDT state, not raw pubsub messages.

**Warning signs:**
Registration accepted based on topic; balances shown from unvalidated pubsub payloads; no signature check on discovery data.

**Phase to address:** CRDT/pubsub design doc + Discovery design doc.

---

### Pitfall 6: Child-key compromise blast radius creep

**What goes wrong:**
Compromise of a child key yields more than the child's assets — e.g., ability to reassign the main, or affect other children.

**Why it happens:**
Reassignment allowed with child signature alone; shared child keys across apps; child metadata influences unrelated accounts.

**How to avoid:**
Explicitly bound child authority: a child key can spend its own assets and (per policy) may propose main replacement, but the design must decide whether replacement requires existing-main consent (safer vs theft) or not (easier recovery). Never share a child key across apps. Guarantee at consensus level: child compromise cannot touch main funds or unrelated children.

**Warning signs:**
Replacement requires only child sig with no guard; shared-key sharing "feature" appears; child action mutates another account's state.

**Phase to address:** Security/consensus design doc + Lifecycle design doc.

---

### Pitfall 7: Proto schema evolution breaks existing builds

**What goes wrong:**
New registration fields renumber or repurpose existing proto fields, breaking SuperGenius/GeniusSDK/GeniusWallet deserialization on deployed nodes.

**Why it happens:**
Editing existing messages in place; reusing field numbers; making new fields required.

**How to avoid:**
Additive-only: new top-level messages, new oneof arms, optional new fields with fresh field numbers. Never renumber. Document a compatibility matrix.

**Warning signs:**
Diff touches existing field numbers; `required` fields added; existing message semantics changed.

**Phase to address:** Registration-protocol design doc.

---

### Pitfall 8: Reward-split edge cases for standalone vs registered children

**What goes wrong:**
A standalone child earns rewards but has no resolvable `dev_addr`/policy, or a registered child's policy changes mid-escrow, causing misrouted or stuck payouts.

**Why it happens:**
Reward routing assumes a single `dev_addr` (escrow HoldEscrow/PayEscrow, TxMgr.cpp:778,812); child policy resolution and change-timing are unspecified.

**How to avoid:**
Design an explicit per-child policy resolution (default vs configured), and pin the policy at escrow-hold time so mid-flight changes don't affect in-progress payouts. Ensure standalone children still have a valid split path.

**Warning signs:**
No policy for standalone children; policy read at release time instead of hold time; missing default.

**Phase to address:** Reward-policy design doc.

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Timestamp ordering instead of seq | Simpler record | Replay/hijack vulnerability | Never for authority |
| Authority in wallet metadata only | Fast to prototype | Not consensus-enforceable | Never (proposal forbids) |
| Reusing ownership path for delegation | Less new code | Child-spends-main risk | Never |
| Open-destination recovery | Flexible | Seizure risk | Only if protocol explicitly designs broader parent transfers with safeguards |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Main key ever enters game/child process | Full main compromise | Out-of-process Connect-GNUS-Wallet signing |
| Single-signature registration | Fraudulent/unsolicited links | Require child + main dual signatures |
| No seq on registration | Replay/reorder hijack | Monotonic per-child seq + consensus order |
| Accepting discovery data from pubsub unvalidated | False balances, spoofed children | Validate against consensus CRDT state + signatures |
| Shared child key across apps | Cross-app total compromise | One child per app; publisher grouping in UI |

## "Looks Done But Isn't" Checklist

- [ ] **Registration record:** often missing the "supersedes seq N" linkage — verify replace/detach reference prior seq.
- [ ] **Consensus rules:** often missing the explicit *negative* rule (child cannot spend main) — verify a dedicated rejection rule + test.
- [ ] **Recovery:** often missing destination restriction — verify destination == registered main is enforced by consensus.
- [ ] **Discovery:** often missing signature/consensus validation of displayed data — verify balances come from validated CRDT state.
- [ ] **Proto changes:** often missing compatibility matrix — verify additive-only and no renumbering.
- [ ] **Reward policy:** often missing standalone-child path and hold-time policy pinning.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Replay accepted an old registration | HIGH | Requires consensus rule fix + re-materialize latest seq; potential re-registration |
| Split-brain registration | HIGH | Define tie-break, re-run consensus resolution, tombstone loser |
| Seizure via open recovery | HIGH | Add destination restriction; affected funds may already be lost |
| Broken proto compat | MEDIUM | Revert field changes, ship additive-only version, coordinate node upgrade |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase (design doc) | Verification |
|---------|-------------------------------|--------------|
| Replay/reorder | Consensus rules + Lifecycle | Design specifies seq + consensus ordering + tombstoning |
| Reassignment split-brain | Lifecycle/change flow | Deterministic (seq, tie-break) + supersedes linkage |
| Recovery seizure | Consensus rules | Destination-restriction rule present |
| Child-spends-main | Consensus rules | Explicit rejection rule + negative test spec |
| Pubsub trust | CRDT/pubsub + Discovery | Authority = signatures+consensus only |
| Child blast radius | Security/Lifecycle | Bounded-authority statement + policy fork decided |
| Proto compat | Registration protocol | Additive-only + compatibility matrix |
| Reward edge cases | Reward policy | Standalone path + hold-time pinning |

## Sources

- SuperGenius audit: `GeniusInputValidator.cpp:421`, `TransactionManager.cpp` (4361/2984/778/812), CRDT `globaldb`, `SGTransaction.proto` — HIGH
- `GNUS_Subwallet_Architecture_Proposal.md` (§Security Model, §Changing Registered Main, §Consensus Rules) — HIGH
- `.planning/codebase/CONCERNS.md` — existing concerns — MEDIUM
- CRDT eventual-consistency vs consensus-ordering literature (general) — HIGH conceptual

---
*Pitfalls research for: child-wallet design on SuperGenius*
*Researched: 2026-07-13*
