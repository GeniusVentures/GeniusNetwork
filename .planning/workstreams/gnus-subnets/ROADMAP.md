# Roadmap: GNUS Subnets (v1.0 GNUS Subnets Architecture)

## Overview

This is a docs-only milestone. Every phase below delivers a design document, not code — there is no implementation, no proto/CRDT/consensus change, and no test suite in this roadmap. The four phases resolve the milestone's four stated deliverables (addressing, pubsub namespacing, job isolation/consensus impact, bridge/gateway) in the dependency order confirmed by research: **addressing → pubsub namespacing → job isolation → bridge/gateway**. This order was an explicit call the roadmapper made on the user's behalf, already reflected in the phase sequence below — it resolves the build-order discrepancy research/SUMMARY.md flagged (the milestone's originally-stated order put the bridge before job isolation; the dependency graph found in the code argues job isolation should settle first, since the bridge's trust model depends on a demonstrably isolated subnet state to bridge *from*).

Everything downstream of Phase 1 reads from the composite `net_id.subnet_id` identity it fixes. Phase 2 is a mechanical extension of one existing shared helper. Phase 3 is where isolation becomes structurally real (CRDT keyspace, consensus-gate re-audit). Phase 4 is the one genuinely new component, scoped last so its trust model can build on settled addressing/topic/keyspace vocabulary.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): Planned milestone work, numbered independently of any other workstream
- This is the first milestone for the gnus-subnets workstream — numbering starts at Phase 1

- [ ] **Phase 1: Subnet Addressing Scheme** - Design doc fixes the `net_id.subnet_id` composite identity, its allocation/registry mechanism, and resolves the address-derivation scoping question
- [ ] **Phase 2: PubSub Channel Namespacing** - Design doc extends the existing topic-naming helper to carry `subnet_id`, enumerates every call site needing conversion, and specifies per-subnet opt-in
- [ ] **Phase 3: Job Isolation & Consensus Impact** - Design doc specifies subnet-scoped CRDT keyspace and job/processing channel design, and re-audits the consensus authority gates for net/subnet-match preconditions
- [ ] **Phase 4: Bridge/Gateway Design** - Design doc specifies the CRDT-native gateway/watcher, its subnet-scoped consensus gate, process architecture, and a rate-limit placeholder hook

## Phase Details

