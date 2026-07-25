# Stack Research

**Domain:** Isolated sub-networks ("subnets") layered under an existing libp2p/GossipSub + CRDT/GlobalDB blockchain node (SuperGenius/GeniusNode)
**Researched:** 2026-07-24
**Confidence:** MEDIUM (patterns cross-checked against multiple independent-system precedents; no code changes made or tested, this is a docs-only research pass)

## Context: What Already Exists (grounding for every recommendation below)

Before recommending anything, here is what SuperGenius already has, verified by reading the current source tree:

| Existing mechanism | Where | Relevance to subnets |
|---|---|---|
| `net_id` (`uint16_t`) — 369=mainnet, 963=testnet, 144=devnet | `src/base/sgns_version.hpp/cpp` | The outer half of the `net_id.subnet_id` composite address already exists and is load-bearing today |
| `subnet_id` (`uint16_t`, default 0) | `GeniusNode.hpp:949`, `TransactionManager.hpp:118,452,622` | **Already threaded through the constructor chain end-to-end** (`GeniusNode` → `TransactionManager::New`) but currently just stored — comment literally says "(reserved)". Nothing derives a topic, CRDT key, or consensus check from it yet. This is the load-bearing seam this milestone's design should target. |
| `sgns_config.json` → `net_id`, `subnet_id` fields | `GeniusNode.cpp:344,394` | Config placement already decided — this milestone documents the *scheme*, not a new config location |
| `GetNetAndVersionAppendix()` → `".%hu"` + `".%hu.%hu"` | `src/base/sgns_version.hpp/cpp` | Single shared helper already used by **every** topic-construction call site (`AccountMessenger`, `Consensus`, `processing_service`, `pubsub_broadcaster_ext`, `GeniusNode`) to append `.<net_id>.<major>.<minor>` to a base topic name. This is the one seam to extend for subnet-aware topics — not a new mechanism. |
| `"/bc-%hu/"` (`TRANSACTION_BASE_FORMAT`) / `GetBlockChainBase(network_id)` | `TransactionManager.hpp:369,418` | CRDT key-prefix scoping by network already exists at this exact granularity |
| GossipSub pubsub | `thirdparty/ipfs-pubsub` (fork of `ipfs_pubsub::GossipPubSub`, wrapping `thirdparty/libp2p` fork's GossipSub impl) | This *is* the transport for topic namespacing — no new transport library needed |
| CRDT / GlobalDB | `src/crdt/globaldb/*`, `crdt_datastore.hpp` | Consensus-visible state sync already exists; `Put(key, value, topics)` already takes an explicit topic set per write |
| `CheckParentChildAuthority`, `CheckCertifiedParent` | `src/blockchain/Blockchain.cpp`, `Consensus.hpp` | Validated consensus-authority-gate pattern for one first-class trust relationship (main↔registered-child); the closest in-repo precedent for a subnet-gateway authority gate |
| EVM bridge: `BridgeCatchupWatcher`/`BridgeRpcWatcher` (`src/watcher/impl`), `ConsensusManager::IsBridgeMintSubject` (`Consensus.hpp:405`), `ChainContractPair`, `bridge_chains_config.json` | `src/watcher`, `src/blockchain/Consensus.hpp`, `src/account` | **This is the closest in-repo precedent for "bridge design."** GNUS↔EVM already uses: watcher polls source-chain events → decoded burn log handed to a callback → `TransactionManager`/`ConsensusManager` mints on GNUS side once the mint proposal passes `IsBridgeMintSubject`. The main↔subnet bridge should be a variant of this shape, not a new architecture. |
| Registration-transaction pattern (D-06, D-11/D-12) — first-class tx type + dedicated CRDT namespace + CRDT filter gates + pubsub broadcast | `TransactionManager` tx-type dispatch, `reg/` CRDT namespace | Validated pattern for "register a new first-class entity via a signed transaction, discoverable via CRDT sync" — directly reusable for subnet registration/allocation |

**Conclusion up front:** almost nothing here calls for a *new third-party library*. SuperGenius's stack (libp2p GossipSub, Boost.Asio, Protobuf, CRDT/GlobalDB, the existing `TransactionManager` dispatch and `ConsensusManager` gate system) is already sufficient. The "stack addition" this milestone needs is a set of **conventions and one new component category** (a subnet gateway/watcher), reusing existing machinery — see "What NOT to Use" below for the traps to avoid.

## Recommended Stack

### Core Technologies (already present — no version change needed)

| Technology | Version (as vendored) | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| libp2p (private fork, `thirdparty/libp2p`, commit-pinned not tag-versioned) | current pinned commit (`1ae9b49`) | GossipSub transport for all pubsub topics, including new subnet-scoped ones | Already the sole pubsub transport in the codebase; subnet isolation is a **topic-naming convention layered on top**, not a protocol change — GossipSub itself has no concept of "networks," isolation is 100% application-layer (see Ethereum precedent below) |
| `ipfs-pubsub` (private fork, `thirdparty/ipfs-pubsub`) wrapping libp2p GossipSub | current pinned commit (`1605636`) | `GossipPubSub`/`GossipPubSubTopic` C++ wrapper used by `GlobalDB`, `AccountMessenger`, `Consensus` | Same reasoning — no new pubsub library needed |
| Protocol Buffers | `v5.34.0` (vendored, `thirdparty/protobuf`) | Wire format for transactions (`EmbeddedTransaction` oneof) | Already the schema mechanism for all first-class tx types (`RegistrationTx`, `TransferTx`, etc.); a subnet-registration/gateway tx is a new oneof case, not a new serialization stack |
| Boost.Asio 1.85.0 (vendored, `thirdparty/boost`) | 1.85.0 | Async I/O for any new watcher component | Matches existing `boost::asio::io_context`-threaded pattern used throughout `TransactionManager`/`GlobalDB`/watchers |
| RocksDB (vendored, `thirdparty/rocksdb`) | as vendored | CRDT/GlobalDB backing store | Already scoped per `/bc-<net_id>/` prefix; subnet scoping is a key-prefix extension, not a new store |

### Supporting Conventions/Patterns To Add (not libraries — design patterns to formalize in the design doc)

| Pattern | Modeled on | Purpose | When to Use |
|---------|---------|---------|-------------|
| Composite dotted addressing, `net_id.subnet_id` (e.g. `144.100`) | SuperGenius's own `NET_ID_APPENDIX`/`SGNS_VERSION_APPENDIX` dotted-decimal convention (`.%hu`, `.%hu.%hu`) — reinforced by Polkadot's hierarchical `MultiLocation` (parent-relative addressing, no fixed global root) | Human-readable, hierarchical subnet address that visually nests under its parent net, matching a pattern already idiomatic in this codebase | All new subnet-aware config, logging, CLI/API surface |
| Fork-digest-style topic suffixing: always include `subnet_id` as an explicit topic segment (default `0` for "no subnet"), never conditionally omitted | Ethereum consensus-layer p2p spec: `/eth2/{ForkDigest}/{Name}/{Encoding}` with `beacon_attestation_{subnet_id}` — same GossipSub substrate SuperGenius already runs on | Extend `GetNetAndVersionAppendix()` (or a new sibling `GetSubnetAppendix()`) to a single shared helper so every topic-construction call site (`AccountMessenger`, `Consensus`, `processing_service`, `pubsub_broadcaster_ext`, `TransactionManager::GetBlockChainBase`) gets subnet scoping for free, exactly like net_id scoping today | Every pubsub topic and CRDT key prefix that must not leak across subnet boundaries |
| Hierarchical CRDT key prefix: `/bc-<net_id>/sn-<subnet_id>/...` (subnet segment nested under, not flattened into, the existing `/bc-<net_id>/` prefix; `sn-0` = main net, collapses to today's behavior) | SuperGenius's existing `TRANSACTION_BASE_FORMAT = "/bc-%hu/"` extended one level, styled after Polkadot's parent-relative `MultiLocation` nesting | Keeps subnet-less nodes/queries byte-identical to today (backward compatible default), while giving subnet-scoped queries a clean, greppable prefix boundary | All new CRDT namespaces this milestone touches (registration, jobs, gateway) |
| Reuse the registration-transaction pattern (first-class tx type + dedicated CRDT namespace + CRDT filter gate + pubsub broadcast, D-06/D-11/D-12) for **subnet registration/allocation** instead of inventing a new allocation mechanism | SuperGenius's own validated child-wallet `RegistrationTx` pattern; conceptually parallel to how Cosmos chain-ids and Avalanche subnet-creation txs are recorded on a canonical anchor chain | Main net is the natural allocation authority for `subnet_id` values (avoids collisions) the same way it already is for child registration — a `SubnetRegistrationTx` recorded in `/bc-<net_id>/subnets/` is discoverable via the same CRDT-sync + pubsub-broadcast + filter-gate mechanism already proven for `reg/` | Subnet creation/allocation flow specifically |
| Native "gateway" bridge transaction pair (lock-on-source / mint-on-destination), consensus-gated by a new `CheckSubnetGatewayAuthority`-style check mirroring `CheckParentChildAuthority`/`CheckCertifiedParent`; observed by a `SubnetGatewayWatcher` built on the existing `watcher::MessagingWatcher` base (same shape as `BridgeCatchupWatcher`/`BridgeRpcWatcher`, but its "chain" to watch is the gateway CRDT namespace/pubsub topic, not an external EVM RPC endpoint) | Closest fit is **Avalanche Warp Messaging's trust model** (message authenticated by the *source domain's own validator/authority set*, verified natively by the destination — no external light client, no third-party custodian), **not** Cosmos IBC's light-client+Merkle-proof model and **not** an Ethereum-style external escrow-contract bridge | Main↔subnet are partitions of the *same* overall GNUS network sharing a root trust anchor (unlike IBC's fully independent, mutually-untrusting chains, or an L2's need to inherit L1 finality across a challenge period) — so authority can be derived the same way `CheckCertifiedParent` already derives main's authority over a child: from a CRDT-recorded registration record, not from a Merkle light client or BLS validator-set signature scheme SuperGenius doesn't otherwise have | The one-and-only main↔subnet GNUS token bridge/gateway this milestone must design |
| Invariant carried over from L2/lock-mint precedent: **minted supply on the destination side must never exceed what was actually locked/burned on the source side** | Universal lock-mint / burn-mint bridge security invariant (Ethereum L2 canonical bridges, cross-chain bridge post-mortems) | Non-negotiable design constraint regardless of which trust model is chosen — the design doc must show a UTXO-level invariant (locked-on-source ⇔ minted-on-destination) enforced by the same `ConsensusManager` gate that decides mint eligibility | The bridge/gateway design deliverable specifically |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| None new | — | This milestone is docs-only; no new build tooling, no new CMake targets, no new CI steps are in scope |

## Installation

Not applicable — no new dependencies are being added. All recommendations reuse already-vendored submodules (`thirdparty/libp2p`, `thirdparty/ipfs-pubsub`, `thirdparty/protobuf`, `thirdparty/boost`, `thirdparty/rocksdb`) and already-present in-repo classes (`TransactionManager`, `ConsensusManager`, `watcher::MessagingWatcher`, `GlobalDB`).

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Native gateway tx + CRDT-derived authority gate (Avalanche-AWM-flavored) | Cosmos IBC-style light client + Merkle packet-commitment proofs | Only if a subnet were ever operated by a mutually-untrusting third party with **no shared root authority** with the main net (i.e. subnets stop being "ours" and become genuinely federated/external chains). Not the case for this milestone's stated scope. |
| Native gateway tx + CRDT-derived authority gate | Ethereum-style escrow/vault smart contract + wrapped-asset mint | Only if subnets ran on a different VM/execution environment than SuperGenius itself (there's no contract-execution layer here to escrow into) |
| Hierarchical CRDT key `/bc-<net_id>/sn-<subnet_id>/` | Flat composite key `/bc-<net_id>.<subnet_id>/` | If a future requirement needs subnet_id-agnostic prefix scans across *all* subnets under a net_id to be a single contiguous key range rather than requiring a nested-prefix scan — either works with RocksDB prefix iteration, this is a naming preference, not a functional blocker |
| Always-present `subnet_id` topic segment (default 0) | Conditionally omit the segment when `subnet_id == 0` | Never recommended — conditional omission is exactly the ambiguity Ethereum's spec avoids by fixing topic *shape*; a subnet-unaware old node and a subnet_id=0 main-net node must produce byte-identical topic strings, which conditional formatting can silently break if the helper's branches ever diverge |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| A second pubsub/gossip library or protocol for subnet-specific traffic | GossipSub (via the existing `ipfs-pubsub` fork) already handles arbitrary topic-scoped broadcast; adding a second transport doubles the attack surface and network-stack maintenance burden for zero functional gain | Extend the existing topic-naming convention (subnet_id as a topic segment) on the existing GossipSub instance |
| A new CRDT/state-sync framework for subnet-scoped state | `GlobalDB`/`CrdtDatastore` already supports arbitrary hierarchical key prefixes and per-write topic sets (`Put(key, value, topics)`) | Reuse `GlobalDB` with a subnet-scoped key prefix, same as net_id scoping today |
| BLS aggregate signatures (Avalanche AWM's actual signature scheme) purely to imitate AWM | SuperGenius doesn't use BLS anywhere else in its consensus/signature stack (child-wallet and registration flows use its existing ed25519/secp signature + CRDT-derived-authority model, per D-60); introducing a second signature primitive just for the gateway would be a real new dependency with real key-management/rotation implications, contradicting the "reuse what's proven" principle that shaped D-60 | Reuse the CRDT-derived-authority model already validated for `CheckCertifiedParent`/`CheckParentChildAuthority` — authority is established by a CRDT-recorded registration record, not by a new cryptographic aggregation scheme |
| A Merkle-proof / light-client verification layer (IBC's `ICS-02`/`ICS-07`-style tracked consensus state) | Massive engineering lift (header-tracking client, fraud/misbehavior handling, per-counterparty client state) that only pays for itself when the two sides are mutually untrusting, independently operated chains — not true for a main net and its own subnet | CRDT sync + consensus-gate authority check (main and subnet nodes are peers of the same overall system and already share CRDT visibility patterns via the existing D-49 follow-mechanism) |
| A new external smart-contract-style escrow/vault component | There's no contract-execution VM in this stack (unlike the EVM side of the existing GNUS↔Ethereum bridge, which legitimately needs one) | A UTXO-level lock/reserve on the source ledger enforced by `TransactionManager`, mirroring how `RecoverFromChild`/D-21 already restricts destination on a transfer |
| Reinventing the watcher framework | `watcher::MessagingWatcher` (base class already used by `BridgeCatchupWatcher`/`BridgeRpcWatcher`) already owns its own thread, handles start/stop lifecycle, and has a proven callback-forwarding shape | Subclass `MessagingWatcher` for the new `SubnetGatewayWatcher`, swapping only the "what am I watching" data source (CRDT/pubsub gateway namespace instead of `eth_getLogs` polling) |
| Flat, non-hierarchical `subnet_id` treated as a fully independent net_id (i.e., minting a brand-new `net_id` per subnet instead of nesting it) | Breaks the explicit milestone framing (`net_id.subnet_id` composition under a parent) and loses the backward-compatibility property that subnet_id=0 collapses to current mainnet behavior everywhere | Keep `net_id` as today's outer scope, add `subnet_id` as the inner/nested scope exactly as the reserved field already implies |

## Stack Patterns by Variant

**If a subnet needs to process jobs with zero visibility into main-net or sibling-subnet job queues:**
- Fold `subnet_id` into the processing/job-queue channel names the same way it's folded into every other topic (`processing_service.cpp`'s `processingGridChannelId`, `processing_subtask_queue_channel_pubsub.cpp`'s `processingQueueChannelId`, `processing_subtask_queue_accessor_impl.cpp`'s `RESULT_CHANNEL_ID_*`)
- Because this is the exact same mechanism as topic namespacing (#2 in the target deliverables) — job isolation is not a separate technical problem, it's an application of the same `GetNetAndVersionAppendix()`-style helper extension to the processing subsystem's existing topic-construction call sites

**If subnet_id=0 (no subnet, plain main net):**
- All topic strings, CRDT key prefixes, and consensus gates must be byte-identical to current behavior
- Because every existing single-net deployment (and every existing test) implicitly assumes `subnet_id == 0` today — this is the hard backward-compatibility constraint any implementation phase must preserve

**If a future subnet needs to bridge assets to more than one other subnet (not just the main net):**
- The gateway pattern generalizes to any `(net_id, subnet_id)` pair as source/destination, not just "subnet → main"
- Because the recommended trust model (CRDT-derived authority + native lock/mint tx pair) doesn't hard-code "main" as a privileged endpoint — it only requires both sides to be running the same overall SuperGenius consensus fabric with a recorded registration linking them, so subnet-to-subnet gateways are the same mechanism, not a new one — but this milestone should still document a single canonical main-anchored gateway first, since that's the stated v1.0 scope

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Extended `GetNetAndVersionAppendix()`-family topic helper (subnet-aware) | Existing `subnet_id_ = 0` default already wired through `GeniusNode`/`TransactionManager` | No proto/config schema change needed to *carry* subnet_id — it's already in `sgns_config.json` and the constructor chain. Only the topic/CRDT-key *formatting* logic needs to change, and only that change needs to preserve `subnet_id==0` ⇒ identical output to today |
| Any new `SubnetRegistrationTx`/gateway-tx proto message | `EmbeddedTransaction` oneof dispatch (`DeSerializeEmbeddedTransaction`) | Follow the exact same oneof-case-dispatch pattern already used for `RegistrationTx`; do **not** introduce a parallel string-based `transaction_parsers` lookup path — that path already had one silent gap this milestone's predecessor found and fixed (missing `"registration"` entry), it is the harder-to-audit of the two dispatch mechanisms already coexisting in `TransactionManager` |
| `ipfs-pubsub`/libp2p fork commit pins | Any topic-naming change | Purely additive at the application layer — GossipSub topic strings are opaque byte strings to libp2p itself, so no libp2p/ipfs-pubsub version bump is required for any of these recommendations |

## Sources

- Cosmos IBC-Go docs, Interchain Developer Academy (light client / packet-commitment / relayer architecture) — MEDIUM confidence (web search, cross-checked against multiple independent write-ups; stable, long-documented protocol)
- Polkadot Wiki / Gavin Wood's original XCM post (MultiLocation hierarchical addressing) — MEDIUM confidence (web search, cross-checked)
- Avalanche Builder Hub / Avalanche blog (Avalanche Warp Messaging, `AddressedPayload`, BLS-signed validator-set verification) — MEDIUM confidence (web search, cross-checked)
- Ethereum.org / cross-chain bridge architecture write-ups (lock-mint vs burn-mint patterns, L2 canonical bridge security model) — MEDIUM confidence (web search, cross-checked)
- `ethereum/consensus-specs` `phase0/p2p-interface.md` (GossipSub topic naming `/eth2/{ForkDigest}/{Name}/{Encoding}`, `beacon_attestation_{subnet_id}` subnet suffixing) — MEDIUM confidence (web search; this is the direct protocol-identical precedent since it uses the same GossipSub substrate SuperGenius already runs)
- SuperGenius source tree (`src/base/sgns_version.hpp/cpp`, `src/account/GeniusNode.{hpp,cpp}`, `src/account/TransactionManager.{hpp,cpp}`, `src/blockchain/Consensus.hpp`, `src/watcher/impl/bridge_catchup_watcher.hpp`, `src/account/bridge_chains_config.json`, `src/crdt/globaldb/globaldb.hpp`) — HIGH confidence (first-party, read directly from the working tree)
- `thirdparty/` submodule commit pins (`ipfs-pubsub`, `libp2p`, `boost` 1.85.0, `protobuf` v5.34.0, `rocksdb`) — HIGH confidence (read directly via `git submodule status` / `git log`)

---
*Stack research for: GNUS Subnets (main↔subnet addressing, pubsub namespacing, token bridge/gateway, job isolation)*
*Researched: 2026-07-24*
