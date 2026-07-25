# Architecture Research

**Domain:** GNUS subnet integration into an existing gossip-pubsub + CRDT + transaction-dispatch consensus node (SuperGenius `GeniusNode`)
**Researched:** 2026-07-24
**Confidence:** HIGH (grounded directly in current SuperGenius source — `GeniusNode.hpp/.cpp`, `TransactionManager.hpp/.cpp`, `sgns_version.hpp/.cpp`, `BridgeRelayer.hpp/.cpp`, `Blockchain.cpp`, `processing_service.cpp` — not external docs)

## Standard Architecture

### System Overview — today (single net, no subnets)

```
┌───────────────────────────────────────────────────────────────────────────┐
│ GeniusNode  (config_json: net_id only; subnet_id_ field exists, unused)   │
├───────────────────────────────────────────────────────────────────────────┤
│  ┌────────────────────┐   ┌─────────────────────┐   ┌───────────────────┐ │
│  │ ipfs_pubsub::       │   │ crdt::GlobalDB        │   │ TransactionManager │ │
│  │ GossipPubSub        │   │ (tx_globaldb_,        │   │  - transaction_    │ │
│  │  - AccountMessenger │   │  job_globaldb_)       │   │    parsers{} table │ │
│  │  - Consensus votes  │   │  keyspace: /bc-{net}/ │   │  - CheckParentChild│ │
│  │  - Processing grid  │   │   ├─ tx/{hash}        │   │    Authority       │ │
│  │    channel          │   │   ├─ reg/{addr}       │   │  - ValidateWitness │ │
│  │  - ProcessingService│   │   └─ proof/{hash}     │   │    ForConsensus    │ │
│  │  - Subtask/result   │   └─────────┬─────────────┘   └─────────┬─────────┘ │
│  │    channels         │             │                            │         │
│  └──────────┬──────────┘             │                            │         │
│             │      all topic names   │      all CRDT paths        │         │
│             └───────► + GetNetAndVersionAppendix() = ".{net_id}" ◄─┘         │
│                       (single process-global network_id_, sgns_version.cpp) │
├───────────────────────────────────────────────────────────────────────────┤
│  Blockchain (consensus gate host)                                           │
│   - CheckCertifiedParent(addr) → reads /bc-{net}/reg/{addr}, no genius_node  │
│     dependency (one-directional link preserved)                             │
├───────────────────────────────────────────────────────────────────────────┤
│  Bridge (external-chain analog, NOT a subnet mechanism)                     │
│   - BridgeRelayer + eth::EthWatchService: watches EVM burn events on N      │
│     chains → GeniusNode::MintFunds() on this net                            │
└───────────────────────────────────────────────────────────────────────────┘
```

**Key existing fact that reshapes the whole design:** `net_id` is not per-node config data that flows cleanly through the stack — it is a **single process-global static** (`static uint16_t network_id_` in `sgns_version.cpp`), read by `version::GetNetworkID()` and written once by `version::SetNetworkId(net_id)`. Every topic name, every CRDT keyspace path, and `TransactionManager::GetMonitoredNetworkIDs()` derive from this one global, not from a value threaded per-call. `SetNetworkId` further **whitelists exactly three values** (`MAIN_NET_ID=369`, `TEST_NET_ID=963`, `DEV_NET_ID=144`) and throws `std::invalid_argument` on anything else.

A `subnet_id_` field already exists end-to-end as a placeholder: `sgns_config.json` → `GeniusNode::LoadSgnsConfig()` (parsed at line ~394) → stored on `GeniusNode` (`subnet_id_`, comment: "reserved") → passed into `TransactionManager::New(...)` → stored as `TransactionManager::subnet_id_` (comment: "Subnet ID from config (reserved)"). **It is read and stored but not consumed anywhere** — not in a topic string, not in a CRDT path, not in a consensus gate, not in `GetMonitoredNetworkIDs()`. This is the exact seam the subnet feature needs to activate.

### Component Responsibilities

