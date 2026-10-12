# Project Research Summary

**Project:** GNUS Child Wallet Design
**Domain:** Child/subwallet + consensus-enforced delegated authority for a C++ UTXO blockchain node (SuperGenius)
**Researched:** 2026-07-13
**Confidence:** HIGH

## Executive Summary

This milestone produces **design documents** (not code) for adding child wallets to the GNUS SuperGenius node, grounded in a fresh audit of the existing codebase. A child wallet is a cryptographically independent secp256k1 wallet a game controls; it can operate standalone, earn GNUS via background inference, transfer its own assets, and optionally register a main wallet through a dual-signed record recorded in consensus-visible CRDT state and broadcast over pubsub. Once registered, the main wallet subscribes to the child's pubsub channel, syncs CRDT to read balances, and can fund or recover from the child — all without the main private key ever entering the game process.

The research confirms the design maps cleanly onto SuperGenius's existing primitives (`GeniusAccount` signing, UTXO ownership, `TransactionManager` validation, `globaldb` CRDT, `PubSubBroadcasterExt` topics, escrow reward splits) with one critical gap: **there is no hierarchical/role-based account authority today — authorization is purely cryptographic signature verification.** The core design work is adding a consensus-enforced parent-child authority layer plus a replay-safe registration record.

The dominant risk is that **CRDT is eventually consistent with no total order, while replay protection and authority resolution assume an order.** Every hard pitfall (replay, reassignment split-brain, recovery-as-seizure, child-spends-main, pubsub spoofing) traces back to this tension, and the design must state explicitly how consensus imposes the ordering plain CRDT deltas lack.

## Key Findings

### Recommended Stack

Reuse SuperGenius's existing stack; the design chooses *schemes*, not new dependencies. Independent per-child secp256k1 keypairs (not HD-derived from the main seed) preserve bounded compromise. Registration is a dual-signature attestation with a monotonic per-child sequence number for replay/reorder resistance. Authority lives in a consensus-visible CRDT namespace and is enforced by extending the existing validation path. Proto changes are additive-only to preserve build compatibility.

**Core technologies:**
- Independent secp256k1 child keypair (`EthereumKeyGenerator`/`GeniusAccount`) — bounds compromise; reuses existing signing/verify.
- Dual-signature registration + monotonic seq (new `SGTransaction.proto` message) — prevents fraudulent links and replay.
- Consensus-recorded CRDT authority record (`globaldb` new namespace + element filter) — makes authority enforceable, not UI-only.

### Expected Features

**Must have (table stakes):**
- Independent child keypair, standalone operation, child-signed arbitrary transfers, child→developer payments.
- Dual-signature registration + record schema, consensus-recorded relationship, replay/reorder protection.
- Main-wallet discovery, balance/asset monitoring, main→child funding, destination-restricted recovery, reject child-spends-main.
- Lifecycle states and processing-reward split policy.

**Should have (differentiators):**
- Change/replace/detach registered main (seq-guarded), per-child configurable reward split, authenticated dev-wallet/split updates, rich child metadata.

**Defer / exclude:**
- Cross-application shared child keys — explicitly an anti-feature (compromise of any app compromises all shared assets).
- Threshold/social recovery for the main wallet — separate concern, v2+.

### Architecture Approach

Child wallets are an account-layer concept: new `ChildWallet`/`RegistrationTransaction` types under `account/`, additive proto changes, and *extensions* (not forks) to `TransactionManager` authority checks and `GeniusInputValidator`. A new CRDT registry namespace holds the consensus-visible record; new pubsub topics carry registration broadcast and child-state sync.

**Major components:**
1. Child identity/keypair model — extends `GeniusAccount` patterns.
2. Registration record + transaction — new proto messages + dual-sig validation.
3. CRDT registry namespace + pubsub topics — persistence, broadcast, discovery.
4. Consensus authority layer — the six spend rules + explicit rejection rule.
5. Reward-policy resolver — per-child split via existing escrow mechanics.

### Critical Pitfalls

