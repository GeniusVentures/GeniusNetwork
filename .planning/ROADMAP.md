# Roadmap: GNUS Child Wallet Design

**Created:** 2026-07-13
**Granularity:** Coarse (3 phases)
**Project Mode:** Vertical MVP

## Overview

This milestone produces implementation-ready design documents for child wallets in the GNUS SuperGenius node. The journey moves from the foundational child-wallet identity and registration protocol (Phase 1), through the consensus-visible CRDT/pubsub persistence and the parent-child authority rules that make the model secure (Phase 2), to the main-wallet discovery, reward policy, and lifecycle/change flows that complete the experience (Phase 3). Each phase delivers reviewable design documents grounded in named SuperGenius anchor points, ordered by dependency so every later document builds on a defined earlier one.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Child Identity & Registration Protocol** - Design the independent child-wallet identity and the child-signed registration record + proto schema (REG-02 dual-signature reversed per D-04/D-05)
- [ ] **Phase 2: CRDT Persistence, PubSub & Consensus Authority** - Design consensus-visible registration storage, broadcast/sync, and the parent-child authority rules
- [ ] **Phase 3: Discovery, Rewards & Lifecycle** - Design main-wallet discovery/monitoring, per-child reward policy, and lifecycle/change flows

## Phase Details

### Phase 1: Child Identity & Registration Protocol

**Goal**: Produce design documents defining the child-wallet identity model and the child-signed registration protocol with additive, backward-compatible proto schema changes (REG-02 dual-signature REVERSED by D-04/D-05 — registration is child-signed-only).
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: IDENT-01, IDENT-02, IDENT-03, IDENT-04, REG-01, REG-02, REG-03, REG-04, REG-05
**Success Criteria** (what must be TRUE):

  1. A design document specifies the child-wallet identity model (independent secp256k1 keypair, own nonce, standalone creation, UTXO ownership) with named `GeniusAccount`/`GeniusNode`/`GeniusUTXO` anchor points, traceable to IDENT-01..04.
  2. A design document specifies the registration record schema and child-signed-only protocol (child signature only; REG-02 dual-signature REVERSED per D-04/D-05), traceable to REG-01, REG-02.
  3. A design document specifies additive Protocol Buffer changes to `SGTransaction.proto` with a backward-compatibility matrix, traceable to REG-03.
  4. The design specifies the out-of-process main-signing flow and monotonic per-child sequence numbering for replay protection, traceable to REG-04, REG-05.

**Plans**: 2 plans
Plans:

- [ ] 01-01-PLAN.md — Child-wallet identity & keypair model design (IDENT-01..04)
- [ ] 01-02-PLAN.md — Registration record schema + child-signed-only protocol + proto changes (REG-01..05; REG-02 REVERSED)

### Phase 2: CRDT Persistence, PubSub & Consensus Authority

**Goal**: Produce design documents for persisting the registration record in consensus-visible CRDT state, broadcasting/subscribing over pubsub, and enforcing all parent-child authority rules.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05, CONS-01, CONS-02, CONS-03, CONS-04, CONS-05, CONS-06
**Success Criteria** (what must be TRUE):

  1. A design document specifies the CRDT registry namespace/key layout and validating element filter in `globaldb`/`TransactionManager`, traceable to SYNC-01, SYNC-02.
  2. A design document specifies registration broadcast on the main's pubsub channel and the main subscribing to child channel(s) for CRDT balance sync via `PubSubBroadcasterExt`, with authority derived only from signatures+consensus (not topic membership), traceable to SYNC-03, SYNC-04, SYNC-05.
  3. A design document specifies all six consensus authority rules — main→child fund, destination-restricted recovery, child→arbitrary/main, child→developer, and the explicit child-cannot-spend-main rejection — mapped to `ValidateTransactionForConsensus`/`GeniusInputValidator`/`CheckTransactionAuthorization`, traceable to CONS-01..06.
  4. The design explicitly resolves the CRDT eventual-consistency vs consensus-ordering tension (seq + consensus order) and separates delegated authority from UTXO ownership checks.

**Plans**: TBD

Plans:

- [ ] 02-01: CRDT registry namespace + pubsub broadcast/subscription design
- [ ] 02-02: Consensus parent-child authority rules design

### Phase 3: Discovery, Rewards & Lifecycle

**Goal**: Produce design documents for main-wallet discovery/monitoring, per-child processing-reward policy, and the lifecycle/change flows with replay-safe conflict resolution.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: DISC-01, DISC-02, DISC-03, RWD-01, RWD-02, RWD-03, LIFE-01, LIFE-02, LIFE-03, LIFE-04
**Success Criteria** (what must be TRUE):

  1. A design document specifies how a main wallet discovers registered children and the per-child information it displays and actions it can take (fund, recover, inspect, revoke/detach), traceable to DISC-01..03.
  2. A design document specifies per-child reward policy resolution for standalone and registered children, hold-time policy pinning, and authenticated dev-wallet/split updates, reusing escrow `HoldEscrow`/`PayEscrow`, traceable to RWD-01..03.
  3. A design document specifies the lifecycle state machine and replace/remove/detach flows with "supersedes seq N" linkage and deterministic conflict resolution, traceable to LIFE-01, LIFE-02, LIFE-04.
  4. The main-replacement policy fork (require existing-main consent vs child-only) is decided and documented with rationale, traceable to LIFE-03.

**Plans**: TBD

Plans:

- [ ] 03-01: Discovery & monitoring design
- [ ] 03-02: Reward policy + lifecycle/change-flow design

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Child Identity & Registration Protocol | 0/2 | Not started | - |
| 2. CRDT Persistence, PubSub & Consensus Authority | 0/2 | Not started | - |
| 3. Discovery, Rewards & Lifecycle | 0/2 | Not started | - |