| Component | Responsibility today | What changes for subnets |
|-----------|----------------------|---------------------------|
| `sgns::version` (`sgns_version.hpp/.cpp`) | Global `network_id_` static; `GetNetworkID()`/`SetNetworkId()`; `GetNetAndVersionAppendix()` builds the `.{net_id}` suffix appended to every pubsub topic and, transitively via `TRANSACTION_BASE_FORMAT`, every CRDT path | **Modified.** Must carry a composite ID (net_id + subnet_id), and `SetNetworkId`'s 3-value whitelist must be relaxed to accept `(net_id, subnet_id)` pairs where `net_id` is still one of the 3 canonical nets but `subnet_id` is validated against a registry/range instead of hardcoded |
| `GeniusNode` (`GeniusNode.hpp/.cpp`) | Top-level orchestrator; owns `pubsub_`, `tx_globaldb_`, `job_globaldb_`, `transaction_manager_`, `blockchain_`; reads `net_id`/`subnet_id` from `sgns_config.json` in `LoadSgnsConfig()` | **Modified.** `subnet_id_` goes from stored-but-inert to actually driving topic/keyspace construction; likely gains an explicit "is this node a subnet member, and of which subnet(s)" concept, and (for gateway-role nodes) dual pubsub/CRDT membership |
| `TransactionManager` (`TransactionManager.hpp/.cpp`) | Tx-type dispatch (`transaction_parsers` table: `transfer`, `mint`, `registration`, `revoke`); `GetBlockChainBase()`/`GetMonitoredNetworkIDs()` build CRDT paths; hosts `CheckParentChildAuthority`, `CheckTransactionAuthorization`, `ValidateWitnessForConsensus` | **Modified + extended.** `GetBlockChainBase()` needs subnet-aware path composition; `GetMonitoredNetworkIDs()` needs a subnet analog (a node must know which subnet keyspaces to watch); `transaction_parsers` gains one or two new tx types for bridge burn/mint-equivalent between net and subnet; a new gate analogous to `CheckParentChildAuthority` is needed for bridge transactions |
| `Blockchain` (`impl/Blockchain.cpp`, `Blockchain.hpp`) | Hosts `CheckCertifiedParent` (reads `/bc-{net}/reg/{addr}` directly, no `genius_node` dependency — preserves the one-directional `blockchain_genesis` ← `genius_node` link) | **Modified.** Needs a subnet-aware registration/authority lookup if the bridge gateway's authority is expressed the same way certified-parent authority is (CRDT-recorded relationship, not raw signature delegation) |
| `crdt::GlobalDB` (`crdt/globaldb/globaldb.hpp/.cpp`) | CRDT-backed keyspace per net, `RegisterElementFilter`/`RegisterNewElementCallback` on path-prefix regexes (e.g. `^/?bc-{net}/reg/[^/]+`) | **Modified (namespacing only, not the CRDT engine itself).** Subnet traffic needs its own keyspace root so subnet CRDT deltas never collide with, or get accidentally synced into, main-net keyspace |
| `ipfs_pubsub::GossipPubSub` / `GossipPubSubTopic` (thirdparty `ipfs-pubsub`) | libp2p gossipsub wrapper; topics are plain strings (`AccountMessenger`, `Consensus`, `ProcessingServiceImpl::Listen`, subtask/result channels) all append `version::GetNetAndVersionAppendix()` | **Not modified itself** — it's a generic pubsub transport. Only the topic-string construction call sites change (all already funnel through one function, which is the leverage point) |
| `BridgeRelayer` + `eth::EthWatchService` (`account/BridgeRelayer.hpp/.cpp`, `evmrelay/`) | Existing main↔external-EVM-chain bridge: watches `BridgeSourceBurned`/`BridgeOutInitiated` EVM log events across N chains, calls `TransactionManager::MintFunds()` on detection | **Not modified — used as the design template**, not the mechanism. A subnet bridge is CRDT-native (both sides are SuperGenius/CRDT, no EVM), so it needs a **new, parallel component**, not a change to this one |
| *(new)* Subnet Bridge/Gateway | — | **New.** CRDT-native analog of `BridgeRelayer`: watches a burn/lock-equivalent tx in one net's/subnet's CRDT keyspace, and — once finalized under that side's consensus — emits a mint/unlock tx into the other side's keyspace |
| *(new)* Subnet Registry | — | **New.** Consensus-visible record of which `subnet_id`s exist under a `net_id`, analogous to the existing `reg/` child-wallet registry pattern — needed so `SetNetworkId`'s current hardcoded 3-value whitelist can be replaced with an actual validation source |