1. **Replay/reorder under eventual consistency** — use monotonic per-child seq + consensus ordering; authority only after consensus validation.
2. **Reassignment split-brain** — deterministic (seq, tie-break) resolution + "supersedes seq N" linkage.
3. **Recovery becomes seizure** — restrict recovery destination to the registered main by consensus rule.
4. **Child-spends-main leakage** — keep a separate authorization branch; add explicit negative rule + test.
5. **Pubsub topic trust** — authority derives from signatures + consensus only, never from topic membership.

## Implications for Roadmap

Suggested phase structure (design-docs milestone; ~coarse granularity → 3–4 phases). Design-document order follows dependencies: identity → registration/CRDT/pubsub → consensus authority + discovery + rewards → lifecycle/changes.

### Phase 1: Child Identity & Registration Protocol
**Rationale:** Nothing else can be specified without the child identity model and the registration record it produces.
**Delivers:** Design docs for child keypair/identity model and the dual-signature registration protocol + additive proto schema (RegistrationTx/RegistrationRecord) with a compatibility matrix.
**Addresses:** Independent keypair, standalone operation, registration schema.
**Avoids:** Proto-compat breakage (Pitfall 7).

### Phase 2: CRDT Persistence, PubSub Flow & Consensus Authority
**Rationale:** Once the record exists, it must be persisted consensus-visibly, broadcast/subscribed, and enforced. This is the security core.
**Delivers:** Design docs for the CRDT registry namespace + element filter, pubsub broadcast/subscription (registration + child-state sync), and the six consensus authority rules incl. destination-restricted recovery and the explicit child-cannot-spend-main rejection.
**Uses:** `globaldb`, `PubSubBroadcasterExt`, `TransactionManager` validation extensions, `GeniusInputValidator`.
**Avoids:** Replay/reorder, recovery-seizure, child-spends-main, pubsub-trust (Pitfalls 1,3,4,5).

### Phase 3: Discovery, Rewards & Lifecycle
**Rationale:** Delivers the main-wallet value (discovery/monitoring/funding) plus monetization and safe mutation of established relationships.
**Delivers:** Design docs for main-wallet discovery + balance sync, per-child processing-reward policy, and lifecycle/change flows (replace/detach/revoke/close) with seq-based replay safety.
**Addresses:** Discovery, monitoring, funding, reward split, lifecycle.
**Avoids:** Reassignment split-brain, reward edge cases, child blast-radius (Pitfalls 2,6,8).

### Phase Ordering Rationale
- Registration record must be defined before anything can persist or validate it.
- Consensus authority depends on both the record and its CRDT representation.
- Lifecycle mutation is riskiest and depends on all prior guarantees, so it comes last.

### Research Flags
- **Phase 2:** Deep — CRDT eventual-consistency vs consensus ordering is the central hard problem; may need focused research during planning.
- **Phase 1 & 3:** Standard — grounded in audited SuperGenius patterns; lighter research.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Reuses audited existing stack; scheme choices well-established |
| Features | HIGH | Extracted directly from authoritative proposal |
| Architecture | HIGH | Mapped to real SuperGenius anchor points |
| Pitfalls | HIGH | Domain-specific, grounded in CRDT/consensus tension + code |

**Overall confidence:** HIGH

### Gaps to Address
- **Consensus ordering mechanism specifics:** how SuperGenius consensus currently establishes ordering for tx must be confirmed during Phase 2 planning to anchor the seq-resolution design.
- **Main-replacement policy fork:** require existing-main consent (anti-theft) vs not (recoverability) — a decision the design must make explicitly, ideally with stakeholder input during Phase 3.

## Sources

### Primary (HIGH confidence)
- SuperGenius codebase audit (this session): `GeniusAccount.hpp`, `GeniusTransaction.hpp`, `TransactionManager.cpp`, `GeniusInputValidator.cpp`, `crdt/globaldb`, `EscrowTransaction.hpp`, `SGTransaction.proto`
- `GNUS_Subwallet_Architecture_Proposal.md` — authoritative spec
- `.planning/codebase/ARCHITECTURE.md`, `CONCERNS.md`

### Secondary (MEDIUM confidence)
- Public wallet-delegation patterns (session keys/ERC-4337 concepts, custodial subaccounts) for comparison

---
*Research completed: 2026-07-13*
*Ready for roadmap: yes*
