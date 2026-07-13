# Phase 1: Child Identity & Registration Protocol - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-13
**Phase:** 1-Child Identity & Registration Protocol
**Areas discussed:** Child identity marker, Registration carrier, Sequence & replay, Dual-sig + signing flow

---

## Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Child identity marker | Explicit account type vs emergent from registration | ✓ |
| Registration carrier | First-class tx vs CRDT-only record vs both | ✓ |
| Sequence & replay | Dedicated reg seq vs reuse DAGStruct.nonce | ✓ |
| Dual-sig + signing flow | How signatures compose + out-of-process boundary | ✓ |

**User's choice:** All four areas selected.

---

## Child Identity Marker

| Option | Description | Selected |
|--------|-------------|----------|
| Emergent from registration record | No new field; child-ness = a registration record naming a main exists | ✓ |
| Explicit account-type flag | Add is_child/account_role marker at creation | |
| Hybrid — local hint + consensus truth | Local UX hint, consensus authoritative | |

**User's choice:** Emergent (via free-text elaboration).
**Notes:** User: "A child wallet will initially be created like any other wallet as a GeniusNode with a private key. We will have a mechanism to connect wallet to our GeniusWallet app, which will give the app with the intended child wallet the main GeniusWallet's public key, the child wallet will add an entry to CRDT signed by itself, this is a new type of CRDT entry, it will contain data as to the main wallet public key. Consensus passes because it is signed by the child wallet account." → confirms emergent identity + surfaced the child-signed-only model.

## Registration Signing (follow-up — surfaced by identity answer)

| Option | Description | Selected |
|--------|-------------|----------|
| Child-signed only | Only child signs; main pubkey via connect flow | ✓ |
| Dual-signature (keep REG-02) | Child + main counter-signature | |
| Two-step: child claims, main confirms | Child pending, main upgrades to registered | |

**User's choice:** Child-signed only.
**Notes:** Reverses locked REG-02 and PROJECT.md "dual-signature" decision. Impact documented in CONTEXT.md D-05: bounded to discovery-view spam because registration grants zero authority over the main (funding/recovery require main signature in Phase 2). Flagged for transition.

## Registration Carrier

| Option | Description | Selected |
|--------|-------------|----------|
| First-class RegistrationTx | New GeniusTransaction subclass through TransactionManager path | ✓ |
| CRDT-only record + element filter | Standalone record, no tx | |
| Both — tx authenticates, CRDT holds state | Tx = event, CRDT = current state | |

**User's choice:** First-class RegistrationTx.
**Notes:** Record still materializes into a CRDT namespace as committed state (namespace/filter = Phase 2 hand-off). Reuses DAGStruct signing/nonce/hashing and consensus ordering.

## Registration Schema (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Single RegistrationTx w/ optional metadata | DAGStruct + main_address + sequence + optional RegistrationMetadata | ✓ |
| Split RegistrationTx + RegistrationRecord | Separate wire event vs stored form | |
| Minimal link + separate metadata message | Core link only; metadata via its own tx | |

**User's choice:** Single RegistrationTx with optional embedded metadata.
**Notes:** Additive-only, new field numbers, compat matrix required (Pitfall 7).

## Sequence & Replay

| Option | Description | Selected |
|--------|-------------|----------|
| Both: DAGStruct.nonce + dedicated reg sequence | Account ordering + registration lineage ordering | ✓ |
| Reuse DAGStruct.nonce only | No new field; conflates all tx with lineage | |
| Dedicated reg sequence, nonce incidental | Lineage via sequence + tie-break only | |

**User's choice:** Both.
**Notes:** Consensus selects highest valid registration sequence; replace/detach reference prior sequence ("supersedes seq N"). Tie-break + consensus-ordering mechanism = Phase 2 hand-off.

## Dual-sig + Signing Flow (Connect boundary)

| Option | Description | Selected |
|--------|-------------|----------|
| Connect delivers main pubkey only | Main performs no signing; REG-04 satisfied trivially | ✓ |
| Optional out-of-process main acceptance | Main later counter-signs to upgrade pending→confirmed | |
| Abstract authorization-provider seam | Interface hides pubkey-only vs counter-sign | |

**User's choice:** Connect delivers main pubkey only.
**Notes:** Handshake specified transport-agnostic; platform UI out of scope (v2/PLAT-*).

---

## Agent's Discretion

- Exact proto field numbers and mechanical shape of the new tx arm/dispatch (additive-only).
- Naming and C++ file placement of the new tx subclass + metadata message under `SuperGenius/src/account/`, following existing `GeniusTransaction` subclass conventions.

## Deferred Ideas

- CRDT registration namespace + element filter — Phase 2 (SYNC-01/02).
- Registration sequence tie-break + consensus ordering — Phase 2.
- Pubsub broadcast/subscription — Phase 2 (SYNC-03/04/05).
- Consensus authority rules — Phase 2 (CONS-01..06).
- Optional out-of-process main acceptance signature — rejected for Phase 1; possible v2 hardening.
- Metadata/reward-policy update rules — Phase 3 (RWD-03).
- Lifecycle state machine + change-flows — Phase 3 (LIFE-01..04).
- Platform "Connect GNUS Wallet" UI — v2 (PLAT-01/02).
