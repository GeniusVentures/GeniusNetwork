# Project Research Summary

**Project:** GNUS Subnets (gnus-subnets workstream)
**Domain:** Isolated sub-networks layered under an existing libp2p/GossipSub + CRDT/GlobalDB blockchain node (SuperGenius/GeniusNode) — docs-only design milestone, v1.0
**Researched:** 2026-07-24
**Confidence:** MEDIUM-HIGH (codebase-grounded architecture/pitfalls findings are HIGH; comparative-ecosystem and stack-precedent findings are MEDIUM)

## Executive Summary

GNUS subnets are a `net_id.subnet_id` composite addressing scheme layered on top of a node that already shares one consensus family across "networks" — architecturally this makes GNUS subnets much closer to Polkadot parachains (shared validator/consensus fabric, pooled trust) than to Avalanche subnets or Cosmos IBC zones (each of which requires bridging in trust from a sovereign, independently-validated chain). The single most important research finding, corroborated independently by all four research passes, is that **`subnet_id` is not a green field**: it is already a `uint16_t` field threaded end-to-end through `sgns_config.json` → `GeniusNode` → `TransactionManager::New`, but it is currently inert ("reserved," never consumed). Every pubsub topic and CRDT keyspace path in the codebase already funnels through exactly one shared helper, `version::GetNetAndVersionAppendix()` (and its CRDT-path derivative `GetBlockChainBase()`), to append `.{net_id}` to strings. This single existing choke point is the highest-leverage design lever available: extending it to also carry `subnet_id` (defaulting to 0, producing byte-identical output to today) mechanically solves addressing, pubsub namespacing, and most of job isolation simultaneously — these are not three separate mechanisms, they are one mechanism applied at one extra call site (`processing_service.cpp`'s grid-channel topic construction already calls the same helper).

The one deliverable that is genuinely new engineering, not an extension of an existing pattern, is the bridge/gateway. SuperGenius's existing EVM bridge (`BridgeRelayer`/`eth::EthWatchService`) is the right architectural *template* (watch a burn/lock event on side A, mint on side B once verified) but cannot be reused directly — there is no EVM chain on the subnet side, so a new CRDT-native watcher component is required. The recommended trust model — reusing the CRDT-recorded-authority pattern behind `CheckCertifiedParent`/`CheckParentChildAuthority` (extend the gate to be subnet-scoped rather than inventing a federated/multisig bridge) — is architecturally cheaper and has a smaller trust surface than any public-chain bridge protocol, and directly avoids the single-signer failure mode responsible for the majority of real-world bridge hacks (Ronin, Wormhole, Nomad).

The dominant risk category, surfaced independently by the Pitfalls and Architecture research, is that several of today's "single-net" assumptions are baked in more deeply than the config-level `subnet_id` field suggests: address derivation carries no net/subnet component at all (an identical keypair produces the identical address on every net and subnet), `net_id` itself is a single process-wide global static (not a per-call parameter), CRDT key-scoping is convention-only string concatenation with no structural enforcement, and the existing certified-parent signature trapdoor (D-60) has no net/subnet-match precondition. None of these break a single-net deployment today, but each becomes a live vulnerability the moment more than one net/subnet coexists on the same keyspace or process. The design doc for every one of the four deliverables must explicitly close these gaps rather than assume the existing gates "already handle it," because none of them were built with more than one network in mind.

## Key Findings

### Recommended Stack

No new third-party libraries or transports are needed. The existing stack — libp2p GossipSub (via the `ipfs-pubsub` fork), Protocol Buffers, Boost.Asio, RocksDB-backed CRDT/GlobalDB, and the existing `TransactionManager`/`ConsensusManager` dispatch-and-gate machinery — is sufficient for all four deliverables. The "stack addition" this milestone needs is a small set of conventions (composite dotted addressing modeled on the existing `.{net_id}` appendix convention and reinforced by Polkadot's parent-relative `MultiLocation`; hierarchical CRDT key prefixing `/bc-{net}.{subnet}/`; Ethereum consensus-layer-style always-present topic segments, never conditionally omitted) plus exactly one new component category: a subnet gateway/watcher, structurally modeled on but not reusing `BridgeRelayer`.

**Core technologies (already present, no version change):**
- libp2p GossipSub (`thirdparty/libp2p` fork) — sole pubsub transport; subnet isolation is a topic-naming convention layered on top, not a protocol change
- Protocol Buffers (v5.34.0 vendored) — a subnet-registration/gateway tx is a new `oneof` case in the existing `EmbeddedTransaction` dispatch, not a new serialization stack
- CRDT/GlobalDB (RocksDB-backed) — already scoped per `/bc-{net_id}/` prefix; subnet scoping is a key-prefix extension, not a new store

**Explicitly avoid:** a second pubsub/gossip transport, a new CRDT/state-sync framework, BLS aggregate signatures (imitating Avalanche Warp purely for novelty), Merkle-proof/light-client verification (IBC-style — only justified for mutually-untrusting sovereign chains, not true here), and a new external smart-contract escrow layer (no contract-execution VM exists in this stack).

### Expected Features

GNUS subnets sit structurally between Polkadot parachains (shared consensus family, the closest analog) and Avalanche/Cosmos (sovereign, independently-validated networks requiring from-scratch trust bridging). Because GNUS subnets share the main net's own consensus family, GNUS can reuse its own authority-gate machinery for subnet trust — a materially cheaper and safer path than any public reference ecosystem had available.

**Must have (table stakes, and the milestone's four stated deliverables):**
- Globally unique, hierarchically-composed `net_id.subnet_id` addressing, with the parent net recoverable by simple parsing (not a lookup)
- Centrally-allocated (not free-form) subnet ID registry — reuses the existing `reg/` CRDT namespace + pubsub-sync pattern already proven for child-wallet registration
- PubSub topic namespacing where the composite subnet ID is a first-class topic segment (not payload-only scoping)
- Explicit node opt-in/subscription per subnet (no default cross-subnet traffic visibility)
- Subnet-aware consensus/authority checks (extend `CheckParentChildAuthority`/`CheckCertifiedParent`, don't replace them)
- Single canonical bridge/gateway per subnet↔mainnet corridor, with conservation-preserving accounting (escrow-on-main + mint-of-canonical-accounting on subnet, not a new wrapped asset)

**Should have (differentiators, worth flagging but not designing in depth this milestone):**
- Reuse of the existing consensus-gate architecture instead of a bolt-on bridge protocol — call this out explicitly in the design doc as the reason the bridge should be scoped as "extend existing gates," not "design a new bridge protocol"
- Composite addressing designed to *not preclude* future nesting (`net_id.subnet_id.subsubnet_id`), without building nesting support now

**Defer (v2+):**
- Bridge rate-limit/cap policy (ties to already-deferred POL-01) — flag as a near-term follow-on, don't design the enforcement mechanism this milestone
- Elastic/shared compute capacity across subnet boundaries — no reference ecosystem needs this; defer until a subnet is live and capacity-starvation is observed, not hypothetical
- Nested subnet addressing, subnet-to-subnet direct bridging — explicit future extension points only

**Anti-features to explicitly avoid:** per-subnet independent validator sets (Avalanche-style — multiplies audited trust surfaces for no matching benefit here); free-form/self-chosen subnet IDs (collision/squatting risk); default cross-subnet job visibility; a wrapped/derivative subnet-side token distinct from canonical GNUS; federated/multisig external bridge validators; unlimited/uncapped bridging with no rate-limit or finality-delay safety valve.

### Architecture Approach

The composite `(net_id, subnet_id)` identity should live at the single existing `sgns::version` choke point, not be threaded as a new parameter through dozens of call sites — every subnet-aware consumer (pubsub topics via `GetNetAndVersionAppendix()`, CRDT paths via `GetBlockChainBase()`, `GetMonitoredNetworkIDs()`) already funnels through this one source. `subnet_id == 0` must produce byte-identical strings to today's main-net-only build, preserving backward compatibility with zero migration for existing deployments (144/369/963). The bridge is architecturally the one exception: it is a new component (a CRDT-native two-sided watcher modeled on, but not reusing, `BridgeRelayer`), because a gateway node structurally cannot represent "watching two keyspaces simultaneously" through a single process-global identity — it needs an explicit second, non-global handle (a second `GlobalDB` instance / second pubsub topic-set), the same way `GeniusNode` already owns two side-by-side `GlobalDB` instances (`tx_globaldb_`, `job_globaldb_`) today.

**Major components:**
1. `sgns::version` (composite identity + subnet-aware `GetNetAndVersionAppendix()`/`SetNetworkId`) — the single leverage point for addressing and pubsub namespacing
2. `TransactionManager` (`GetBlockChainBase()`, `GetMonitoredNetworkIDs()`/new `GetMonitoredSubnetIDs()`, `transaction_parsers`) — subnet-aware CRDT keyspace roots and tx dispatch; reuses the existing `"mint"` tx type for the bridge-credit leg rather than inventing a new proto message
3. `Blockchain` (subnet-scoped analog of `CheckCertifiedParent`) — subnet/bridge authority gate, preserving the existing one-directional `blockchain_genesis` ← `genius_node` dependency constraint (D-63)
4. *(new)* Subnet Registry — consensus-visible CRDT record of allocated subnet IDs, replacing `SetNetworkId`'s currently-hardcoded 3-value whitelist for the subnet dimension
5. *(new)* Subnet Bridge/Gateway watcher — CRDT-native burn-watch → mint-emit, modeled on but structurally distinct from `BridgeRelayer`

### Critical Pitfalls

1. **Address derivation has no net/subnet scoping** — the identical keypair produces the identical address on every net and subnet (`GeniusAccount::GetAddress()` derives purely from the pubkey). Must be resolved explicitly in the addressing design phase: either fold `net_id.subnet_id` into address derivation, or guarantee every downstream consumer is tuple-keyed `(net_id, subnet_id, address)` instead of bare-address-keyed.
2. **CRDT keyspace namespacing is convention-only** — the `/bc-{net_id}/...` prefix is built by ad hoc `boost::format` string concatenation at each call site with no structural enforcement by the datastore itself. Fix: one mandatory shared key-building function that every subnet-aware CRDT read/write must go through.
3. **`net_id` is a process-wide global singleton** — breaks any node (specifically the gateway) that must see two nets/subnets at once. Do not attempt runtime toggling of the global; architect the gateway as either two cooperating single-net processes or a refactored net-context parameter with multiple side-by-side instances.
4. **Single gateway signer as sole trust anchor** — reusing the child-wallet certified-parent signature pattern verbatim for the bridge recreates the exact single-signer federated-bridge weakness behind the majority of real-world cross-chain losses (Ronin, Wormhole, Nomad). Require quorum/threshold certification from the source net's validator registry, not a bare relaying signature.
5. **No cross-net atomicity (double-mint risk) and no epoch-pinning** — lock/burn and mint are separate, uncoordinated CRDT commits with no shared transaction boundary; bridge certificates must carry the source registry epoch/CID and destination-side idempotency keys, or a stale-epoch or duplicate-submission mint can slip through.
6. **Cross-net reuse of the certified-parent signature trapdoor** — `CheckTransactionAuthorization`'s D-60 trapdoor has no net/subnet-match precondition today; must be explicitly re-audited and gated by "same net *and* subnet" before subnets exist, not assumed to already handle it.
7. **Unknown-tx-type silent rejection** — this exact failure already happened once in this codebase (the `"registration"` dispatch-table gap found during v2.3). Any new bridge tx type must add a `transaction_parsers` entry and a regression test as an explicit, named checklist item — not an implicit assumption.

## Implications for Roadmap

### Build-order discrepancy to flag for the roadmapper

**The milestone's stated deliverable order** (per PROJECT.md) is: **addressing → pubsub namespacing → bridge/gateway → job isolation.**

**Both the Architecture and Stack research independently recommend a different order:** **addressing → pubsub namespacing → job isolation → bridge/gateway (bridge last).** The rationale, given consistently by both research passes: job isolation is where isolation actually becomes real and testable (CRDT keyspace namespacing, `GetBlockChainBase()`/`GetMonitoredNetworkIDs()` subnet-awareness, consensus-gate subnet-scoping) — and the bridge's entire trust model depends on being able to read a *finalized, genuinely isolated* state on both sides. Designing the bridge against a subnet that isn't demonstrably isolated yet risks baking in wrong assumptions about what "the subnet's state" even means. The bridge is also the one deliverable requiring genuinely new engineering (a new component, not an extension of an existing helper), so both research passes argue it benefits from being scoped last, once the addressing/topic/keyspace vocabulary it needs to describe "lock on side A, mint on side B" already has a fixed, implemented shape.

**If the roadmap keeps the milestone's original order for scheduling reasons**, the one hard dependency that must be preserved regardless: addressing before everything, and pubsub namespacing before job isolation (since job isolation's channel-topic half *is* pubsub namespacing applied to one more call site — the processing grid channel already calls the same shared helper).

The roadmapper should make an explicit, informed call here rather than defaulting silently to either order — this is not a case where research analysis paralysis should mask a real trade-off between "matches the milestone's original framing" and "matches the dependency graph found in the code."

### Phase 1: Subnet Addressing Scheme
**Rationale:** Every other deliverable — pubsub topic strings, CRDT keyspace roots, job-isolation channel names, and the bridge's two-sided keyspace access — reads from this one identity source. Nothing else can be designed concretely until the composite ID's string/byte representation and allocation mechanism are fixed. This is also where the addressing-layer pitfalls (address derivation, replay-nonce keying) must be resolved or explicitly deferred with a documented tuple-keying invariant.
**Delivers:** `net_id.subnet_id` composition scheme, `config_json` placement (already exists, document the scheme not a new location), Subnet Registry design (CRDT-backed allocation, replacing `SetNetworkId`'s hardcoded whitelist for the subnet dimension), and an explicit design decision on whether address derivation itself must fold in `net_id.subnet_id` or whether uniqueness is enforced structurally elsewhere.
**Addresses:** Globally unique hierarchical addressing, centrally-allocated subnet ID registry (both table stakes from FEATURES.md).
**Avoids:** Pitfall 1 (address collision across nets/subnets) and Pitfall 8 (replay-nonce keyed by bare address) — both must be explicitly resolved or the invariant documented, not silently inherited.

### Phase 2: PubSub Channel Namespacing
**Rationale:** The cheapest, most mechanical follow-on — extending the single existing `GetNetAndVersionAppendix()` helper to also carry `subnet_id` (default 0, byte-identical to today) retroactively namespaces every existing topic call site (`AccountMessenger`, `Consensus`, `processing_service`, `pubsub_broadcaster_ext`) for free. It is also a hard prerequisite for job isolation, since the processing grid channel topic is just one more caller of this same function.
**Delivers:** Subnet-aware topic-naming scheme, an explicit checklist of every existing hardcoded topic literal/migration-file constant that must be converted (Pitfall 4 — this codebase's `GNUS_FULL_NODES_TOPIC`/`_LEGACY` constants are compile-time strings, not computed), and application-level topic-subscription filtering guidance (topic names are routing hints only, not security boundaries).
**Uses:** `version::GetNetAndVersionAppendix()` (STACK.md), Ethereum consensus-layer fork-digest-style always-present subnet segment convention.
**Implements:** `sgns::version` composite identity extension (ARCHITECTURE.md Component 1).

### Phase 3: Job Isolation & Consensus Impact
**Rationale:** (See build-order discrepancy above — this phase's position relative to the bridge is the one open question for the roadmapper.) Job isolation is where isolation becomes demonstrably real: subnet-scoped CRDT keyspace roots, `GetMonitoredNetworkIDs()`'s subnet-aware sibling, and — critically — re-auditing the existing consensus authority gates for a net/subnet-match precondition they were never designed to reason about.
**Delivers:** Subnet-scoped `GetBlockChainBase()`/CRDT keyspace design (`/bc-{net}.{subnet}/`), subnet-scoped job/processing channel design (mechanically the same as Phase 2's topic work applied to `processing_service.cpp`), and an explicit re-audit of `CheckParentChildAuthority`/`CheckCertifiedParent`/`CheckTransactionAuthorization`'s D-60 trapdoor for missing net/subnet-match preconditions.
**Addresses:** Subnet-scoped job scheduling, CRDT/registration/validation-gate subnet-awareness (both named explicitly in the milestone's deliverable list).
**Avoids:** Pitfall 2 (convention-only CRDT namespacing — introduce the shared key-building function here), Pitfall 10 (cross-net reuse of the certified-parent trapdoor — this is exactly the "validation-gate subnet-awareness" deliverable).

### Phase 4: Bridge/Gateway Design
**Rationale:** The one genuinely new component in this milestone, and the one whose trust model structurally depends on the other three phases already being settled (a finality/isolation guarantee to bridge *from* has to exist before you can design what "verify the other side's state" means). Also the highest-risk deliverable from a security-pitfalls standpoint — five of the ten cataloged pitfalls map here.
**Delivers:** CRDT-native gateway/watcher component design (modeled on, not reusing, `BridgeRelayer`), a `CheckSubnetGatewayAuthority`-style consensus gate extending `CheckCertifiedParent`'s CRDT-derived-authority pattern (explicitly NOT a single-signer/federated model), an explicit gateway process-architecture decision (two cooperating single-net processes vs. a refactored net-context parameter, given `net_id`'s process-global-singleton constraint), epoch-pinning and mint-idempotency requirements, and a documented rate-limit/cap policy hook (even if not implemented this docs-only milestone). Also delivers: single canonical gateway/bridge design, conservation-preserving accounting (escrow-on-main + mint-of-canonical-accounting on subnet).

### Phase Ordering Rationale

- Addressing must come first because it's the sole identity source every other phase reads from — this is not a preference, it's a hard dependency confirmed independently by all four research files.
- PubSub namespacing before job isolation is a hard dependency because job isolation's channel-topic half literally is pubsub namespacing applied to one more call site.
- Job isolation before the bridge (Architecture/Stack recommendation) vs. bridge before job isolation (milestone's stated order) is the one real disagreement — surfaced above for the roadmapper's explicit call, not resolved here.
- The bridge is scoped last regardless of the final decision on the above, in terms of *design maturity required*: it is the only deliverable needing a genuinely new component, and it has the highest concentration of security-critical pitfalls (5 of 10), so it benefits from the addressing/topic/keyspace vocabulary being fixed before its trust model is finalized.

### Research Flags

Phases likely needing deeper research during planning:
- **Bridge/Gateway phase:** Genuinely novel component with no direct in-repo precedent to copy line-for-line (only a structural template, `BridgeRelayer`, that doesn't transfer as-is); the trust-model, epoch-pinning, and idempotency design choices have real security consequences and only MEDIUM-confidence industry corroboration (bridge-hack postmortems, not GNUS-specific precedent).
- **Job Isolation & Consensus phase:** The consensus-gate re-audit (Pitfall 10) requires careful, source-grounded analysis of `CheckTransactionAuthorization`'s exact trapdoor conditions — worth a dedicated research pass during planning to enumerate every call site precisely against current HEAD (all pitfalls research is time-stamped against the `dev_childwallet` branch and explicitly flagged "verify against HEAD before design-doc finalization").

Phases with standard, well-documented patterns (can likely skip a dedicated research-phase pass):
- **Subnet Addressing Scheme:** The composite-ID convention (dotted decimal, existing `.{net_id}` appendix pattern) and registry pattern (reuse of the proven `reg/` CRDT namespace + pubsub-sync mechanism) are both already fully precedented in-repo.
- **PubSub Channel Namespacing:** Purely mechanical extension of one existing, well-understood shared helper function; the checklist of call sites to convert is already enumerated in ARCHITECTURE.md/PITFALLS.md.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | No new libraries needed (HIGH confidence, read directly from source/submodule pins); the comparative-precedent reasoning (Polkadot/Avalanche/Cosmos/Ethereum patterns) is MEDIUM — cross-checked web sources, not GNUS-specific validation |
| Features | HIGH (addressing/bridge) / MEDIUM (job isolation) | Addressing and bridge patterns corroborated across multiple independent public ecosystems; GNUS's job-processing model (a compute marketplace, not just tx/block processing) has no directly comparable public reference, so job-isolation-specific feature framing is more inferential |
| Architecture | HIGH | Grounded directly in current SuperGenius source (`GeniusNode`, `TransactionManager`, `sgns_version`, `BridgeRelayer`, `Blockchain`, `processing_service`) — not external documentation |
| Pitfalls | HIGH (codebase-grounded findings) / MEDIUM (cross-net bridge-attack literature) | Address/CRDT/global-singleton/dispatch-table pitfalls read directly from source, including one pitfall (dispatch-table gap) that already happened once in this exact codebase; bridge-attack-pattern corroboration (Ronin/Wormhole/Nomad) is secondary-source industry analysis, though incident facts themselves are highly cross-corroborated |

**Overall confidence:** MEDIUM-HIGH — the codebase-grounded findings (what exists today, where the seams are, what pitfalls are structurally baked in) are uniformly HIGH confidence since all four researchers read the actual source tree directly. The comparative-ecosystem precedent reasoning and the specific bridge-security recommendations are MEDIUM confidence, appropriately so for a docs-only design milestone that should be validated against deeper research during the bridge/gateway planning phase specifically.

### Gaps to Address

- **Build-order discrepancy (addressing → pubsub → bridge → job-isolation vs. addressing → pubsub → job-isolation → bridge):** Not a research gap so much as a decision the roadmapper must make explicitly — see "Implications for Roadmap" above. Both orderings are internally consistent; they differ on whether "isolation-first" or "milestone's stated deliverable order" should take precedence.
- **Whether address derivation itself needs to change (Pitfall 1) vs. whether tuple-keying downstream is sufficient:** This is a genuinely open design fork that the addressing-phase design doc must resolve explicitly and document as an invariant, not something research alone can settle — it has real implications for every other phase (bridge, job isolation, replay protection) that this research surfaces but does not close.
- **Gateway process architecture (single refactored process vs. two cooperating single-net processes), forced by `net_id`'s process-global-singleton constraint:** Flagged as a hard architectural decision for the bridge/gateway phase; research documents the constraint and both options but does not recommend one over the other, since the choice depends on operational/deployment factors outside this research's scope.
- **Verify all pitfalls/architecture line/file references against current HEAD before design-doc finalization** — the pitfalls research explicitly notes findings are anchored to the `dev_childwallet` branch post-v2.4-merge and may drift.

## Sources

### Primary (HIGH confidence)
- SuperGenius source tree, direct inspection: `src/base/sgns_version.hpp/cpp`, `src/account/GeniusNode.hpp/cpp`, `src/account/TransactionManager.hpp/cpp`, `src/blockchain/Consensus.hpp`, `src/blockchain/impl/Blockchain.cpp`, `src/account/BridgeRelayer.hpp/cpp`, `src/watcher/impl/bridge_catchup_watcher.hpp`, `src/account/bridge_chains_config.json`, `src/crdt/globaldb/globaldb.hpp/cpp`, `src/processing/processing_service.cpp`, `src/account/GeniusAccount.cpp`, `src/blockchain/ValidatorRegistry.cpp/hpp`, `src/account/RevokeTransaction.hpp`
- `thirdparty/` submodule commit pins (`ipfs-pubsub`, `libp2p`, `boost` 1.85.0, `protobuf` v5.34.0, `rocksdb`) via `git submodule status`/`git log`
- `.planning/PROJECT.md` — workstream goal, historical registration-dispatch-table gap (v2.3), D-60/D-63 key decisions

### Secondary (MEDIUM confidence)
- Avalanche Builder Hub / ACP-77 / ICTT overview and GitHub repo (subnet/Warp/ICTT architecture)
- Polkadot Developer Docs / Wiki (relay chain, parachains, XCM transport)
- Cosmos IBC-Go docs / Interchain Developer Academy / ICS-20 spec (light client, escrow+voucher pattern)
- Ethereum.org bridges docs, ERC-7281/ERC-7802 (canonical bridge, cross-chain token fungibility)
- `ethereum/consensus-specs` p2p-interface.md (GossipSub subnet topic suffixing — direct protocol-identical precedent, same GossipSub substrate)
- Bridge hack postmortem synthesis (Ronin, Wormhole, Nomad) via DEV Community and yellow.com summaries
- ACM DLT Research and Practice, ImmuneBytes, ScienceDirect (cross-chain bridge attack patterns, double-spend analysis)
- libp2p gossipsub spec (github.com/libp2p/specs)

### Tertiary (LOW confidence)
- None flagged — all sources used were either primary (repo) or cross-checked secondary sources with multiple corroborating references.

---
*Research completed: 2026-07-24*
*Ready for roadmap: yes*
