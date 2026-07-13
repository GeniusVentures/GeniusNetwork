# Architecture Research

**Domain:** Child-wallet integration into the GNUS SuperGenius C++ node
**Researched:** 2026-07-13
**Confidence:** HIGH (mapped to audited SuperGenius anchor points)

> Design-docs milestone. This describes how the child-wallet feature *integrates with* the existing SuperGenius components (audited this session), and the order in which the design documents should be produced.

## Standard Architecture

### System Overview

```
┌───────────────────────────────────────────────────────────────────────┐
│                          Wallet / Identity Layer                        │
│  ┌───────────────┐   ┌───────────────┐   ┌──────────────────────────┐   │
│  │ GeniusAccount │   │  Child Wallet  │   │ Registration Record       │   │
│  │ (main, secp)  │   │ (child, secp)  │   │ (child+main sigs, seq)    │   │
│  │ GeniusAccount │   │  own nonce      │   │ NEW proto message         │   │
│  │  .hpp:207,216 │   │  own UTXO owner │   │ in SGTransaction.proto    │   │
│  └───────┬───────┘   └───────┬────────┘   └────────────┬─────────────┘   │
├──────────┼───────────────────┼─────────────────────────┼─────────────────┤
│                     Consensus / Validation Layer (EXTENDED)             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ CheckTransactionAuthorization (TxMgr.cpp:4361)  ← + AUTHORITY     │   │
│  │ ValidateTransactionForConsensus (TxMgr.hpp:689) ← + parent-child  │   │
│  │ GeniusInputValidator (ownership + sig)          ← + delegated-spend│  │
│  │ FilterTransaction (TxMgr.cpp:2984)              ← + registration  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────────┤
│                       CRDT State Layer (globaldb)                       │
│  ┌───────────────────────┐  ┌──────────────────────────────────────┐    │
│  │ tx/  proof/ (existing) │  │ registry/<child>/  (NEW namespace)   │    │
│  │ element filters        │  │ element filter + regex               │    │
│  └───────────────────────┘  └──────────────────────────────────────┘    │
│              RocksDB  +  IPLD Merkle DAG deltas  (crdt_datastore)        │
├─────────────────────────────────────────────────────────────────────────┤
│                        PubSub Layer (GossipSub)                         │
│  PubSubBroadcasterExt: AddListenTopic / AddBroadcastTopic               │
│  main channel topic  ◄── child broadcasts registration                  │
│  child channel topic ◄── main subscribes for balance/registry sync      │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Integration Point |
|-----------|----------------|-------------------|
| Child wallet identity | Own keypair, own nonce sequence, own UTXO ownership | Extends/parallels `GeniusAccount` (`GeniusAccount.hpp`), created via `GeniusNode::New` `AccountSource` |
| Registration record | Encodes child↔main binding, dual sigs, seq, metadata | NEW message + oneof arm in `account/proto/SGTransaction.proto` |
| Registration transaction | Carries the record into consensus/CRDT | New `GeniusTransaction` subtype, signed by child; main sig embedded |
| Authority validator | Enforces the six consensus rules | Extend `CheckTransactionAuthorization` / `ValidateTransactionForConsensus` (TxMgr) + `GeniusInputValidator` |
| Registration CRDT filter | Validates + persists registration deltas | New element filter alongside `tx/`, `proof/` (TxMgr.cpp:190-213) |
| Registration CRDT namespace | Consensus-visible authority store | New `HierarchicalKey` prefix in `globaldb` |
| PubSub topics | Broadcast registration; sync child state | `PubSubBroadcasterExt` (pubsub_broadcaster_ext.hpp) |
| Reward-policy resolver | Route processing split per child | Extend escrow `HoldEscrow`/`PayEscrow` (TxMgr.cpp:778,812) with per-child `dev_addr`/`peers_cut` |

## Recommended Design-Document Structure

```
.planning/  (design outputs land in phase docs; conceptual module layout below)
SuperGenius/src/account/
├── ChildWallet(.hpp/.cpp)          # NEW: child identity, keypair, nonce
├── RegistrationTransaction(.hpp)   # NEW: dual-sig registration tx type
├── proto/SGTransaction.proto       # EXTEND: RegistrationTx, RegistrationRecord
├── proto/SGAccountComm.proto       # EXTEND (opt): registry query/response msgs
├── TransactionManager.(hpp/cpp)    # EXTEND: authority rules, registration filter
└── GeniusInputValidator.cpp        # EXTEND: delegated-spend (fund/recover) checks
SuperGenius/src/crdt/globaldb/      # registry namespace + topic wiring (design-only)
```

### Structure Rationale

- **New types under `account/`:** child wallets are an account-layer concept; keep them next to `GeniusAccount`/transactions.
- **Extend, don't fork, TransactionManager:** authority is a validation concern that belongs on the existing consensus path; a parallel path would risk divergent rules.
- **Additive proto changes:** preserve wire compatibility (see STACK "What NOT to Use").

## Architectural Patterns

### Pattern 1: Consensus-Recorded Capability Record

**What:** Store a dual-signed registration record as consensus-visible CRDT state; consensus consults it to authorize main↔child actions.
**When to use:** Whenever authority must outlive local metadata and be independently verifiable by all nodes.
**Trade-offs:** Strong, tamper-evident authority; cost is new consensus rules + CRDT filter complexity and the eventual-consistency ordering problem (PITFALLS).

### Pattern 2: Dual-Signature Attestation

**What:** Registration valid only if it carries a child signature AND a main signature over the same canonical record (incl. seq).
**When to use:** Establishing/mutating a bilateral relationship where both parties must consent.
**Trade-offs:** Prevents unilateral hijack; requires an out-of-process main-signing flow (Connect-GNUS-Wallet), adding UX steps.

### Pattern 3: Monotonic-Sequence Latest-Wins (consensus-ordered)

**What:** Each child's registration carries a strictly increasing seq; consensus deterministically resolves the winning record.
**When to use:** Mutable relationships (replace/detach) under eventual consistency.
**Trade-offs:** Deterministic conflict resolution; requires consensus to define the total order that CRDT alone does not provide.

### Pattern 4: Destination-Restricted Delegated Spend

**What:** Main-recover-from-child produces a transfer whose destination is constrained to the registered main address.
**When to use:** Recovery flows where the delegate should move funds but not redirect them.
**Trade-offs:** Limits abuse of a compromised main key; slightly less flexible than open parent transfers.

## Data Flow

### Registration Flow

```
Child wallet exists (standalone)
    ↓ user selects main wallet
