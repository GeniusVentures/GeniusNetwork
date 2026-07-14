---
phase: 03-discovery-rewards-lifecycle
reviewed: 2026-07-13T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - docs/03-01-discovery-monitoring.md
  - docs/03-02-reward-policy-lifecycle.md
findings:
  critical: 1
  warning: 2
  info: 3
  total: 6
status: issues_found
---

# Phase 03: Code Review Report — Discovery, Rewards & Lifecycle

**Reviewed:** 2026-07-13
**Depth:** standard (per-file analysis with cross-document consistency checks)
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Phase 03 produced two design-documentation deliverables: a discovery & monitoring design (03-01) and a reward-policy & lifecycle design (03-02). Both documents are thorough, well-organized, and map every concept to concrete SuperGenius anchor points (file paths, proto fields, line numbers). The cross-document linkages between the two artifacts are consistent.

One **critical** finding was discovered: the Per-Child Information table in 03-01 §4.1 contains an incorrect field mapping for the "Child address" row, which both references the wrong proto field (`main_address` instead of the CRDT key) and contradicts the row immediately below it. This would mislead an implementer into reading the wrong data for the child wallet's address, potentially causing incorrect wallet behavior.

Two **warnings** relating to ambiguous cross-phase references and a subtle design tension between hold-time pinning claims and the PayDev payout path. Three **info-level** notes on under-specified data sources and line-range typos.

The documents are otherwise well-structured, internally consistent, and implementation-ready — with the noted corrections.

---

## Critical Issues

### CR-01: "Child address" incorrectly mapped to `RegistrationTx.main_address` in Per-Child Information table

**File:** `docs/03-01-discovery-monitoring.md:301`

**Issue:** The "Child address" row in the Display Field → Data Source mapping table (§4.1) states:

> `RegistrationTx.main_address` (field 2) — the child wallet's address

This is incorrect. `RegistrationTx.main_address` (field 2) stores the **main (parent) wallet's address** — this is the anchor the main uses to discover which children belong to it. The row immediately below ("Main address") correctly identifies `RegistrationTx.main_address` (field 2) as "the registered parent," creating a direct contradiction within the same table.

The child wallet's address is the key component in the CRDT key `reg/{child_addr}` (Phase 2 D-12) — it is NOT stored as a separate field in the `RegistrationTx` proto message. An implementer following this table literally would attempt to read `RegistrationTx.main_address` and treat it as the child address, leading to data corruption in the per-child aggregator.

**Fix:**

```markdown
| Child address | Derived from CRDT key `reg/{child_addr}` — the `{child_addr}` component | `reg/{child_addr}` CRDT key (D-12, `docs/02-crdt-registry-pubsub.md` §2) |
| Main address | `RegistrationTx.main_address` (field 2) — the registered parent | `reg/{child_addr}` CRDT |
```

---

## Warnings

### WR-01: D-17 incorrectly cited as the anchor for main's own-topic subscription in push path

**File:** `docs/03-01-discovery-monitoring.md:52`

**Issue:** Step 4 of the push-path flow (§2.1) states:

> Main wallet receives CID notification via `AddListenTopic(main_address)` (Phase 2 D-17, `pubsub_broadcaster_ext.hpp:74`).

Per `03-CONTEXT.md`, D-17 is defined as:

> "main subscribes to child channels for state sync"

This is a different subscription (to the **child's** address topic) than the one used for discovery push (subscription to the **main's own** address topic). The `AddListenTopic` API is used in both cases, but D-17 specifically describes the state-sync subscription, not the discovery CID-notification subscription.

The document correctly describes the mechanism (subscribe to `main_address` topic) but anchors it to the wrong D-number. This could cause confusion when an implementer cross-references the Phase 2 design doc and finds D-17 describing a different subscription target.

**Fix:** In §2.1 step 4, replace the D-17 reference with a reference to D-15/D-16 (pubsub broadcast + CID notification) or simply cite the `AddListenTopic` API without a D-number:

> Main wallet receives CID notification via `AddListenTopic(main_address)` (Phase 2 D-15/D-16, `pubsub_broadcaster_ext.hpp:74`).

Also in §2.4 Traceability, change the D-17 bullet from "Main subscribes to child's address topic for state sync after discovery" to clarify that step 4 is the main's **own** topic subscription, not the child state-sync subscription (which is a separate step in §4 per D-17).

### WR-02: PayDev reading live CRDT state partially contradicts D-32 hold-time pinning claim

**File:** `docs/03-02-reward-policy-lifecycle.md:262-263`

**Issue:** Section 5.4 states:

> "For PayDev, the policy at payout time is the authoritative one — the developer wallet address is resolved fresh from the current registration state. This means a child updating its dev_wallet mid-flight (after escrow creation but before payout) would redirect the developer payout to the new address."

This is an intentional design choice (per D-33: child controls its own reward policy). However, it creates a tension with D-32 (from `03-CONTEXT.md`) which states:

> "The reward policy (dev_addr, peers_cut) is pinned at HoldEscrow time"

Read literally, D-32 claims both `dev_addr` and `peers_cut` are pinned. The 03-02 document correctly documents that only `peers_cut` is pinned for PayEscrow, while `dev_addr` is re-read from CRDT at PayDev time — but it never explicitly calls out this partial override of D-32.

