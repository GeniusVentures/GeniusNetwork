# Phase 1: Subnet Addressing Scheme - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-24
**Phase:** 1-Subnet Addressing Scheme
**Areas discussed:** Address derivation scoping, Composite ID format & validation, Subnet Registry allocation mechanism, Replay-nonce keying corollary

---

## Address Derivation Scoping

| Option | Description | Selected |
|--------|-------------|----------|
| Fold into derivation | Address = domain-separated hash(pubkey, net_id, subnet_id); structurally unique but requires backward-compat carve-out for existing addresses | |
| Tuple-keying invariant | GetAddress() unchanged; every consumer must key by (net_id, subnet_id, address) instead | ✓ |
| You decide | Claude resolves during research/planning | |

**User's choice:** Tuple-keying invariant ("I don't think this needs to differ")
**Notes:** Follow-up question on domain-separation versioning was answered "N/A — going with tuple-keying" (derivation isn't changing, so versioning is moot).

| Option | Description | Selected |
|--------|-------------|----------|
| Mandatory shared helper | Every consumer must go through one shared key-building/lookup function; no bare-address keying anywhere | ✓ |
| Documented convention only | State the invariant as a rule, no mandated enforcement mechanism | |
| You decide | Claude picks based on relation to Phase 3's JOBC-01 requirement | |

**User's choice:** Mandatory shared helper (Recommended)
**Notes:** Ties directly into Phase 3's already-scoped JOBC-01 mandatory shared key-building function requirement.

---

## Composite ID Format & Validation

| Option | Description | Selected |
|--------|-------------|----------|
| Dotted-decimal + packed uint16 pair | "144.100" display form; net_id/subnet_id stay two separate uint16_t fields, no new serialization | ✓ |
| Single packed 32-bit integer | (net_id << 16 \| subnet_id) as canonical wire form | |
| You decide | Claude picks based on existing TransactionManager::New signature | |

**User's choice:** Dotted-decimal + packed uint16 pair (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| 0 always reserved | subnet_id=0 permanently means "no subnet / main net only"; byte-identical to today | ✓ |
| 0 is allocatable | 0 is just the first subnet ID, issuable like any other | |

**User's choice:** 0 always reserved (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Full uint16 range, no sub-structure | Any value 1-65535 allocatable, no reserved sub-ranges | ✓ |
| Reserve a sub-range | Carve out e.g. 1-999 for "official" subnets | |
| You decide | Claude picks the simplest option | |

**User's choice:** Full uint16 range, no sub-structure (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Keep flat | net_id/subnet_id stay top-level sibling fields in sgns_config.json | ✓ |
| Nest under a "subnet" object | Group subnet_id under a nested object, requires config-schema migration | |

**User's choice:** Keep flat (Recommended)

---

## Subnet Registry Allocation Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Main-net-operator-issued | Only a certified main-net authority can write a valid registry entry (CheckCertifiedParent-style pattern) | ✓ |
| Open self-registration, first-claim-wins | Any node can broadcast a claim; CRDT conflict resolution settles collisions | |
| You decide | Claude resolves during planning | |

**User's choice:** Main-net-operator-issued (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| New top-level namespace (/bc-{net_id}/subnets/{subnet_id}) | Mirrors reg/{child_addr} pattern but as its own distinct namespace | ✓ |
| Reuse reg/ namespace with a type discriminator | Subnet registrations share reg/ path, distinguished by record-type field | |

**User's choice:** New top-level namespace, e.g. /bc-{net_id}/subnets/{subnet_id} (Recommended)

---

## Replay-Nonce Keying Corollary

| Option | Description | Selected |
|--------|-------------|----------|
| State it explicitly here | This design doc names GetPeerNonce/GetOutgoingPreviousHash/GetTrackedTxByNonceAndAddress as needing (net_id, subnet_id, address) keying | |
| Defer detail to Phase 3 (Job Isolation) | This phase states nonce tracking falls under the tuple-keying invariant in general terms only; Phase 3 names the specifics during its consensus-gate re-audit | ✓ |

**User's choice:** Defer detail to Phase 3 (Job Isolation)
**Notes:** Deliberate scoping choice to keep this design doc focused on identity/format/allocation rather than re-litigating consensus-gate details Phase 3 already owns.

---

## Claude's Discretion

- Exact naming of the shared tuple-keying helper function/type — to be finalized during planning/Phase 3.

## Deferred Ideas

- Replay-nonce/previous-hash keying specifics — deferred to Phase 3 (Job Isolation & Consensus Impact).
- Subnet ID range sub-structuring (reserved "official" vs. "open" ranges) — declined for this milestone, revisit only if a real need emerges post-v1.0.
- Address-derivation domain-separation versioning — moot given derivation isn't changing this milestone; noted in case a future milestone revisits address derivation.
