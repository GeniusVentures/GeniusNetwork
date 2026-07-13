# Stack Research

**Domain:** Child/subwallet + consensus-enforced delegated authority for a C++ UTXO blockchain node (GNUS SuperGenius)
**Researched:** 2026-07-13
**Confidence:** HIGH (grounded in existing SuperGenius code + established wallet-security standards)

> This is a **design-documentation** milestone. Recommendations are framed as "the design should specify X because Y", not "install library Z". SuperGenius already has its stack (C++17/20, secp256k1 via TrustWalletCore, Protocol Buffers, libp2p GossipSub, CRDT over RocksDB/IPLD). The task is to choose the right *schemes and patterns* for child wallets on top of that stack.

## Recommended Stack

### Core Technologies (concepts the design must adopt)

| Technology / Scheme | Version / Std | Purpose | Why Recommended |
|---------------------|---------------|---------|-----------------|
| Independent secp256k1 keypair per child | existing `EthereumKeyGenerator` | Child identity | Matches proposal's "cryptographically independent wallet"; bounds compromise to the child; reuses `GeniusAccount` signing/verify (`GeniusAccount.hpp:207,216`). |
| Dual-signature registration attestation | new record in `SGTransaction.proto` | Bind child↔main | Both parties must consent → prevents unsolicited/fraudulent association (proposal §Registration Flow). Mirrors EIP-712/EIP-1271 "signed attestation" concept. |
| Monotonic sequence number per child registration | uint64 field | Replay/reorder protection | CRDT is eventually consistent with **no total order**; a per-child monotonically-increasing seq lets consensus deterministically pick the latest valid registration. |
| Consensus-visible authority record in CRDT | new key namespace in `globaldb` | Parent-child authority | Proposal requires authority "enforced by consensus rather than only wallet UI". Store registration under a well-known `HierarchicalKey` prefix filtered by `TransactionManager` element filter. |
| Capability/authority-scoped validation | extension to `ValidateTransactionForConsensus` | Enforce spend rules | The design must add a hierarchical-authority check; today authorization is signature-only (`CheckTransactionAuthorization`, TxMgr.cpp:4361). |
| Protobuf field-additive versioning | proto3 | Schema evolution | Add new message types / optional fields only; never renumber → keeps SuperGenius/GeniusSDK/GeniusWallet builds compatible. |

### Supporting Concepts

| Concept | Purpose | When to Use |
|---------|---------|-------------|
| Destination-restricted recovery | Main-recover-from-child limited to registered main address | Recovery path; prevents a compromised-main-key from redirecting funds arbitrarily (proposal §Recovers Funds). |
| Per-child processing-policy record (`dev_addr`, `peers_cut`) | Reward routing | Reuse escrow `HoldEscrow`/`PayEscrow` (TxMgr.cpp:778,812); child needs its own policy, inheritable or explicit. |
| Lifecycle state enum (standalone/pending/registered/detached/revoked/closed) | Registration state machine | Registration + change flows; encodes valid transitions in consensus rules. |
| Topic-namespaced pubsub channels | Discovery + balance sync | `PubSubBroadcasterExt.AddListenTopic` — main subscribes to child channel(s); child broadcasts registration to main's channel. |

### Standards Whose *Concepts* Inform the Design

| Standard | Relevance | How to Apply |
|----------|-----------|--------------|
| EIP-1271 (contract signature validation) | Delegated authority verification | Model the "is this signer authorized for this account?" check; here consensus plays the "contract" role. |
| ERC-4337 / session keys (account abstraction) | Scoped delegated keys | Conceptual analog for "child key acts for itself; main key has recovery authority". Do NOT import EVM AA machinery. |
| BIP-32/44 (HD derivation) | Alternative identity model | **Considered and rejected** for the parent↔child link (see below), but valid for a single user's own key management. |
| Multi-sig / threshold (2-of-2) | Registration consent + optional replacement guard | Dual-signature registration is effectively a 2-of-2 attestation; replacement may require existing-main co-sign. |

## Installation

Not applicable — design-docs milestone, no new dependencies. All schemes map onto SuperGenius's existing libraries (TrustWalletCore secp256k1, Protobuf, libp2p, RocksDB/IPLD CRDT).

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Independent child keypair | BIP-32 HD-derived child from main seed | If the *main* wallet must be able to re-derive/spend child keys offline. Rejected here: it would put derivation authority (hence spend authority) implicitly with the seed holder, violating "main key never in game process" and "compromise bounded to child". |
| Consensus authority record in CRDT | Local-only wallet metadata | Never for authority — proposal explicitly requires consensus enforcement. Local metadata is fine only for UI grouping. |
| Dual-signature registration | Child-only self-declared main | Rejected: allows a child (or attacker with child key) to name an arbitrary main and spam/grief; main consent is required. |
| Sequence-number + consensus-ordered latest | Timestamp-only ordering | Timestamps are spoofable and clocks skew; use monotonic seq as primary, timestamp as advisory. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Deriving child keys from the main seed for the parent-child link | Couples compromise; main-seed exposure compromises all children | Independent per-child keypairs + explicit registration record |
| Sharing one child key across multiple apps | Proposal §Sharing: compromise of any app compromises all shared assets | One child wallet per application; group by publisher in UI only |
| Relying on wall-clock timestamps for replay protection | CRDT nodes have no synchronized clock and no total order | Monotonic per-child sequence numbers, consensus-ordered |
| Renumbering / repurposing existing proto fields | Breaks wire compat with deployed SuperGenius/GeniusSDK/GeniusWallet | Additive new messages + optional fields only |
| Granting main wallet blanket transfer authority over child | Turns "recovery" into "seizure"; expands main-key blast radius | Destination-restricted recovery (to registered main only) unless protocol explicitly widens |

## Stack Patterns by Variant

**If the design prioritizes maximal child independence:**
- Registration is optional and removable; standalone children are first-class.
- Because the proposal states a child "remains independently usable" and standalone is a valid lifecycle state.

**If the design prioritizes anti-theft on reassignment:**
- Require existing-main co-signature to replace the registered main.
- Because it stops an attacker who only has the child key from hijacking the parent link — at the cost of harder legitimate recovery if the old main is lost.

**If the design prioritizes recoverability:**
- Allow child-signed main replacement without old-main consent, guarded by seq + new-main consent.
- Because it lets a legitimate owner recover from a lost main wallet.
- (This is an explicit policy fork the design must decide — see PITFALLS.)

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| New registration proto messages | existing `SGTransaction.proto` DAGStruct | Add as new top-level messages + a new oneof arm; existing readers ignore unknown fields. |
| New CRDT key prefix | existing `globaldb` element filters | Add a new regex filter alongside `tx/` and `proof/` (TxMgr.cpp:190-213); do not alter existing patterns. |
| New pubsub topics | `PubSubBroadcasterExt` | Plain-string topics like existing `SGNUS.*`; no protocol change. |

## Sources

- SuperGenius codebase audit (this session): `GeniusAccount.hpp`, `GeniusTransaction.hpp`, `TransactionManager.cpp`, `crdt/globaldb`, `EscrowTransaction.hpp`, `SGTransaction.proto` — HIGH
- `GNUS_Subwallet_Architecture_Proposal.md` — authoritative feature/security spec — HIGH
- Wallet-security standards (BIP-32/44, EIP-1271, ERC-4337 concepts) — established public standards — HIGH (conceptual application), MEDIUM (exact fit to UTXO+CRDT)

---
*Stack research for: child-wallet design on SuperGenius*
*Researched: 2026-07-13*