An implementer who takes D-32 at face value and assumes dev_addr is always pinned could inadvertently build PayDev to read from the stored `EscrowTransaction.dev_addr_` instead of live CRDT, creating a subtle policy-resolution bug.

**Fix:** Add an explicit caveat in §5.4 stating that D-32's pinning applies to PayEscrow (peer payouts) but NOT to PayDev (developer payouts), and that this is intentional per D-33. For example:

> **Note on D-32:** The hold-time pinning guarantee (D-32) applies to `peers_cut` in the PayEscrow path and is enforced by `EscrowTransaction` immutability (§3). For `PayDev`, the developer wallet address is intentionally NOT pinned — it reads the current `RegistrationMetadata.dev_wallet` from CRDT at payout time. This means D-32's "dev_addr is pinned" claim applies only to the escrow release path (PayEscrow), not the developer payout path (PayDev). This is by design per D-33: the child controls its own reward policy.

---

## Info

### IN-01: "Registration date" data source references undefined DAGStruct timestamp

**File:** `docs/03-01-discovery-monitoring.md:308`

**Issue:** The "Registration date" row maps to `"CRDT element timestamp or dag_struct timestamp from DAGStruct header"`. The DAGStruct message structure is not defined in this document, and it's unclear which field within DAGStruct carries the timestamp (the `DAGStruct` proto is a Phase 1 artifact). An implementer would need to trace this to the Phase 1 registration protocol doc.

This is not a defect — the document correctly identifies that the date comes from CRDT metadata or the DAG header — but the anchor is under-specified for a standalone implementer.

**Fix:** Add a cross-reference to the Phase 1 doc where DAGStruct timestamp fields are defined, or note the specific field name (e.g., `DAGStruct.timestamp`).

### IN-02: Broad line range `AccountMessenger.hpp:199-223` in requirement traceability table

**File:** `docs/03-01-discovery-monitoring.md:568`

**Issue:** The DISC-01 requirement traceability row (§7) references `AccountMessenger.hpp:199-223` for "topic constants." However, the detailed anchor points in §3.1 and §3.5 consistently reference `AccountMessenger.hpp:199-202` for the two topic constants (`ACCOUNT_COMM` and `REQUESTS_COMM`). The broader range 199-223 likely includes other AccountMessenger declarations that are not topic constants.

This appears to be a copy-paste error when the traceability table was consolidated from the detailed sections. It's unlikely to cause implementation errors since the detailed sections have the correct range, but the inconsistency is misleading.

**Fix:** Change `AccountMessenger.hpp:199-223` to `AccountMessenger.hpp:199-202` in the DISC-01 traceability row.

### IN-03: CRDT delta data freshness claimed as "Sub-second" for online children

**File:** `docs/03-01-discovery-monitoring.md:331-332`

**Issue:** The Data Freshness table (§4.3) claims "Sub-second for online children" as the latency for child CRDT deltas. However, per the Phase 2 design, CRDT deltas are DAG-synced via IPFS Graphsync — the pubsub notification carries only the topic/CID, not the delta payload itself. Actual CRDT sync latency depends on network conditions, DAG traversal depth, and Graphsync block-exchange time, which can be seconds to minutes in practice.

The "Sub-second" claim is overly optimistic for a design document and could set false expectations for implementers testing real-world sync latency.

**Fix:** Revise the freshness claim to reflect realistic CRDT sync behavior, e.g., "Eventual consistency (typically seconds; bounded by IPFS Graphsync)" instead of "Sub-second for online children."

---

## Cross-Document Consistency Verification

The following cross-document linkages were verified and found consistent:

| Topic | 03-01 Reference | 03-02 Reference | Status |
|-------|----------------|-----------------|--------|
| RevokeTx oneof arm | `revoke = 9` in `Consensus.proto:70-80` (§6.4) | `revoke = 9` (§8.2, §11.3) | ✓ Consistent |
| RegistrationTx field 8 in EmbeddedTransaction | "arms 1-7 consumed, 8 = RegistrationTx" (§6.4) | `registration = 8` in oneof table (§11.3) | ✓ Consistent |
| Detach flag as field 5 | `RegistrationTx.detach_flag = 5` (§6.5) | `detach_flag = 5` (§11.1) | ✓ Consistent |
| Supersedes sequence as field 6 | `RegistrationTx.supersedes_sequence = 6` (§6.5) | `supersedes_sequence = 6` (§11.1) | ✓ Consistent |
| CheckParentChildAuthority gate placement | "Gate 2.5" between gates 2 and 3 (§6.1, §6.2) | "Gate 2.5" between authorization and timestamp (§8.3) | ✓ Consistent |
| RevokeTx recommended as first-class tx | "recommends a first-class RevokeTx" (§6.4) | "Recommendation: First-class RevokeTx" (§8.1) | ✓ Consistent |
| D-26 certified-status check | Required in push (§2.1 step 6) and poll (§3.3.2) | Required before policy resolution (§2.4) | ✓ Consistent |
| D-35 detach is child-initiated | §6.5 | §7 (entire section) | ✓ Consistent |
| D-36 revoke is main-initiated | §6.4 | §8 (entire section) | ✓ Consistent |
| D-39 detach preserves UTXOs | §6.5 (child "retains all UTXOs") | §10.1 (UTXOs "Unchanged") | ✓ Consistent |

---

_Reviewed: 2026-07-13_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
