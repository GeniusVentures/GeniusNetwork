# Feature Research

**Domain:** Child/subwallet system for GNUS SuperGenius (game-integrated delegated wallets)
**Researched:** 2026-07-13
**Confidence:** HIGH (features extracted directly from the authoritative proposal)

> This is a **design-docs** milestone. "Table stakes / differentiator / anti-feature" here means: what the *design documents* must cover to be complete, what adds design value, and what the design must explicitly exclude.

## Feature Landscape

### Table Stakes (The Design MUST Cover These)

Missing any of these leaves the design incomplete relative to the proposal.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Independent child keypair + identity | Core of the whole model ("cryptographically independent wallet") | MEDIUM | Reuse `GeniusAccount`/`EthereumKeyGenerator`; child needs own nonce sequence. |
| Standalone operation (no main required) | Proposal: child valid without a main wallet | LOW | Lifecycle "standalone"; child can hold/receive/transfer + earn rewards unregistered. |
| Child-signed transfer to arbitrary address | Child is an independent wallet | LOW | Existing transfer path + signature check; no main approval needed. |
| Child → developer wallet payment | In-app purchases / game payments | MEDIUM | Destination = registered developer wallet; consensus checks destination. |
| Processing-reward split (dev cut / child) | Child earns GNUS via background inference | MEDIUM | Reuse escrow `peers_cut`+`dev_addr` (HoldEscrow/PayEscrow); per-child policy. |
| Main-wallet registration (dual-signature) | Establishes parent-child authority | HIGH | Both child + main signatures; consensus-recorded; the crux feature. |
| Registration record schema | Must be well-specified for consensus | MEDIUM | child pubkey, main pubkey, both sigs, seq/nonce, timestamp, optional game/publisher/dev-wallet/split. |
| Consensus-recorded relationship (CRDT-backed) | Authority "enforced by consensus" not UI | HIGH | New CRDT namespace + element filter; broadcast over pubsub. |
| Main-wallet discovery of its children | Main must find registered children | MEDIUM | Main subscribes to child pubsub channel(s); reads CRDT registration set. |
| Main-wallet balance/asset monitoring | Display child balances without child key | MEDIUM | CRDT sync of child UTXO/asset state to main. |
| Main → child funding | Main can transfer funds into child | MEDIUM | Consensus verifies main signature + child registered that main. |
| Main-recover-from-child | Recover funds if game uninstalled / key lost | HIGH | Consensus verifies registered-main signature + destination = registered main (restricted). |
| Reject child-spends-main | Security invariant | MEDIUM | Consensus rejects any tx spending main funds without main signature. |
| Lifecycle states | standalone/pending/registered/detached/revoked/closed | MEDIUM | State machine + valid transitions in consensus rules. |
| Replay/reorder protection | Registration integrity under CRDT | HIGH | Monotonic seq + consensus ordering; see PITFALLS. |

### Differentiators (Design Decisions That Add Value)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Change/replace registered main wallet | Recover from lost main; migrate wallets | HIGH | Seq-guarded; policy fork: require old-main consent or not. |
| Detach main (return to standalone) | Non-destructive un-linking | MEDIUM | Child remains valid wallet after detach. |
| Per-child processing policy (configurable split up to 100%) | Developer monetization flexibility | MEDIUM | `dev_addr` + `peers_cut` per child/game registration. |
| Publisher grouping in main-wallet UI | UX for many child wallets | LOW | UI-only; not consensus. Design describes conceptually (UI out of scope for build). |
| Rich child metadata (game, publisher, dev wallet, cut, dates, activity, status) | Discovery/monitoring quality | MEDIUM | Optional registration fields + activity read from CRDT. |
| Authenticated developer-wallet / split updates | Prevent silent payout redirection | HIGH | Update requires appropriate signatures (dev/publisher/child/main). |

### Anti-Features (Design Must Explicitly Exclude / Warn Against)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| One shared child key across multiple apps | Shared balance/NFTs across publisher's games | Compromise of ANY app compromises ALL shared assets (proposal §Sharing) | One child wallet per app; publisher grouping in UI only |
| Main wallet with blanket spend authority over child | "Full control" convenience | Turns recovery into seizure; expands main-key blast radius | Destination-restricted recovery (to registered main) |
| Deriving child from main seed for the link | "Simpler key management" | Main-seed exposure compromises all children; breaks bounded-compromise goal | Independent per-child keypairs + explicit registration |
| Timestamp-only ordering of registrations | "Simple latest-wins" | Spoofable, clock-skew, no CRDT total order → replay/hijack | Monotonic seq + consensus ordering |
| Storing main private key in game/child process | "Convenient signing" | Directly violates the central security principle | Connect-GNUS-Wallet flow; main signs out-of-process |