### Phase 1: Subnet Addressing Scheme
**Goal**: A design doc exists that fixes the `net_id.subnet_id` composite addressing scheme as the single identity source every other phase reads from, including its allocation mechanism and an explicit resolution of whether address derivation itself must change.
**Depends on**: Nothing (first phase)
**Requirements**: ADDR-01, ADDR-02, ADDR-03
**Success Criteria** (what must be TRUE):
  1. Design doc specifies the exact `net_id.subnet_id` composite format (e.g. dotted-decimal string/byte representation), `config_json` field placement, and validation rules (range bounds, parent-net recoverability by parsing, collision prevention) — precise enough to implement without further interpretation.
  2. Design doc specifies the subnet ID allocation/registry mechanism, naming the exact CRDT namespace and pubsub-sync pattern it reuses (mirroring the proven `reg/` namespace + broadcast pattern from child-wallet registration) and how it replaces `SetNetworkId`'s current hardcoded 3-value whitelist for the subnet dimension.
  3. Design doc explicitly resolves the address-derivation open question (Pitfall 1: `GeniusAccount::GetAddress()` derives purely from pubkey today, identical across every net/subnet) — either specifying how `net_id.subnet_id` folds into derivation, or documenting the tuple-keying `(net_id, subnet_id, address)` invariant every downstream consumer must follow instead. No silent inheritance of the ambiguity is acceptable.
  4. Design doc names concrete SuperGenius anchor points the scheme touches (e.g. `GeniusAccount::GetAddress`, `SetNetworkId`, `sgns_config.json`'s existing `subnet_id` field), so downstream phases and implementers have a fixed vocabulary to build on.
**Plans**: TBD

### Phase 2: PubSub Channel Namespacing
**Goal**: A design doc exists specifying how `subnet_id` becomes a first-class topic segment across every existing pubsub call site, with default (`subnet_id == 0`) behavior byte-identical to today.
**Depends on**: Phase 1
**Requirements**: PUBSUB-01, PUBSUB-02, PUBSUB-03
**Success Criteria** (what must be TRUE):
  1. Design doc specifies the exact extension to the existing `GetNetAndVersionAppendix()` (and its CRDT-path derivative `GetBlockChainBase()`) that folds `subnet_id` into topic/path strings, with the explicit invariant that `subnet_id == 0` produces output identical to current main-net-only builds (144/369/963 need zero migration).
  2. Design doc enumerates every existing hardcoded topic literal/constant requiring conversion to subnet-aware naming (e.g. `GNUS_FULL_NODES_TOPIC`/`_LEGACY` and other compile-time string constants), each with its call-site file reference, so no conversion site is discovered later by surprise.
  3. Design doc specifies node opt-in/subscription behavior per subnet, guaranteeing no default cross-subnet traffic visibility (a node must explicitly subscribe to see a subnet's traffic).
  4. Design doc states explicitly that topic names are routing hints only, not a security boundary, and cross-references Phase 3's consensus-gate work as the actual enforcement point for subnet isolation.
**Plans**: TBD

### Phase 3: Job Isolation & Consensus Impact
**Goal**: A design doc exists specifying the subnet-scoped CRDT keyspace and job/processing channel design, and re-audits every existing consensus authority gate for missing net/subnet-match preconditions.
**Depends on**: Phase 2
**Requirements**: JOBC-01, JOBC-02, JOBC-03
**Success Criteria** (what must be TRUE):
  1. Design doc names the exact mandatory shared key-building function that replaces today's ad hoc `boost::format` string concatenation for CRDT keyspace paths, and enumerates every existing call site it replaces (e.g. `GetBlockChainBase()`'s `/bc-{net_id}/` prefix becoming `/bc-{net_id}.{subnet_id}/`, `reg/`, `tx/`, `job/` paths).
  2. Design doc specifies the subnet-scoped job/processing channel design, applying Phase 2's namespacing pattern to `processing_service.cpp`'s grid-channel topic construction as the one remaining call site.
  3. Design doc re-audits `CheckParentChildAuthority`, `CheckCertifiedParent`, and `CheckTransactionAuthorization`'s D-60 certified-main signature trapdoor line-by-line against current HEAD, and specifies the exact net/subnet-match precondition each must add before subnets can coexist safely.
  4. Design doc documents a subnet-aware sibling to `GetMonitoredNetworkIDs()` (e.g. `GetMonitoredSubnetIDs()`) and how `TransactionManager`'s dispatch consumes it for subnet-scoped job/tx routing.
**Plans**: TBD

### Phase 4: Bridge/Gateway Design
**Goal**: A design doc exists specifying the CRDT-native gateway/watcher component, its subnet-scoped consensus gate, its process architecture, and a placeholder rate-limit hook — the one genuinely new component this milestone designs, built on the settled addressing/topic/keyspace vocabulary from Phases 1-3.
**Depends on**: Phase 3
**Requirements**: BRDG-01, BRDG-02, BRDG-03, BRDG-04
**Success Criteria** (what must be TRUE):
  1. Design doc specifies the CRDT-native gateway/watcher component (burn-watch → mint-emit), explicitly modeled on but structurally distinct from `BridgeRelayer`, naming the two side-by-side handles it must own (a second `GlobalDB` instance / second pubsub topic-set, the same pattern `GeniusNode` already uses for `tx_globaldb_`/`job_globaldb_`) to work around `net_id`'s process-global-singleton constraint.
  2. Design doc specifies a subnet-scoped consensus gate (e.g. `CheckSubnetGatewayAuthority`) extending the CRDT-derived-authority pattern behind `CheckCertifiedParent`, explicitly rejecting a federated/multisig external-validator model and stating why (avoids the single-signer failure mode behind Ronin/Wormhole/Nomad).
  3. Design doc resolves the gateway process-architecture decision (two cooperating single-net processes vs. a refactored net-context parameter with multiple side-by-side instances) and specifies epoch-pinning + destination-side idempotency-key requirements that close the double-mint risk (no shared transaction boundary exists between the lock/burn commit and the mint commit today).
  4. Design doc documents a rate-limit/cap policy hook as a placeholder only — an interface/config surface named and positioned in the design, explicitly deferred for enforcement to a future milestone (ties to already-deferred POL-01/SUBX-04), not implemented this milestone.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|-----------------|--------|-----------|
| 1. Subnet Addressing Scheme | 0/TBD | Not started | - |
| 2. PubSub Channel Namespacing | 0/TBD | Not started | - |
| 3. Job Isolation & Consensus Impact | 0/TBD | Not started | - |
| 4. Bridge/Gateway Design | 0/TBD | Not started | - |
