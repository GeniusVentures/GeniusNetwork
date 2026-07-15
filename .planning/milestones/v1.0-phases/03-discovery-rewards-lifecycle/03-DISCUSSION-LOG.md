# Phase 3: Discovery, Rewards & Lifecycle - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-14
**Phase:** 03-discovery-rewards-lifecycle
**Areas discussed:** Discovery lookup, Standalone rewards, Main replacement, Detach CRDT handling, Revoke vs detach, Reward policy updates

---

## Discovery CRDT Layout (DISC-01)

| Option | Description | Selected |
|--------|-------------|----------|
| CRDT prefix scan over reg/ | Main scans reg/ namespace, deserializes each record, filters by main_address field. | |
| Dual-entry index namespace | Also write reg-by-main/{main_addr}/{child_addr} pointer. Main queries its own index namespace. | |
| In-memory derived index | Main subscribes to its topic, builds in-memory map from reg/ entries. Non-persistent. | |

**User's choice:** "In general, main wallet will know children through pubsub broadcasts, but there is a chance it may miss this. Wallet should occasionally poll on its channel, through AccountMessenger, 'what child wallets do I have'. A child wallet, or full node, or anyone that happens to know, can respond to this. The main wallet should probably keep this information in a json or something."

**Notes:** Push-primary/poll-fallback model with decentralized responders. No additional CRDT namespace — discovery is peer-to-peer. Local JSON cache for persistence.

---

## Standalone Child Reward Policy (RWD-01)

| Option | Description | Selected |
|--------|-------------|----------|
| SDK DevConfig defaults at hold time | Standalone children use DevConfig_st (Addr, Cut) from SDK init. Registration supersedes. | ✓ |
| No dev cut for standalone | Standalone children get 100% of rewards. Registration required for publisher split. | |
| Game publisher configures at SDK level | Publisher sets dev_wallet/peers_cut at build/deploy time, applied until registration. | |

**User's choice:** "SDK DevConfig defaults at hold time"

**Notes:** Same mechanics as today — no new infrastructure needed. On registration, RegistrationMetadata values supersede for new escrows. Existing escrows retain hold-time policy (already pinned in EscrowTransaction model).

---

## Main Replacement Consent (LIFE-03 fork)

| Option | Description | Selected |
|--------|-------------|----------|
| Child-only replacement (no consent) | Child unilaterally replaces main. Consistent with D-04/D-05. Old main loses recovery rights. | ✓ |
| Require old-main signature | Replacement must be co-signed by old main. Fails closed if old key is lost. | |
| Old-main veto window | Child publishes intent; old main has timeout to veto. Adds timing complexity. | |

**User's choice:** "Child-only replacement (no consent)"

**Notes:** Consistent with child-signed-only model. Rationale: registration grants zero authority over main's funds; recovery requires new main's signature anyway. Deadlock avoidance — old main key loss doesn't trap the child.

---

## Detach CRDT Handling (LIFE-01, LIFE-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Remove the reg/ record entirely | Record deleted. Child indistinguishable from never-registered standalone. | |
| Replace with tombstone record | Record replaced with detached-status entry. Audit trail but no main link. | |
| Keep record, set detached flag | Record stays with detached flag. Main has inspect-only visibility. Child retains UTXOs. | ✓ |

**User's choice:** "Keep record, set detached flag"

**Notes:** Audit trail preserved. Main can inspect history/balances but zero recovery authority. Child functions as standalone wallet with registration history. Detached/revoked never transitions back to Unregistered — the record is retained.

---

## Revoke vs Detach Semantics (LIFE-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Detach = child-initiated, Revoke = main-initiated | Both produce same CRDT outcome (detached flag), different signers. | ✓ |
| Only detach exists — no revoke needed | Main cannot force retention; revoke is client-side (stop listening). | |
| Revoke = main-signed consensus, Detach = child-signed | Same as option 1 but emphasized different tx types/consensus paths. | |

**User's choice:** "Revoke = main-signed consensus, Detach = child-signed"

**Notes:** Two paths to the same CRDT outcome (detached flag set). Revoke is the only main-signed lifecycle action. Consensus validates correct signer per path. Both produce the same result: main loses recovery authority, child continues independently.

---

## Reward Policy Updates (RWD-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Child-only via new RegistrationTx | Child issues RegistrationTx at higher sequence with updated metadata. | ✓ |
| Main-only via revoke+replace flow | Only main can update dev_wallet/peers_cut. Gives publisher control. | |
| No updates after registration | Metadata immutable after first registration. Change requires detach+re-register. | |

**User's choice:** "Child-only via new RegistrationTx"

**Notes:** Consistent with child-signed-only model. Publishers trust the child not to redirect — social contract, not cryptographic constraint. The sequence field provides ordering; reg/ CRDT merge keeps highest-sequence update.

---

## the agent's Discretion

- Exact proto field additions for detach_flag, supersedes_sequence, and revoke transaction message
- AccountMessenger mechanism for discovery polling — extend existing messaging_watcher pattern
- Local JSON cache schema and file location for discovered-children list
- Lifecycle state machine diagram and transition table
- Naming of revoke transaction subclass and file placement

## Deferred Ideas

- Platform "Connect GNUS Wallet" UI flows — v2 (PLAT-01, PLAT-02)
- Aggregated registry topic for publisher-scale fan-out — v2 (ADV-02)
- Threshold/social-recovery scheme for main wallet — v2 (ADV-01)
- Optional main acceptance signature for registration — considered/rejected Phase 1, possible v2 hardening
