# Roadmap: GNUS Child Wallet Design

## Milestones

- ✅ **v1.0 Child Wallet Design** — Phases 1-3 (shipped 2026-07-15)
- 🚧 **v2.0 Registration Implementation** — Phases 4-5 (in progress)

## Phases

<details>
<summary>✅ v1.0 Child Wallet Design (Phases 1-3) — SHIPPED 2026-07-15</summary>

- [x] Phase 1: Child Identity & Registration Protocol (2/2 plans) — completed 2026-07-13
- [x] Phase 2: CRDT Persistence, PubSub & Consensus Authority (2/2 plans) — completed 2026-07-14
- [x] Phase 3: Discovery, Rewards & Lifecycle (2/2 plans) — completed 2026-07-14

Full detail archived at `.planning/milestones/v1.0-ROADMAP.md`.
Phase execution history archived at `.planning/milestones/v1.0-phases/`.

</details>

### 🚧 v2.0 Registration Implementation (In Progress)

- [x] **Phase 4: Registration Proto & Transaction** — Proto schema additions, RegistrationTransaction C++ subclass, child-signed submission path
- [x] **Phase 5: CRDT Persistence, PubSub & Integration Test** — FilterRegistration + reg/ namespace, pubsub broadcast, main discovery read path, multi-node integration test (completed 2026-07-16)

## Phase Details

### Phase 4: Registration Proto & Transaction

**Goal:** The SuperGenius node builds with the new RegistrationTx proto and C++ subclass, and a child wallet can construct, sign, and submit a registration through the existing TransactionManager path.
**Mode:** mvp
**Depends on:** Nothing (first phase of v2.0)
**Requirements:** RIMPL-01, RIMPL-02, RIMPL-03
**Success Criteria** (what must be TRUE):

  1. `SGTransaction.proto` compiles with additive `RegistrationTx` + `RegistrationMetadata` messages, and `Consensus.proto` compiles with the `registration = 8` oneof arm in `EmbeddedTransaction` — existing SuperGenius transfers/mints/escrows continue to serialize, deserialize, and validate identically to pre-change builds on all supported platforms (Windows, Linux, macOS).
  2. `RegistrationTransaction` C++ subclass compiles and links: `New()` factory constructs and `FillHash`-es a valid tx; `SerializeToEmbeddedTransaction`/`SerializeByteVector` produce correct protobuf bytes; static `DeSerializeByteVector` round-trips the bytes back to an equivalent `RegistrationTransaction`; deserializer registration (`"registration"`, `&RegistrationTransaction::DeSerializeByteVector`) is called at static-init and `case EmbeddedTransaction::kRegistration` dispatches in `TransactionManager::DeSerializeEmbeddedTransaction`.
  3. A child wallet creates a `RegistrationTransaction` via the `New()` factory, signs it child-only via `MakeSignature(*child_account)`, and submits through `TransactionManager::SendTransactionItem` — the submission consumes a `DAGStruct.nonce` from the child's `GeniusAccount`, carries a monotonic per-child `sequence`, and the `TransactionManager` nonce validation and `CheckSignature` pass (observable via a GTest unit test asserting `SENDING` status and valid `DAGStruct` fields).

**Plans:** 2/2 plans complete

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 04-02-PLAN.md — TransactionManager Integration & End-to-End Submission: deserializer dispatch (kRegistration case), RegisterChild API + GeniusNode wrapper, SendTransactionItem reg/ path diversion, minimal FilterRegistration (gates a-c per D-44), end-to-end GTest proving child creates/signs/submits → SENDING status

---

### Phase 5: CRDT Persistence, PubSub & Integration Test

