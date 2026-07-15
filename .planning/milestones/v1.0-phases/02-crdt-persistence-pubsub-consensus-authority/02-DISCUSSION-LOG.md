# Phase 2: CRDT Persistence, PubSub & Consensus Authority - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-13
**Phase:** 02-crdt-persistence-pubsub-consensus-authority
**Areas discussed:** CRDT namespace & key layout, PubSub channel design, Consensus authority integration, CRDT vs consensus ordering

---

## CRDT Namespace & Key Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Both tx/ and reg/ | RegistrationTx gets tx/ entry AND materializes into reg/ record | |
| reg/ only | RegistrationTx lives only in new reg/ namespace | ✓ |

**User's choice:** reg/ only — a new FilterRegistration method parallel to FilterTransaction, new regex pattern `^/?/bc-{net}/reg/`.

| Option | Description | Selected |
|--------|-------------|----------|
| reg/{child_addr} — single record | One CRDT element per child, updated in-place | ✓ |
| reg/{child_addr}/{seq} — event log | Each registration event gets own element, full history by prefix | |

**User's choice:** Single record per child, updated in-place on each valid registration event.

| Option | Description | Selected |
|--------|-------------|----------|
| Sig + seq + well-formed | Filter rejects on deserialization, bad sig, seq not higher, malformed | ✓ |
| Sig only (defer seq to consensus) | Filter only rejects on deserialization/sig; consensus decides seq | |

**User's choice:** Filter enforces seq strictly higher at the CRDT gate level.

| Option | Description | Selected |
|--------|-------------|----------|
| Full RegistrationTx | Store complete protobuf including DAGStruct, sig, metadata | ✓ |
| Derived RegistrationRecord | Store only state fields (main_address, seq, metadata, timestamp) | |

**User's choice:** Full RegistrationTx — self-contained, independently verifiable.

---

## PubSub Channel Design

| Option | Description | Selected |
|--------|-------------|----------|
| CRDT gossip (no direct broadcast) | Registration propagates via CRDT DAG sync only | |
| Main's address topic + CRDT | Child publishes on main's topic AND writes to CRDT | ✓ |

**User's choice:** Both — pubsub notification for low-latency discovery, CRDT for authoritative storage.

| Option | Description | Selected |
|--------|-------------|----------|
| Main subscribes to child's address topic | AddListenTopic(child_address) for CRDT delta sync | ✓ |
| Main queries reg/ namespace only | Read reg/ entries + tx/ entries, no pubsub subscription | |
| Both: subscribe + query | Subscribe for live updates, query for bootstrap | |

**User's choice:** Direct subscription to child's address topic.

| Option | Description | Selected |
|--------|-------------|----------|
| Query reg/ by main address | CRDT query to discover registered children | |
| Pubsub notification triggers subscription | Notification carries child_addr, main subscribes directly | ✓ |

**User's choice:** Pubsub notification IS the discovery mechanism — no CRDT query needed.

| Option | Description | Selected |
|--------|-------------|----------|
| Child address only | Minimal notification payload | |
| Child address + RegistrationTx | Full protobuf in notification | |
| Registration CID/hash | Content-addressed reference to DAG entry | ✓ |

**User's choice:** CID/hash reference — avoids duplication, forces CRDT validation before main acts.

---

## Consensus Authority Integration

| Option | Description | Selected |
|--------|-------------|----------|
| New CheckParentChildAuthority step | New gate between signature and replay in pipeline | ✓ |
| Extend CheckTransactionAuthorization | Expand signature-only check to include authority | |
| Extend GeniusInputValidator | Add authority as exception branch in ValidateWitness | |

**User's choice:** New dedicated gate — clean separation from signature and UTXO ownership.

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse transfer type + reg/ lookup | No new tx types; gate checks sig + reg/ record | ✓ |
| New tx type per authority action | parent-fund, parent-recover as new proto types | |

**User's choice:** Reuse "transfer" type — direction determined by src/dst addresses.

| Option | Description | Selected |
|--------|-------------|----------|
| Hard destination == main | Recovery dst MUST be the registered main address | ✓ |
| Allow registered sibling destinations | Recovery to any child registered to same main | |

**User's choice:** Hard restriction — recovery destination locked to registered main.

**User's clarifications on CONS-04:** Child→developer is a normal transfer — the existing GeniusNode::PayDev pattern handles it. No special consensus rule needed. The developer wallet comes from DevConfig_st (existing), not from the reg/ record.

---

## CRDT vs Consensus Ordering

| Option | Description | Selected |
|--------|-------------|----------|
| Full consensus (like txs) | RegistrationTx goes through SubmitProposal → quorum → certificate | ✓ |
| CRDT-only with seq resolution | Local seq resolution without consensus rounds | |
| Hybrid: CRDT gate + nonce chain | CRDT filters, nonce provides ordering | |

**User's choice:** Full consensus path — RegistrationTx participates in the same sgns.nonce.v1 subject.

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse sgns.nonce.v1 | RegistrationTx on existing nonce-chain subject | ✓ |
| New sgns.registration.v1 | Dedicated registration consensus subject | |

**User's choice:** Reuse existing subject — no new SubjectHandler needed.

| Option | Description | Selected |
|--------|-------------|----------|
| First-to-consensus wins | First certified registration at given seq is authoritative | ✓ |
| Seq + tx hash deterministic | Lexicographic tie-break on tx hash | |

**User's choice:** First-to-consensus — nonce chain already prevents same-nonce conflicts.

| Option | Description | Selected |
|--------|-------------|----------|
| Filter accepts pre-cert (like tx/) | Registration enters CRDT before certificate | ✓ |
| Filter requires certificate | Only certified registrations enter CRDT | |

**User's choice:** Accept pre-cert (matches tx/ pattern). Certified flag marks authority.

---

## the agent's Discretion

- Proto field numbers and mechanical reg/ filter registration shape
- Naming of FilterRegistration, CheckParentChildAuthority methods
- Certified status flag implementation approach (separate key, in-band field, or in-memory map)

## Deferred Ideas

- Main-replacement policy fork (Phase 3)
- Lifecycle state machine + change flows (Phase 3)
- Main-wallet discovery/monitoring display (Phase 3)
- Per-child processing-reward policy (Phase 3)
- Platform "Connect GNUS Wallet" UI flows (v2)
- Aggregated registry topic (v2)
