# Requirements: GNUS Subnets

**Defined:** 2026-07-24
**Core Value:** Produce design documentation defining how isolated GNUS subnets (`net_id.subnet_id`, e.g. `144.100` under main net `144`) address, communicate, bridge tokens, and isolate job/consensus processing — no implementation this milestone.

## v1 Requirements

Requirements for the v1.0 milestone (docs-only). Each maps to one design-doc roadmap phase.

### Subnet Addressing Scheme

- [ ] **ADDR-01**: Design doc specifies `net_id.subnet_id` composite addressing format, `config_json` placement, and validation rules
- [ ] **ADDR-02**: Design doc specifies subnet ID allocation/registry mechanism (reusing the `reg/` CRDT namespace + pubsub-sync pattern)
- [ ] **ADDR-03**: Design doc resolves whether address derivation itself must fold in `net_id.subnet_id`, or documents the tuple-keying invariant if not

### PubSub Channel Namespacing

- [ ] **PUBSUB-01**: Design doc specifies how `subnet_id` extends the existing `GetNetAndVersionAppendix()` topic-naming scheme
- [ ] **PUBSUB-02**: Design doc enumerates every existing hardcoded topic literal/constant requiring conversion to subnet-aware naming
- [ ] **PUBSUB-03**: Design doc specifies node opt-in/subscription behavior per subnet (no default cross-subnet traffic visibility)

### Job Isolation & Consensus Impact

- [ ] **JOBC-01**: Design doc specifies subnet-scoped CRDT keyspace design (a mandatory shared key-building function, replacing ad hoc string concatenation)
- [ ] **JOBC-02**: Design doc specifies subnet-scoped job/processing channel design
- [ ] **JOBC-03**: Design doc re-audits `CheckParentChildAuthority`/`CheckCertifiedParent`/D-60 trapdoor for missing net/subnet-match preconditions

### Bridge/Gateway Design

- [ ] **BRDG-01**: Design doc specifies the CRDT-native gateway/watcher component (burn-watch → mint-emit), modeled on but distinct from `BridgeRelayer`
- [ ] **BRDG-02**: Design doc specifies a subnet-scoped consensus gate extending the CRDT-derived-authority pattern (not a federated/multisig model)
- [ ] **BRDG-03**: Design doc specifies the gateway process-architecture decision (given `net_id`'s global-singleton constraint) and epoch-pinning/idempotency requirements for mint safety
- [ ] **BRDG-04**: Design doc documents a rate-limit/cap policy hook (placeholder only — not implemented this milestone)

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Subnet Extensions

- **SUBX-01**: Elastic/shared compute capacity across subnet boundaries
- **SUBX-02**: Nested subnet addressing (`net.subnet.subsubnet`)
- **SUBX-03**: Subnet-to-subnet direct bridging (bypassing main net)
- **SUBX-04**: Bridge rate-limit/cap enforcement implementation (ties to existing deferred POL-01)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Any code implementation | This milestone is docs-only — design documents, no proto/CRDT/consensus code changes |
| New third-party libraries/transports | Research confirms the existing libp2p/CRDT/Protobuf/Boost stack is sufficient for all four deliverables |
| BLS aggregate signatures / Merkle-proof light-client verification | Only justified for mutually-untrusting sovereign chains (Avalanche/Cosmos-style); GNUS subnets share the main net's own consensus family |
| Federated/multisig external bridge validators | Recreates the single-signer failure mode behind most real-world bridge hacks (Ronin, Wormhole, Nomad); CRDT-derived authority is cheaper and safer here |
| Wrapped/derivative subnet-side token distinct from canonical GNUS | Conservation-preserving escrow+mint accounting keeps one canonical token, not a new wrapped asset |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ADDR-01 | TBD | Pending |
| ADDR-02 | TBD | Pending |
| ADDR-03 | TBD | Pending |
| PUBSUB-01 | TBD | Pending |
| PUBSUB-02 | TBD | Pending |
| PUBSUB-03 | TBD | Pending |
| JOBC-01 | TBD | Pending |
| JOBC-02 | TBD | Pending |
| JOBC-03 | TBD | Pending |
| BRDG-01 | TBD | Pending |
| BRDG-02 | TBD | Pending |
| BRDG-03 | TBD | Pending |
| BRDG-04 | TBD | Pending |

**Coverage:**
- v1 requirements: 13 total
- Mapped to phases: 0 (pending roadmap creation)
- Unmapped: 13 ⚠️

---
*Requirements defined: 2026-07-24*
*Last updated: 2026-07-24 after initial definition*