## Recommended Integration Structure

```
config_json (sgns_config.json)
├── net_id            # existing, unchanged (144/369/963)
└── subnet_id          # existing field, currently inert — becomes load-bearing

sgns::version (modified)
├── NetworkIdentity{ net_id, subnet_id }   # replaces bare uint16_t network_id_
├── GetNetAndVersionAppendix()             # now emits ".{net_id}.{subnet_id}" (subnet_id==0 ⇒ main net, unchanged string)
└── SetNetworkId(net_id, subnet_id)        # net_id whitelist unchanged; subnet_id checked against Subnet Registry, not hardcoded

TransactionManager (modified)
├── GetBlockChainBase(net_id, subnet_id)   # keyspace root becomes /bc-{net}.{subnet}/
├── GetMonitoredNetworkIDs()                # gains sibling GetMonitoredSubnetIDs() (mirrors DEV→TEST/MAIN cross-visibility pattern)
├── transaction_parsers{}                   # + "subnet_bridge_out", "subnet_bridge_in" (or reuse "mint"/"transfer" with a subnet-scoped source/dest, see Data Flow)
└── CheckParentChildAuthority-style gate    # + CheckSubnetBridgeAuthority(tx): mint-on-subnet/mint-on-mainnet only valid if matching burn is CRDT-confirmed on the other side

Blockchain (modified)
└── CheckCertifiedParent-style lookup       # + subnet-scoped registry read, if gateway authority is modeled the same way

crdt::GlobalDB (namespacing only)
└── keyspace root /bc-{net}.{subnet}/       # subnet CRDT lives in its own root; main net's root untouched

ipfs_pubsub topics (namespacing only)
└── every topic += ".{net}.{subnet}"        # single leverage point: GetNetAndVersionAppendix()

(new) Subnet Registry
└── consensus-visible list of subnet_id under net_id, gates SetNetworkId + bridge trust

(new) Subnet Bridge/Gateway component
└── CRDT-native burn-watch → mint-emit, modeled on BridgeRelayer but internal (no EVM)
```

### Structure Rationale

- **Composite ID lives at the `sgns::version` layer, not scattered per-call:** every subnet-aware consumer (pubsub topics, CRDT paths, monitored-network lists) already funnels through `GetNetworkID()`/`GetNetAndVersionAppendix()`/`GetBlockChainBase()`. Extending the identity *at its single source* is far cheaper than threading a new parameter through dozens of call sites — the existing code already centralized this exact seam for us.
- **`subnet_id == 0` must mean "main net, unchanged behavior":** since `subnet_id_` already defaults to `0` everywhere it's declared (`GeniusNode.hpp` line 949, `TransactionManager.hpp` line 622), the addressing/topic/keyspace formatting must special-case 0 to produce byte-identical strings to today's main-net-only build. This is what keeps the feature backward-compatible with every existing deployed net (144/369/963) with zero migration.
- **The bridge is a new component, not a repurposed one**, because `BridgeRelayer` is fundamentally an EVM-log watcher (`AbiValue` decoding, `ChainRpcEndpointProvider`) — there is no EVM chain on the subnet side. The *pattern* (watch a burn-equivalent event on side A, mint on side B, gated by a certified-authority check) transfers; the *implementation* does not.
- **Job isolation piggybacks on CRDT + pubsub namespacing, it isn't a separate mechanism:** `ProcessingServiceImpl::Listen()` already builds its grid-channel topic as `processingGridChannelId + GetNetAndVersionAppendix()` — the same function used everywhere else. Once the appendix carries `subnet_id`, job broadcast is isolated *for free*. Nothing subnet-specific needs to be added to `processing_service.cpp` beyond that one shared call already covering it.

## Architectural Patterns

### Pattern 1: Single global identity function as the sole leverage point