## Feature Dependencies

```
Independent child keypair
    └──enables──> Standalone operation
    └──enables──> Child-signed arbitrary transfer
    └──enables──> Child → developer payment

Main-wallet registration (dual-signature)
    └──requires──> Registration record schema
    └──requires──> Consensus-recorded relationship (CRDT)
        └──enables──> Main-wallet discovery
            └──enables──> Balance/asset monitoring
        └──enables──> Main → child funding
        └──enables──> Main-recover-from-child
    └──requires──> Replay/reorder protection

Change/replace registered main ──requires──> Lifecycle states + seq protection
Reject child-spends-main ──requires──> Consensus authority layer (NEW; none today)
Processing-reward split ──enhances──> Standalone AND registered children
```

### Dependency Notes

- **Discovery/monitoring/funding/recovery all require registration + CRDT record:** no authority exists until the relationship is consensus-recorded.
- **All main-authority rules require a NEW consensus hierarchical-authority layer:** today `CheckTransactionAuthorization` is signature-only (TxMgr.cpp:4361) — this is the highest-risk dependency.
- **Replace/detach require lifecycle + seq:** ordering guarantees must exist before mutation flows are safe.
- **Reward split is independent of registration:** a standalone child still earns; policy just routes the split.

## MVP Definition (Design-Doc Coverage)

### Launch With (v1 design docs)

- [ ] Child identity & keypair model — foundation for everything
- [ ] Registration protocol (dual-signature + record schema + proto) — the core mechanism
- [ ] CRDT persistence + pubsub broadcast/subscription of registration — makes authority real
- [ ] Consensus rules for all six authority cases — the security contract
- [ ] Discovery + balance sync design — delivers main-wallet value
- [ ] Processing-reward policy for children — monetization path
- [ ] Lifecycle + registration-change flows — completeness + replay safety

### Add After Validation (v1.x)

- [ ] Authenticated developer-wallet/split update flows — trigger: developers need to rotate payout addresses
- [ ] Rich activity-history monitoring — trigger: main-wallet UX maturity

### Future Consideration (v2+)

- [ ] Cross-application shared children (explicitly discouraged) — defer/likely never; document risks
- [ ] Threshold/social-recovery for main wallet — defer; separate concern from child model

## Feature Prioritization Matrix

| Feature | User Value | Implementation (Design) Cost | Priority |
|---------|------------|------------------------------|----------|
| Child identity model | HIGH | MEDIUM | P1 |
| Registration protocol + schema | HIGH | HIGH | P1 |
| Consensus authority rules | HIGH | HIGH | P1 |
| CRDT + pubsub registration flow | HIGH | HIGH | P1 |
| Discovery + balance sync | HIGH | MEDIUM | P1 |
| Reward split policy | MEDIUM | MEDIUM | P2 |
| Lifecycle + change/replace | MEDIUM | HIGH | P2 |
| Dev-wallet update auth | MEDIUM | MEDIUM | P2 |
| Cross-app sharing | LOW | HIGH | P3 (discouraged) |

## Competitor Feature Analysis

| Feature | Session-key wallets (ERC-4337) | Custodial game subaccounts | Our Approach |
|---------|-------------------------------|-----------------------------|--------------|
| Child independence | Scoped session keys, revocable | Fully custodial (no user key) | Fully independent keypair, non-custodial |
| Parent authority | Smart-contract validation | Server-side ACL | Consensus-recorded registration record |
| Recovery | Owner key recovers | Provider recovers | Registered main, destination-restricted |
| Discovery | On-chain events | Provider DB | CRDT state + pubsub subscription |

## Sources

- `GNUS_Subwallet_Architecture_Proposal.md` — authoritative feature list — HIGH
- SuperGenius codebase audit (escrow split, transaction/authorization paths) — HIGH
- Public wallet-delegation patterns (session keys, custodial subaccounts) for comparison — MEDIUM

---
*Feature research for: child-wallet design on SuperGenius*
*Researched: 2026-07-13*
