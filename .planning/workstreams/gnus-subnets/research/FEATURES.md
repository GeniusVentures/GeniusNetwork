# Feature Research

**Domain:** Isolated subnet/sidechain architecture for GNUS SuperGenius (addressing, pubsub namespacing, token bridge, job isolation)
**Researched:** 2026-07-24
**Confidence:** HIGH (addressing/bridge patterns — multiple corroborating primary-source ecosystems) / MEDIUM (job-isolation-for-compute-jobs specifics, since GNUS's "job" concept is a compute marketplace, not just tx/block processing, and no directly comparable public ecosystem does this)

## Comparative Ecosystem Snapshot

| System | Unit of isolation | Addressing | Security/validator model | Bridge model |
|---|---|---|---|---|
| **Avalanche Subnets** | Subnet (own VM, own validator subset) | 32-byte `subnetID` + `blockchainID`, validators opt in per subnet via node config | Subnet-specific validator set (can differ from Primary Network) | Interchain Messaging (ICM/"Warp") + Interchain Token Transfer (ICTT): hub-and-spoke, one "home" contract per asset, lock-and-mint / native-mint on spoke |
| **Polkadot Parachains** | Parachain (`ParaId`) | `ParaId` (u32) registered in relay-chain state | Shared/pooled security — relay chain validators finalize every parachain block, no separate validator set per para | XCM (message format, not a bridge) relayed *through* the relay chain — relay chain validators arbitrate trust, chains never trust each other directly |
| **Cosmos IBC Zones** | Zone (independent chain, own `chain-id`) | `chain-id` + per-connection `client-id`/`channel-id` | Fully independent validator set per zone; trust delegated to a light client of the counterparty | ICS-20 escrow/voucher: lock on source, mint IBC voucher (`ibc/<hash>`) on destination carrying a denom trace path; burn voucher + unlock on return |
| **Ethereum L2 (rollups/sidechains)** | L2 chain (own `chainId`, EIP-155) | Global chain-id registry (chainlist.org) | Rollups inherit L1 security via fraud/validity proofs; sidechains run fully independent validator sets | Canonical bridge per L2 (Arbitrum Bridge, Optimism Standard Bridge, Base Bridge) — lock-and-mint, with a finality/challenge window (e.g. 7-day fraud-proof window on optimistic rollups) |

**Key structural takeaway for GNUS:** GNUS subnets are much closer to **Polkadot parachains** than to Avalanche subnets or Cosmos zones — a subnet shares the *same node software and consensus family* as the main net (not a sovereign chain with its own independent validator set that must be trust-bridged in from scratch). This means GNUS can reuse its own consensus/authority-gate machinery for subnet trust instead of needing a light-client or federated-bridge protocol built from nothing — a materially cheaper and safer path than most public-chain ecosystems had available to them.

## Feature Landscape

### Table Stakes (Expected Behavior)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Globally unique, hierarchically-composed subnet identifier (`net_id.subnet_id`) | Every reference ecosystem has this: Avalanche `subnetID`, Polkadot `ParaId`, Cosmos `chain-id`, Ethereum `chainId`. Ambiguous/duplicate IDs break routing, topic naming, and accounting everywhere downstream. | LOW | Matches PROJECT.md's `net_id.subnet_id` composite (e.g. `144.100`). Parent net must be recoverable from the composite by simple parsing, not a lookup. |
| Centrally-allocated (not free-form) subnet ID allocation/registry | Free-form IDs risk collision and squatting (this is precisely why chainlist.org exists for Ethereum chain IDs, and why Polkadot's ParaId is assigned via relay-chain slot auction/registration, not self-chosen). | LOW-MEDIUM | Directly reuses the existing `reg/` CRDT-namespace + pubsub-sync pattern already built for child-wallet registration — a `subnet-reg/` (or similar) namespace is the natural analog. **Direct dependency on existing CRDT `reg/` + pubsub sync mechanism.** |
| Subnet config manifest tied to the subnet ID (`config_json` placement) | Every ecosystem needs a place to declare subnet-specific parameters (Avalanche's VM config + genesis, Polkadot's parachain genesis state, Cosmos zone's chain-registry entry). Without it, nodes can't know how to join/validate a subnet they haven't seen before. | LOW | Config should be resolvable *from* the subnet ID (e.g., stored keyed by `net_id.subnet_id` in the same registry CRDT), not a side channel that can drift out of sync with the ID registry. |
| PubSub topic names carry the full composite subnet ID | Every isolation-by-subnet system partitions its gossip/relay layer by identifier: Avalanche validators only gossip for subnets in their config; Polkadot collators are assigned per-para; Cosmos zones simply don't share a p2p network at all. Traffic isolation is achieved at the transport/topic layer, not just the application layer. | LOW-MEDIUM | This is GNUS's own dedicated phase ("PubSub channel namespacing") — table stakes finding here is simply: **the subnet ID must be a first-class segment of the topic string**, e.g. `/bc-{net_id}.{subnet_id}/reg/...`, not an attribute carried inside message payloads only (payload-only scoping still costs every subscriber the bandwidth/CPU to receive and discard off-subnet traffic). |
| Explicit node opt-in/subscription per subnet | No reference system defaults nodes to processing every subnet's traffic. Avalanche: add subnet ID to node config. Polkadot: collator assigned to a specific para. Cosmos: a zone's nodes never even see other zones' gossip. | LOW | Nodes not participating in subnet `144.100` should not subscribe to its pubsub topics or receive its jobs by default. |
| Subnet-aware consensus/authority checks | Trust checks must know which network segment a transaction/job belongs to, or a main-net validator could misapply subnet rules to main-net traffic (or vice versa). Cosmos scopes trust per light client + channel; Polkadot scopes finality per para; Avalanche scopes validation per subnet's validator set. | MEDIUM | **Direct dependency on existing `CheckParentChildAuthority`/`CheckCertifiedParent` gates** — these already parameterize "is this signer authorized for this scoped address," and the natural extension is parameterizing them by subnet scope as well as by parent/child role. This is far less work than building a net-new authorization model. |
| Single canonical bridge/gateway per subnet↔mainnet corridor | Every L2 "ships with a canonical bridge" (Arbitrum, Optimism, Base); Avalanche's ICTT uses one "home" contract per asset in a hub-and-spoke; Cosmos IBC's transfer module is the singular sanctioned path per channel. Multiple competing bridge paths for the same asset fragment liquidity and multiply attack surface. | MEDIUM | Matches PROJECT.md's "likely via a single gateway/bridge mechanism" framing directly — this is confirmed table stakes, not a design risk to relitigate. |
| Conservation-preserving accounting (escrow/lock on one side, controlled mint/unlock on the other) | This is the *only* pattern used across Cosmos IBC (escrow + voucher), Avalanche ICTT (lock-and-mint), and Ethereum canonical bridges (lock-and-mint) — total supply must remain provably 1:1 across the corridor at all times. | MEDIUM | Since PROJECT.md specifies bridging to "the canonical GNUS token" (not a new wrapped asset), the pattern should be **escrow-on-main + mint-representation-on-subnet**, symmetric with **burn-on-subnet + unlock-on-main**, tracked as CRDT-visible transactions — not two independently-minted tokens. |
| Bridge transactions are provable/attributable through the same consensus-visible mechanism as everything else | Bridge accounting that lives outside consensus-visible state (e.g., an off-chain federated ledger) is exactly the failure mode behind most public bridge hacks (Ronin, Wormhole, Nomad — see Pitfalls research). | MEDIUM | Reuse the CRDT + pubsub sync pattern already proven for `reg/` — bridge deposits/withdrawals should be "just another namespaced transaction type," consistent with how `RegistrationTx` was added as a first-class transaction type rather than a side-channel. |

### Differentiators (Where GNUS Can Do Better)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Reuse of existing consensus-gate architecture instead of a bolt-on bridge protocol | Most ecosystems had to build trust-minimization from scratch (light clients, fraud proofs, federated multisigs) because their subnets/zones are sovereign chains. GNUS subnets share the same node software/consensus family as the main net, so `CheckParentChildAuthority`/`CheckCertifiedParent`-style gates can be *extended* to subnet scope rather than replaced with an external bridge protocol. This is architecturally cheaper and has a smaller, more auditable trust surface than Cosmos-style light clients or Avalanche-style Warp signature aggregation. | LOW-MEDIUM (relative to alternatives — still needs the subnet-scope parameterization work) | This is the single biggest structural advantage GNUS has over the public-chain precedents; call it out explicitly in the design doc as the reason the bridge phase should be scoped as "extend existing gates" rather than "design a new bridge protocol." |
| Elastic job-processing capacity shared with (not siloed from) the main net's compute pool | Avalanche subnets and Cosmos zones require each network to bootstrap and retain its *own* dedicated validator/compute capacity — a new subnet is capacity-poor until it attracts its own operators. GNUS's job-processing model (a compute marketplace, not just a ledger) could let a subnet's job queue optionally draw on main-net compute capacity under explicit policy, rather than requiring the subnet to have already attracted enough dedicated nodes. No public reference ecosystem does this because none of them separate "consensus validator" from "job/compute executor" the way SuperGenius's job-processing model does. | MEDIUM-HIGH | Must be explicit/opt-in and clearly bounded — silently blurring the isolation boundary defaults into the anti-feature below. Flag as a **future differentiator**, not part of this milestone's four deliverables. |
| Composite addressing designed to be extensible to nested subnets | `net_id.subnet_id` composition is naturally extensible to `net_id.subnet_id.subsubnet_id` if a future need arises, unlike Avalanche/Polkadot/Cosmos which all use a flat namespace (no ecosystem here nests subnets/parachains/zones within each other). | LOW to design for, HIGH if actually implemented | Recommend: design the addressing scheme so it *doesn't preclude* nesting later, but do not build nesting support now — no reference ecosystem needed it, and it multiplies pubsub-topic and consensus-gate complexity combinatorially. Treat as an extension point noted in the design doc, not a v1 feature. |

### Anti-Features (Avoid These)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|------------------|-------------|
| Per-subnet independent validator sets / bespoke consensus rules (Avalanche-style) | Looks flexible — "let each subnet tune its own trust model" | Multiplies the number of distinct `CheckXxxAuthority`-style gates that must be independently audited, and reintroduces exactly the sovereign-chain trust-bridging problem GNUS's shared-consensus-family design lets it avoid. For a compute-job network this is pure overhead with no matching benefit. | Keep one consensus/validator model across main net and all subnets; scope authority checks by subnet_id parameter, not by swapping in a different trust mechanism per subnet. |
| Free-form/self-chosen subnet ID strings | Feels lightweight for developers to spin up a subnet without waiting on an allocator | Collision risk, topic-namespace ambiguity, and squatting — the exact problem Ethereum's chain-id ecosystem still deals with today via chainlist.org, and exactly what Polkadot's ParaId registration process exists to prevent. | Centrally allocate small integer subnet IDs under a given `net_id`, mirroring ParaId/chain-id registry conventions; validate at registration time via the existing CRDT registry pattern. |
| Default cross-subnet job visibility (any node can subscribe to every subnet's topics to pick up work) | "More jobs available to more compute" sounds efficient | Destroys the isolation guarantee that's the entire point of subnets — every node pays the bandwidth/CPU cost of every subnet's traffic, which is the same trap sharded chains and Ethereum's data-availability sharding design explicitly avoid via mandatory per-shard topic subscription. | Default: nodes subscribe only to main net + subnets they've explicitly opted into; cross-subnet job discovery (if ever wanted) is a deliberate, separate feature, not a side effect of address design. |
| Wrapped/derivative subnet-side token distinct from canonical GNUS | Mirrors Avalanche ICTT's "native asset on spoke" pattern and looks like it cleanly isolates subnet accounting | PROJECT.md explicitly requires bridging to "the canonical GNUS token" — minting a separately-named derivative reintroduces the wrapped-token fragmentation problem the Ethereum ecosystem is still trying to undo (see ERC-7281/xERC20 efforts to make cross-chain tokens fungible again). Creates N different "GNUS-on-subnet-X" assets instead of one fungible GNUS. | Escrow + mint-of-canonical-accounting on the subnet side (not a new asset symbol/contract per subnet), so token identity stays singular regardless of which network segment holds it. |
| Federated/multisig external bridge validators, separate from GNUS's own consensus | Fast to stand up without touching consensus code | This is the precise root cause behind the largest public bridge hacks: Ronin ($624M, 5 compromised validator keys), Wormhole ($320M, deprecated signature-check bypass), Nomad (zero-Merkle-root accepted as valid) — see Pitfalls research. GNUS already has a consensus-integrated authority-gate mechanism proven for child-wallet transfers; a parallel federated bridge would be both duplicated effort and a strictly weaker security model bolted on next to a stronger one that already exists. | Extend `CheckParentChildAuthority`/`CheckCertifiedParent`-style gates to subnet scope instead of introducing a separate bridge-specific trust mechanism. |
| Unlimited/uncapped bridging with no rate limit or finality delay | Feels like better UX — "instant, unlimited transfers" | Every reference bridge has *some* safety valve against runaway drain if a gate is ever compromised or buggy: optimistic rollups' 7-day fraud-proof window, IBC's timeout+ordered-channel semantics, Avalanche Warp's signature-aggregation threshold. Removing this turns any future authorization bug into an unbounded-loss event rather than a bounded, catchable one. | At minimum, design the bridge with a rate-limit/cap policy hook from day one (ties directly to the already-deferred POL-01 transfer-limits work), even if the cap value/enforcement isn't implemented this docs-only milestone. |

## Feature Dependencies

```
Subnet ID allocation/registry (subnet-reg/ CRDT namespace)
    └──requires──> Existing reg/ CRDT namespace + D-49 pubsub sync pattern (child-wallet registration)

PubSub topic namespacing (per-subnet topics)
    └──requires──> Subnet ID allocation/registry (topic string embeds the allocated composite ID)

Subnet-scoped job processing/isolation
    └──requires──> PubSub topic namespacing (jobs dispatched/discovered via subnet-scoped topics)
    └──requires──> Subnet-aware consensus/authority checks (a job's validity must resolve against the correct subnet scope)

Bridge/gateway (main <-> subnet token movement)
    └──requires──> Subnet ID allocation/registry (bridge accounting keyed by net_id.subnet_id)
    └──requires──> Existing CheckParentChildAuthority / CheckCertifiedParent gates (extended to subnet scope, not replaced)
    └──requires──> Existing CRDT registration-as-transaction-type pattern (bridge txs modeled the same way RegistrationTx was added)

Elastic cross-subnet compute sharing (differentiator, deferred)
    └──enhances──> Subnet-scoped job processing
    └──conflicts──> Default cross-subnet job visibility anti-feature (must be explicit/policy-gated, never silent default)

Nested subnet addressing (differentiator, deferred)
    └──enhances──> Subnet ID allocation/registry (only if designed to remain extensible)
```

### Dependency Notes

- **Subnet ID allocation requires the existing `reg/` CRDT namespace + pubsub sync:** This is the single strongest reuse opportunity in the whole feature set. The registration mechanism already built for child wallets (child-signed record, CRDT persistence under a dedicated namespace, pubsub broadcast, main-node discovery via `RegElementCallback`) is structurally identical to what a subnet registry needs — a subnet is just a different *kind* of registered entity than a child wallet. The design doc should treat this as "the same registry pattern, a new namespace and entity type," not a new subsystem.
- **PubSub topic namespacing requires the subnet ID registry to exist first:** topic strings can't embed a `net_id.subnet_id` composite that hasn't been allocated/validated yet — allocation is a hard prerequisite, not parallelizable with topic-scheme design (though the topic *scheme* can be designed in parallel, it can't be deployed/tested without an ID to plug in).
- **Job isolation requires both topic namespacing and subnet-aware authority checks:** namespacing alone (transport-layer isolation) is necessary but not sufficient — a job could still be gossiped only on the right topic yet be validated by a consensus gate that doesn't know which subnet it belongs to, reopening cross-subnet contamination at the validation layer.
- **The bridge/gateway requires the existing `CheckParentChildAuthority`/`CheckCertifiedParent` gates as its foundation, not a new protocol:** this is the load-bearing dependency for the whole bridge design question. Because these gates already solve "is this signer authorized to move value across a scoped-address boundary" for main↔child, the bridge design task is "generalize the scope parameter from child-address to subnet-address," which is a materially smaller design problem than the "build interchain trust from zero" problem every public-chain ecosystem faced.
- **Elastic cross-subnet compute sharing conflicts with the default-cross-subnet-visibility anti-feature:** the differentiator only works if it's an explicit, policy-gated escape hatch (e.g., main-net capacity opts in to serve subnet overflow) — if implemented as "nodes just subscribe to everything," it collapses into the anti-feature and defeats the isolation goal entirely.

## MVP Definition

### Launch With (v1 — this docs-only milestone's four deliverables)

- [ ] Subnet addressing scheme (`net_id.subnet_id` composition + allocation/registry design) — foundational; every other deliverable depends on it existing first
- [ ] PubSub topic namespacing scheme (subnet_id folded into topic strings) — table stakes for traffic isolation, required before job isolation can be designed
- [ ] Bridge/gateway design (single canonical corridor, escrow/mint-of-canonical pattern, gate reuse from `CheckParentChildAuthority`/`CheckCertifiedParent`) — table stakes, and the design should explicitly document the gate-reuse dependency as the reason this is lower-risk than a from-scratch bridge protocol
- [ ] Job isolation & consensus impact design (subnet-scoped job scheduling, CRDT/registration/validation-gate subnet-awareness) — table stakes, depends on both addressing and topic namespacing being settled first

### Add After Validation (v1.x, future milestones)

- [ ] Rate-limit/cap policy for bridge transfers (extends deferred POL-01) — trigger: bridge design moves from docs to implementation
- [ ] Subnet-to-subnet direct bridging (bypassing main net) — trigger: a concrete multi-subnet use case emerges that can't tolerate main-net-mediated latency/cost

### Future Consideration (v2+)

- [ ] Elastic/shared compute capacity across subnet boundaries — defer until at least one subnet is live and capacity-starvation is an observed (not hypothetical) problem
- [ ] Nested subnet addressing (`net_id.subnet_id.subsubnet_id`) — defer indefinitely unless a concrete need appears; no reference ecosystem needed this

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Subnet addressing/allocation scheme | HIGH | LOW-MEDIUM | P1 |
| PubSub topic namespacing | HIGH | LOW-MEDIUM | P1 |
| Bridge/gateway design (gate-reuse based) | HIGH | MEDIUM | P1 |
| Job isolation & consensus subnet-awareness | HIGH | MEDIUM | P1 |
| Bridge rate-limit/cap policy | MEDIUM | LOW-MEDIUM | P2 |
| Elastic cross-subnet compute sharing | MEDIUM | HIGH | P3 |
| Nested subnet addressing | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for this milestone's design doc (the four target deliverables)
- P2: Should have, flag as a near-term follow-on in the design doc
- P3: Nice to have, future consideration — mention as an extension point, don't design in depth

## Competitor/Reference Feature Analysis

| Feature | Avalanche Subnets | Polkadot Parachains | Cosmos IBC Zones | GNUS Subnets (recommended approach) |
|---------|--------------------|----------------------|-------------------|--------------------------------------|
| Identity | 32-byte `subnetID` + `blockchainID` | `ParaId` (u32) in relay-chain state | `chain-id` + client/channel IDs | Composite `net_id.subnet_id`, centrally allocated, parent recoverable by parsing |
| Validator/consensus model | Independent per-subnet validator set | Shared/pooled — relay chain validates every para | Fully independent per zone | Shared consensus family with main net; authority gates parameterized by subnet scope, not swapped out |
| Traffic isolation | Validators opt in per subnet at node-config level | Collators assigned per para | No shared p2p network at all between zones | PubSub topics carry the composite subnet ID; explicit per-subnet subscription, no default cross-subnet visibility |
| Bridge/token movement | ICM/Teleporter + ICTT hub-and-spoke, lock-and-mint | XCM relayed through relay chain (trust arbitrated by relay validators) | ICS-20 escrow + voucher with denom trace | Single canonical gateway; escrow-on-main + mint-of-canonical-accounting on subnet, using existing `CheckParentChildAuthority`/`CheckCertifiedParent` gates extended to subnet scope rather than a new bridge protocol |
| Safety valve on bridge | Warp signature-aggregation threshold | N/A (single trust domain via relay chain) | Timeout + ordered-channel semantics | Recommend rate-limit/cap policy hook (ties to deferred POL-01), deferred to implementation phase |

## Sources

- [What Is an Avalanche Subnet? — Gate Learn](https://www.gate.com/learn/articles/what-is-avalanche-subnet) — MEDIUM confidence (secondary/educational source, cross-checked against official docs)
- [ACP-77: Reinventing Subnets — Avalanche Builder Hub](https://build.avax.network/docs/acps/77-reinventing-subnets) — HIGH confidence (official Avalanche documentation)
- [Subnets: Supercharging Scalability on Avalanche — Figment.io](https://www.figment.io/insights/scalability-on-avalanche/) — MEDIUM confidence (infrastructure-provider technical content)
- [ICM Contracts / ICTT Overview — Avalanche Builder Hub](https://build.avax.network/docs/cross-chain/teleporter/overview) — HIGH confidence (official docs)
- [Avalanche Interchain Token Transfer — GitHub (ava-labs)](https://github.com/ava-labs/avalanche-interchain-token-transfer) — HIGH confidence (official implementation repo)
- [Overview of the Polkadot Relay Chain — Polkadot Developer Docs](https://docs.polkadot.com/reference/polkadot-hub/consensus-and-security/relay-chain/) — HIGH confidence (official documentation)
- [Parachains Overview — Polkadot Developer Docs](https://docs.polkadot.com/reference/parachains/) — HIGH confidence (official documentation)
- [Get Started with XCM — Polkadot Developer Docs](https://docs.polkadot.com/parachains/interoperability/get-started/) — HIGH confidence (official documentation)
- [XCM Transport Methods (XCMP, HRMP, VMP) — Polkadot Wiki](https://wiki.polkadot.com/learn/learn-xcm-transport/) — HIGH confidence (official wiki)
- [Understand IBC Denoms — Interchain Developer Academy](https://ida.interchain.io/tutorials/6-ibc-dev/) — HIGH confidence (official Cosmos/Interchain educational docs)
- [ICS-20 Fungible Token Transfer spec — cosmos/ibc GitHub](https://github.com/cosmos/ibc/blob/main/spec/app/ics-020-fungible-token-transfer/README.md) — HIGH confidence (official protocol spec)
- [Overview — IBC-Go transfer module docs](https://ibc.cosmos.network/main/apps/transfer/ics20-v1/overview/) — HIGH confidence (official docs)
- [Bridges — ethereum.org](https://ethereum.org/developers/docs/bridges/) — HIGH confidence (official Ethereum Foundation documentation)
- [What is a Canonical Bridge? — Cube Exchange](https://www.cube.exchange/what-is/canonical-bridge) — MEDIUM confidence (secondary/exchange educational source)
- [How To Make Cross-Chain Tokens Fungible Again: ERC-7281 — Gate Learn](https://www.gate.com/learn/articles/how-to-make-cross-chain-tokens-fungible-again-part-ii/7084) — MEDIUM confidence (secondary source, cross-checked against EIP text)
- [ERC-7802: Token With Mint/Burn Access Across Chains — eips.ethereum.org](https://eips.ethereum.org/EIPS/eip-7802) — HIGH confidence (official EIP)
- Bridge hack postmortem synthesis (Ronin, Wormhole, Nomad) via [Building Secure Blockchain Bridges — DEV Community](https://dev.to/koxy/building-secure-blockchain-bridges-common-vulnerabilities-and-solutions-2431) and [How Crypto Bridges Move Billions — yellow.com](https://yellow.com/learn/how-crypto-bridges-move-billions) — MEDIUM confidence (secondary summaries of widely-reported, well-corroborated incidents; incident facts themselves are HIGH confidence given cross-source agreement)
- GNUS internal context: `W:\gnus\GeniusNetwork\.planning\PROJECT.md` (existing child-wallet mechanisms: `RegistrationTx`, CRDT `reg/` namespace, D-49 pubsub sync, `CheckParentChildAuthority`, `CheckCertifiedParent`) — HIGH confidence (primary project source)

---
*Feature research for: GNUS Subnets (subnet addressing, pubsub namespacing, token bridge, job isolation)*
*Researched: 2026-07-24*
</content>