**Goal:** Accepted registrations persist in consensus-visible CRDT `reg/` state with a validating element filter, broadcast on the main wallet's pubsub channel, and discoverable by the main node — proven correct by a multi-node GTest integration test.
**Mode:** mvp
**Depends on:** Phase 4
**Requirements:** RIMPL-04, RIMPL-05, RIMPL-06, RIMPL-07, TEST-01, TEST-02, TEST-03, TEST-04
**Success Criteria** (what must be TRUE):

  1. `FilterRegistration` is registered on the `reg/` CRDT pattern in `TransactionManager::New()` (parallel to existing `tx/` and `proof/` filters) and validates incoming `reg/` deltas through four gates: deserialization, child signature, sequence monotonicity vs existing `reg/{child_addr}` record, and well-formed checks (`main_address` is valid 128-hex pubkey, `sequence > 0`). Valid `RegistrationTx` elements are accepted (`std::nullopt`); bad signatures, malformed `main_address`, and non-monotonic or zero `sequence` are rejected with tombstone.
  2. An accepted `RegistrationTx` persists as a single CRDT element at key `/bc-{net}/reg/{child_addr}` (full protobuf value) and the child's `SendTransactionItem` flow includes `main_address` in the pubsub topic set — the main node receives a CID notification on its address topic via `PubSubBroadcasterExt` and resolves the full `RegistrationTx` from its local CRDT.
  3. A main node enumerates and reads the child registrations naming it via a CRDT `reg/` scan or direct key lookup — returning child address, main address, sequence, and metadata for each discovered registration (RIMPL-06 read path, observable via an `EXPECT_TRUE` on a `GetRegistrationsForMain(main_addr)` helper in the integration test).
  4. Multi-node GTest integration test (`SuperGenius/test/src/multiaccount/regtest/child_registration.cpp`, following the `multi_account_sync.cpp` `CreateNode` pattern: genesis-authorized node A + peer node B on an isolated network) asserts that (a) node B's `RegistrationTx` naming node A as main is accepted and processed (TEST-02), (b) the registration propagates via CRDT/pubsub and node A discovers node B as its registered child with correct addresses/sequence (TEST-03), and (c) invalid registrations — tampered child signature, malformed `main_address`, and replayed or non-monotonic `sequence` — are rejected by `FilterRegistration` and never appear in node A's discovery view (TEST-04).

**Plans:** 3/4 plans complete

**Wave 1** *(no dependencies)*

- [x] 05-01-PLAN.md — FilterRegistration Gate (d) + RegisterChild Auto-Derive: complete FilterRegistration with sequence monotonicity gate (d) + sequence > 0 check, RegisterChild 2-arg auto-derive overload delegating to 3-arg, fix Phase 4 advisory warnings (unchecked dynamic_pointer_cast + silent SerializeByteVector) in SendTransactionItem

**Wave 2** *(depends on Wave 1)*

- [x] 05-02-PLAN.md — Discovery Read Path + PubSub CID Handler: RegistrationDiscoveryEntry struct + GetRegistrationsForMain CRDT scan, GeniusNode wrappers, CID notification handler (reg/ NewElementCallback → AddListenTopic follow)

**Wave 3** *(depends on Waves 1-2)*

- [x] 05-03-PLAN.md — Multi-Node Integration Test: 3-node fixture (genesis + main A + child B), positive test cases (TEST-02 register + TEST-03 discover), negative test cases (TEST-04 tampered signature / malformed main_address / non-monotonic sequence rejected)

**Wave 4** *(gap closure — depends on Waves 1-3)*

- [ ] 05-04-PLAN.md — Gap Closure: Compile Blockers + Signature Test Hardening: add `friend class RegTestAccess;` (CR-01) and `friend class ChildRegistrationIntegrationTest;` (CR-02) friend declarations, replace flaky byte-offset signature tampering with deterministic proto-level DAG signature tampering (WR-02/WR-03), build-and-run verification checkpoint

> **Test scaffold reference:** The integration test harness follows `SuperGenius/test/src/multiaccount/multi_account_sync.cpp`. Key patterns: `CreateNode(self_addr, dev_addr, token, id, /*isFullNode*/false, /*isProcessor*/false, /*isGenesisAuthorized*/true)` for the genesis node, `CreateNode(self_addr, dev_addr, token, id)` for peer nodes; `WaitForNodeSync(node, timeout)` for CRDT ready-state; test directories isolated via `FILE_PREFIX`-based `boost::dll::program_location()` subdirectories. Registration tests add `RegistrationTransaction::New()` + `MakeSignature` + `SendTransactionItem` onto the existing scaffold.

> **Out of scope for v2.0:** Consensus authority rules (CONS-01..06 `CheckParentChildAuthority` gate) — designed in v1.0 Phase 2, implementation deferred to a later milestone. RegistrationTx flows through full consensus (`sgns.nonce.v1` subject, `OnConsensusCertificate` → CONFIRMED) but the parent-child authority gate is NOT installed in `ValidateTransactionForConsensus` in this milestone.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Child Identity & Registration Protocol | v1.0 | 2/2 | Complete | 2026-07-13 |
| 2. CRDT Persistence, PubSub & Consensus Authority | v1.0 | 2/2 | Complete | 2026-07-14 |
| 3. Discovery, Rewards & Lifecycle | v1.0 | 2/2 | Complete | 2026-07-14 |
| 4. Registration Proto & Transaction | v2.0 | 2/2 | Complete    | 2026-07-16 |
| 5. CRDT Persistence, PubSub & Integration Test | v2.0 | 3/4 | Gap Closure | 2026-07-16 |