**What:** All net-scoping in the existing codebase passes through exactly one function (`version::GetNetAndVersionAppendix()`) for pubsub topics and one derived function (`GetBlockChainBase()`) for CRDT paths — both ultimately reading the same `network_id_` global.
**When to use:** Extend the identity *at the source*, not at each of the ~10+ call sites (`AccountMessenger.cpp`, `Consensus.cpp`, `processing_service.cpp`, `processing_subtask_queue_channel_pubsub.cpp`, `processing_subtask_queue_accessor_impl.cpp`, `pubsub_broadcaster_ext.cpp`, migration files).
**Trade-offs:** Low blast radius, but it does mean the composite identity is *still* a process-global — a single `GeniusNode` process is bound to one `(net_id, subnet_id)` pair at a time, same as today's one-`net_id`-per-process constraint. A gateway node that must simultaneously see main-net and subnet-net keyspaces cannot just "read the global twice" — it needs an explicit second identity/second `GlobalDB`/second pubsub-topic-set, constructed side-by-side (see Anti-Pattern 1).

**Example (illustrative, not exact code):**
```cpp
// today
std::string full_topic = topic + version::GetNetAndVersionAppendix(); // ".144"

// with subnets, subnet_id defaulting to 0 preserves today's string exactly
std::string full_topic = topic + version::GetNetAndVersionAppendix(); // net_id=144, subnet_id=0 -> ".144" (unchanged)
                                                                       // net_id=144, subnet_id=100 -> ".144.100"
```

### Pattern 2: Certified-authority-via-CRDT-registration, not cryptographic delegation