Child signs RegistrationRecord{child_pk, main_pk, seq, meta}
    ↓ broadcast on MAIN's pubsub channel  (PubSubBroadcasterExt.Broadcast)
Main reviews + signs acceptance (out-of-process; main key never leaves)
    ↓ RegistrationTx (child sig + main sig) submitted
Consensus validates dual sig + seq  → FilterTransaction accepts
    ↓ written to CRDT registry/<child>/  (globaldb.Put + topic publish)
Relationship now consensus-visible; state = registered
```

### Discovery + Balance Sync

```
Main subscribes to child channel topic  (AddListenTopic)
    ↓ CRDT deltas for child UTXO/registry replicate to main
Main reads registry set → lists children (balance, assets, game, dev, cut, status)
    (no child private key required)
```

### Funding / Recovery

```
Main → child:   main-signed transfer; consensus checks child registered this main
Main-recover:   main-signed; consensus checks (a) source is child of this main,
                (b) destination == registered main; produces delegated-spend witness
                validated by GeniusInputValidator
Child→arbitrary/dev: child-signed; normal UTXO ownership + signature checks
Child-spends-main:   REJECTED (no valid main signature)
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Few children per main | Single child channel subscription; registry read is trivial |
| Many children per main (publisher-wide) | Consider a shared/aggregated registry topic; paginate registry reads; bound CRDT subscription fan-out |
| Many mains network-wide | Registry namespace keyed by child ensures per-child locality; element filter regex must stay O(1)-ish per delta |

### Scaling Priorities

1. **First bottleneck:** pubsub subscription fan-out when a main has many children → design an aggregation topic or lazy subscription.
2. **Second bottleneck:** CRDT DAG growth from registration churn (replace/detach) → tombstone old records; keep only latest seq materialized.

## Anti-Patterns

### Anti-Pattern 1: Authority via local wallet metadata

**What people do:** Track parent-child links only in the wallet app DB.
**Why it's wrong:** Not enforceable by consensus; any node/UI can lie; recovery unverifiable.
**Do this instead:** Consensus-recorded registration in CRDT with element-filter validation.

### Anti-Pattern 2: Bolting authority onto UTXO ownership only

**What people do:** Treat "main can spend child" as just another owner match.
**Why it's wrong:** Existing ownership check requires `payload_owner == src_address` (GeniusInputValidator.cpp:421); conflating breaks the invariant and could enable child-spends-main.
**Do this instead:** Add an explicit delegated-spend authorization branch gated by the registration record, distinct from normal ownership.

### Anti-Pattern 3: Trusting pubsub sender identity

**What people do:** Accept a registration because it arrived on the main's topic.
**Why it's wrong:** Any peer can publish to a gossip topic; topic membership is not authorization.
**Do this instead:** Authority derives solely from the dual signatures + consensus validation, never from which topic delivered it.

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| ChildWallet ↔ TransactionManager | Signed transactions (DAGStruct) | Reuse signing/verify; add registration tx type |
| TransactionManager ↔ globaldb | CRDT Put + element filters | New registry namespace + filter regex |
| globaldb ↔ PubSubBroadcasterExt | Topic publish/subscribe | New child/main channel topics |
| Reward path ↔ EscrowTransaction | HoldEscrow/PayEscrow | Per-child dev_addr/peers_cut policy |

## Suggested Design-Document Order (dependencies)

1. **Child identity & keypair model** — nothing else can be specified without it.
2. **Registration protocol + record schema + proto changes** — defines the artifact consensus/CRDT operate on.
3. **CRDT persistence + pubsub broadcast/subscription** — makes the record consensus-visible and discoverable.
4. **Consensus authority rules** (the six cases) — depends on record + CRDT being defined.
5. **Discovery + balance sync** — depends on registration record + child channel subscription.
6. **Reward policy** — mostly independent; can be designed alongside 4–5.
7. **Lifecycle + change/replace/detach + replay protection** — depends on all of the above (mutation of an established record).

## Sources

- SuperGenius audit: `GeniusAccount.hpp`, `TransactionManager.cpp` (4361/2984/190-213/778/812), `GeniusInputValidator.cpp` (421), `crdt/globaldb`, `pubsub_broadcaster_ext.hpp`, `SGTransaction.proto` — HIGH
- `.planning/codebase/ARCHITECTURE.md` — existing architecture map — HIGH
- `GNUS_Subwallet_Architecture_Proposal.md` — data-flow & rules — HIGH

---
*Architecture research for: child-wallet design on SuperGenius*
*Researched: 2026-07-13*