**What:** `CheckCertifiedParent`/`CheckParentChildAuthority` do not use signature delegation (main's key never signs "as" the child). Instead, authority is established by a **CRDT-recorded relationship** (`reg/{child_addr}` naming a `main_address`), and a special-cased branch in `CheckTransactionAuthorization` accepts the main's *own* signature on a child-sourced tx only when that CRDT record exists (D-60, established during the child-wallet work).
**When to use:** This is the template for subnet bridge authority too. A "gateway" address's signature on a mint-on-subnet tx should only be accepted if the *burn on the main-net side is itself CRDT-confirmed* — i.e., the gate reads the other side's keyspace the same way `CheckCertifiedParent` reads `reg/`, rather than trusting a bare signature or an off-chain relayer claim.
**Trade-offs:** Requires the gate to have read access to *both* keyspaces (main-net root and subnet root), which is a real architectural requirement on whichever node hosts the consensus gate for bridge transactions (almost certainly the gateway node, and/or full nodes on both sides that mirror both keyspaces read-only).

### Pattern 3: Cross-net visibility already has a working precedent — `GetMonitoredNetworkIDs()`

**What:** `TransactionManager::GetMonitoredNetworkIDs()` already special-cases: a node on `DEV_NET_ID` also monitors `TEST_NET_ID` and `MAIN_NET_ID` (used everywhere `GetBlockChainBase(network_id)` is looped over for tx/reg queries: lines ~1225, ~1359, ~1937, ~5413).
**When to use:** This is the direct precedent for "a main-net node needs visibility into its subnets' bridge-relevant CRDT state" (and vice versa for a subnet node needing to see main-net confirmation of an inbound bridge). A `GetMonitoredSubnetIDs()` sibling, populated from the Subnet Registry rather than hardcoded, is a mechanical extension of an already-proven pattern — not a new concept.
**Trade-offs:** Watching N additional keyspaces means N times the CRDT sync/query traffic on whichever node does the watching — this is exactly why the milestone context flags "job isolation" as a separate concern from "bridge": a subnet job-processing node should almost certainly *not* also be monitoring main-net or sibling-subnet keyspaces (that would defeat isolation), whereas the gateway node specifically *should*.

## Data Flow

### Token crossing main net → subnet → main net (recommended design)

```
[User/child wallet on MAIN NET]
    │  TransferFunds(amount, dest=<gateway/bridge address>, token=GNUS)
    ▼
[TransactionManager, main-net keyspace /bc-{net}/]
    │  ordinary "transfer" tx, consensus-finalized under existing gates
    │  (no new tx type needed for the "lock" leg — reuse "transfer" to a
    │   well-known gateway address, same as the existing EVM bridge reuses
    │   a burn-to-null-address pattern conceptually)
    ▼
[Subnet Bridge/Gateway component — NEW, modeled on BridgeRelayer]
    │  watches /bc-{net}/tx/ for finalized transfers to the gateway address
    │  (CRDT new-element callback / RegisterElementFilter, same primitive
    │   TransactionManager already uses for reg/ and tx/)
    ▼
[TransactionManager, subnet keyspace /bc-{net}.{subnet}/]
    │  gateway emits a "mint"-equivalent tx crediting the destination
    │  subnet address; CheckSubnetBridgeAuthority gate (NEW, modeled on
    │  CheckCertifiedParent) verifies the matching main-net lock tx exists
    │  and is finalized before accepting the mint
    ▼
[Subnet-scoped job processing, pubsub topics/CRDT under /bc-{net}.{subnet}/,
 completely isolated from main net and sibling subnets]

--- return leg (subnet → main net) is the mirror image ---

[Subnet account] --"transfer" to gateway address, subnet-side finalized-->
[Gateway] --watches subnet keyspace, emits "mint"-equivalent on main net-->
[Main-net TransactionManager] --CheckSubnetBridgeAuthority verifies subnet lock-->
[Main-net destination account credited]
```

**Why reuse `transfer`+gated-`mint` instead of inventing a dedicated `bridge_out`/`bridge_in` tx type:** the existing EVM bridge already establishes the pattern of "lock/burn on side A is an ordinary transaction; the crediting on side B is a `mint`-family tx gated by proof-of-the-other-side" (`MintFunds()` is called by `BridgeRelayer` after external verification). Reusing `TransactionManager`'s existing `"mint"` entry in `transaction_parsers` (already present, already wired to `ParseMintTransaction`/`RevertMintTransaction`) for the subnet-mint leg minimizes new proto/dispatch surface — the milestone's own project memory notes a preference for reusing existing transaction types over inventing new proto messages where the shape already fits. The new work is narrowly the **gate** (`CheckSubnetBridgeAuthority`) that must cross-check the other side's keyspace before accepting the mint, not the tx type itself.

## Scaling / Isolation Considerations

| Concern | Single subnet | Several subnets under one net | Subnet nesting |
|---------|---------------|-------------------------------|----------------|
| CRDT keyspace collision | `/bc-{net}.{subnet}/` root prevents any collision with `/bc-{net}/` main root | Each subnet gets its own root; a main-net node does **not** need to sync every subnet's full keyspace, only bridge-relevant paths (mirrors `GetMonitoredNetworkIDs`'s selective monitoring, not blanket sync) | Not addressed by this milestone's scope (`net_id.subnet_id` is a fixed 2-level composite, not arbitrarily deep) — flag as an explicit non-goal in the design doc unless the roadmap wants it |
| Pubsub topic fan-out | One extra topic suffix segment, same gossipsub mesh | N subnets = N independent topic sets; nodes that aren't gateways or subnet members simply never subscribe, so fan-out cost is opt-in, not global | — |
| Job scheduling | Subnet-scoped `processing_grid_chanel_topic_` fully isolates job broadcast from main net | Each subnet's job pool is independent; a subnet's `ProcessingServiceImpl` only ever sees its own subnet's grid topic, so a busy subnet cannot starve another subnet's or main net's job queue | — |
| Bridge trust | One gateway address/component is a single point of trust — same trust shape as today's `authorized_full_node`/certified-parent model, not a new trust primitive | A registry of one gateway per subnet, or one shared gateway servicing all subnets under a net, is a design choice the roadmap phase should make explicitly (shared gateway = simpler, single point of contention; per-subnet gateway = more isolation, more components) | — |

## Anti-Patterns

### Anti-Pattern 1: Treating `subnet_id` as "just another field on the existing global"

**What people do:** Bump `network_id_` to also carry `subnet_id` and assume any node can flip between identities at will.
**Why it's wrong:** `network_id_` is a single process-global `static`. A gateway node (or any full node monitoring both a subnet and its parent net) needs **simultaneous** access to two keyspaces/topic-sets, not sequential access to one-then-the-other. A single mutable global cannot represent "I am watching both `/bc-144/` and `/bc-144.100/` right now."
**Instead:** Keep the *default* identity (the one `GetNetworkID()`/`GetNetAndVersionAppendix()` resolve to, used for this node's own transactions and job processing) as the single global — that's correct and sufficient for ordinary main-net-only or subnet-only nodes. For gateway/monitoring roles, add an explicit **second, non-global handle** (a second `GlobalDB` instance rooted at the other keyspace, a second set of pubsub topic subscriptions) rather than trying to make the global itself multi-valued. This mirrors how `GeniusNode` already owns two `GlobalDB` instances (`tx_globaldb_` and `job_globaldb_`) side by side — the pattern for "more than one keyspace handle per node" already exists in the codebase.

### Anti-Pattern 2: Letting the bridge gate trust a bare signature instead of the other side's CRDT state

**What people do:** Have the gateway sign the mint tx and let ordinary `CheckSignature()` pass it.
**Why it's wrong:** This collapses the bridge's security to "trust the gateway's private key," identical to the weakness the child-wallet work explicitly avoided (D-60's whole point was *not* doing raw signature delegation). A compromised or buggy gateway could mint tokens on the subnet with no on-chain proof a matching lock ever happened on the main-net side.
**Instead:** The gate must read the *other side's* keyspace and require a finalized, matching lock/burn record before accepting the mint — exactly the `CheckCertifiedParent`-style pattern (Pattern 2 above), not a `CheckSignature()`-only path.

### Anti-Pattern 3: Extending `SetNetworkId`'s whitelist by just adding subnet IDs to the same 3-value enum-like check

**What people do:** Add every valid `(net,subnet)` pair as a new hardcoded constant next to `MAIN_NET_ID`/`TEST_NET_ID`/`DEV_NET_ID`.
**Why it's wrong:** That whitelist was fine for 3 fixed nets that never change, but a subnet space is meant to be created/allocated dynamically (the milestone explicitly asks for a "validation/allocation" scheme for subnet addressing). Hardcoding subnet IDs into source defeats the purpose and requires a rebuild for every new subnet.
**Instead:** Keep `net_id` validated against the existing 3-constant whitelist (unchanged — subnets only exist under real nets), but validate `subnet_id` against the **Subnet Registry** (a consensus-visible, CRDT-backed list, same pattern as the `reg/` child-wallet registry) rather than a compiled-in constant.

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `sgns::version` ↔ everything else | Direct function calls (`GetNetworkID()`, `GetNetAndVersionAppendix()`, `GetBlockChainBase()`) | Single choke point — the cheapest place to introduce composite-ID awareness; touching it correctly (with `subnet_id==0` byte-identical to today) is the highest-leverage, lowest-risk change in the whole feature |
| `GeniusNode` ↔ `TransactionManager` | Constructor injection (`subnet_id` already passed at `TransactionManager::New(..., subnet_id)`) | Wiring already exists; this boundary needs **no new plumbing**, only for `TransactionManager` to start *using* the value it already receives |
| `TransactionManager` ↔ `crdt::GlobalDB` | Path-string keys (`GetBlockChainBase() + "tx/"` etc.) and `RegisterElementFilter`/`RegisterNewElementCallback` regex patterns | Every regex pattern that currently hardcodes `"^/?" + blockchain_base + "reg/[^/]+"`-style strings needs re-deriving per subnet-scoped `blockchain_base`; this is mechanical once `GetBlockChainBase()` itself is subnet-aware |
| `TransactionManager` ↔ `Blockchain` | `CheckCertifiedParent()` call, `SetSlotHashPopulator` callback | If bridge authority reuses the certified-parent pattern, `Blockchain` needs a subnet-scoped analog lookup, which — like `CheckCertifiedParent` today — should **not** create a new dependency back onto `genius_node` (preserve the existing one-directional `blockchain_genesis` ← `genius_node` link, per the existing D-63 constraint) |
| Subnet Bridge/Gateway ↔ both keyspaces | CRDT new-element callbacks on both sides + tx submission on both sides | New component; needs read access to main-net keyspace and subnet keyspace simultaneously (see Anti-Pattern 1) — this is the one place in the whole design that structurally cannot be a single-identity node in the "ordinary node" sense |

## Suggested Build Order (with rationale — differs slightly from the milestone's listed order)

The milestone's target-deliverable list orders topics as: addressing → pubsub namespacing → bridge/gateway → job isolation. Based on the dependency shape found in the code, this research recommends:

1. **Addressing scheme first** (`net_id.subnet_id` composition, `sgns::version` composite identity, `subnet_id` validation/allocation via a Subnet Registry). *Rationale:* every other topic area — pubsub topic strings, CRDT keyspace roots, and the bridge's two-sided keyspace access — reads from this one identity source. Nothing else can be designed concretely (not even "what does a subnet pubsub topic look like") until the composite ID's string/byte representation is fixed.

2. **PubSub topic namespacing second.** *Rationale:* this is the cheapest, most mechanical follow-on — a one-function change (`GetNetAndVersionAppendix()`) already touches every topic call site in the codebase. It's also a prerequisite for job isolation (the processing grid channel topic is *just* one more caller of that same function), so it must land before job isolation can be verified end-to-end.

3. **Job isolation & consensus impact third** (CRDT keyspace namespacing, `GetBlockChainBase()`/`GetMonitoredNetworkIDs()` subnet-awareness, `transaction_parsers`/consensus-gate subnet-scoping). *Rationale:* this is where "isolation" actually becomes real and testable — a subnet's jobs, CRDT state, and transaction validation must demonstrably not leak into or depend on main-net state before it makes sense to build a *bridge* connecting the two. Designing the bridge against a subnet that isn't genuinely isolated yet would bake in wrong assumptions.

4. **Bridge/gateway last.** *Rationale:* the bridge's entire trust model (Pattern 2 / Anti-Pattern 2) depends on being able to read a *finalized, isolated* state on both sides — which only exists once steps 1–3 are in place. It also introduces the one genuinely novel component (a CRDT-native two-sided watcher, modeled on but not reusing `BridgeRelayer`), so it benefits from being scoped last, once the addressing/topic/keyspace vocabulary it needs to describe "lock on side A, mint on side B" already has a fixed, implemented shape.

If the roadmap prefers to keep the milestone's original ordering (bridge before job isolation) for scheduling reasons, the one hard dependency to preserve regardless of order is: **addressing before everything, pubsub namespacing before job isolation** (since job isolation's channel-topic half *is* pubsub namespacing applied to one more call site).

## Sources

- Direct source inspection (HIGH confidence — primary source, not documentation):
  - `SuperGenius/src/account/GeniusNode.hpp`, `GeniusNode.cpp` (config loading, `subnet_id_` field, orchestration wiring)
  - `SuperGenius/src/account/TransactionManager.hpp`, `TransactionManager.cpp` (`transaction_parsers`, `GetBlockChainBase`, `GetMonitoredNetworkIDs`, `CheckParentChildAuthority`, `CheckTransactionAuthorization`, `ValidateWitnessForConsensus`)
  - `SuperGenius/src/base/sgns_version.hpp`, `sgns_version.cpp` (global `network_id_`, `SetNetworkId` whitelist, `GetNetAndVersionAppendix`)
  - `SuperGenius/src/account/BridgeRelayer.hpp`, `BridgeRelayer.cpp` (existing external-chain bridge pattern used as design template)
  - `SuperGenius/src/blockchain/impl/Blockchain.cpp`, `Blockchain.hpp` (`CheckCertifiedParent`, D-63 one-directional dependency constraint)
  - `SuperGenius/src/processing/processing_service.cpp` (`ProcessingServiceImpl::Listen`, grid channel topic construction)
  - `SuperGenius/src/crdt/globaldb/globaldb.cpp/.hpp`, `pubsub_broadcaster_ext.cpp` (CRDT keyspace/filter mechanics, topic appendix usage)
  - `.planning/PROJECT.md` (workstream goal, prior child-wallet consensus-gate precedent, key decisions D-60/D-63)

---
*Architecture research for: GNUS subnet integration (v1.0 gnus-subnets workstream)*
*Researched: 2026-07-24*
