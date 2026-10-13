# Requirements: IPFS P0 Remediation (ipfs-improve)

**Defined:** 2026-10-12
**Core Value:** Close the two non-CI P0 findings from the `gnus_libp2p_comparison.md` audit — Bitswap correctness bugs (canceled timers treated as timeouts; callbacks invoked under mutex) and unbounded GossipSub remote-driven state — with regression tests as acceptance evidence, fixed at the actual integrated SHAs and verified through the thirdparty pin chain into SuperGenius/GeniusSDK builds.

## v1 Requirements

Requirements for milestone v1.0 (ipfs-improve workstream). Each maps to roadmap phases.

### Bitswap Timer Correctness

- [x] **BSTP-01**: A canceled Bitswap request timer never fires the failure path — the `async_wait` handler checks `ec` and returns on `operation_aborted` (port of the in-file C-5 pattern from `ContentRequestContext` to `BitswapRequestContext`, `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp`)
- [x] **BSTP-02**: Each Bitswap block request yields exactly one terminal result — a completion flag checked under the mutex makes success and timeout paths mutually exclusive even when an already-expired handler fires with success after cancel
- [x] **BSTP-03**: Consumer-initiated cancellation or success produces no error callback; only a genuine timeout produces exactly one failure callback (`REQUEST_TIMEOUT`-class)

### Bitswap Reentrancy

- [ ] **BSTP-04**: Consumer callbacks are dispatched outside all internal mutexes — state mutated under lock (callbacks moved out, request marked complete, erased from the request map), callbacks invoked after unlock (port of the in-file C-7 pattern)
- [ ] **BSTP-05**: A consumer callback may synchronously re-enter Bitswap — cancel its own request or issue new requests — without deadlock or use-after-free (context kept alive via `shared_from_this()` during dispatch)

### GossipSub Resource Bounds

- [x] **GOSS-01**: The per-peer remote subscription table is bounded — a configurable cap in `Gossip::Config` (gossip.hpp); excess subscribe entries in an RPC are ignored, and the heartbeat sweep prunes non-live entries without ever evicting state a live remote subscriber depends on (Graft/Prune/IHAVE)
- [x] **GOSS-02**: The outbound per-peer pending queue is bounded by bytes at `write()` entry with a configurable knob in `Gossip::Config` — on cap hit the RPC is dropped (logged), not silently buffered; sustained overflow beyond a distinct higher threshold closes the slow stream
- [x] **GOSS-03**: A peer that persistently violates bounds is escalated through the existing `DenyListConnectionGater::BlockPeer()` path — no new policy machinery
- [x] **GOSS-04**: Every bound-enforcement event is observable — logged (peer, topic/count, bytes) via the existing `log::SubLogger`; no silent drops

### Regression Evidence

- [ ] **TEST-01**: Race-ordering regression tests exist and pass for the Bitswap fixes — cancel raced with expiry (both orders), response-then-canceled-timer-fires (no failure after success), timeout-then-late-response (no double callback), and reentrant callback canceling its own request without deadlock
- [x] **TEST-02**: Bound-enforcement tests exist and pass for the GossipSub fixes — subscription cap enforced per peer, outbound queue cap drops (not buffers, not disconnects) at the configured threshold, sustained overflow closes the stream, and violations reach the peer-block escalation path

### Integration

- [ ] **INTG-01**: Fixes land on the actual integrated submodule SHAs (ipfs-bitswap-cpp, libp2p, ipfs-pubsub as needed) and are verified against those SHAs — not branch tips — before pinning
- [ ] **INTG-02**: The `thirdparty` pins are updated with content-probed verification (fix markers confirmed present at the pinned commit, not trusted by branch name)
- [ ] **INTG-03**: SuperGenius focus suites pass on the repinned tree (CRDT/PubSub, DAG-syncer, AccountMessenger paths that consume bitswap/gossip), and GeniusSDK builds cleanly against the repinned tree

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Peer Scoring & Graylisting (GossipSub v1.1 scope)

- **PSCG-01**: Behavior-based peer scoring with thresholds (Gossip/Publish/Graylist) replacing manual block escalation
- **PSCG-02**: Decay-based graylist — auto-unblock after TTL using the existing `ban_interval_msec` precedent

### Queue Refinement

- **QUER-01**: Two-lane outbound queue (urgent control-message lane, Go `UrgentPush` parity) so mesh maintenance survives bulk publish load
- **QUER-02**: Idle outbound stream recycling
- **QUER-03**: CRDT-burst-aware bound tuning from real traffic measurements

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Restore CI and full test builds (audit P0 #3) | Explicitly excluded by operator for this milestone |
| Bitswap 1.1/1.2 protocols (Want-Have/Dont-Have), CIDv1 responses | Audit P1 — public-IPFS interoperability, distinct milestone |
| GNUS ↔ Go interoperability test harness | Audit P1 — verify-after-fix work, not fix work |
| Relay/NAT-traversal/reconnection field testing | Audit P1 — unrelated to the two in-scope P0 findings |
| Selective upstream QUIC/WebSocket transport integration | Audit P2 — connectivity expansion, not correctness |
| CPU/throughput/latency/memory benchmarking vs Go | Audit P2 — quantification, not remediation |
| Peer scoring (D-1) | GossipSub v1.1 scope; conflicts with GOSS-03's simple escalation if bundled |
| Rewriting the C++ stack in Go | Audit conclusion: not justified by the findings |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BSTP-01 | Phase 1 | Complete |
| BSTP-02 | Phase 1 | Complete |
| BSTP-03 | Phase 1 | Complete |
| BSTP-04 | Phase 2 | Pending |
| BSTP-05 | Phase 2 | Pending |
| GOSS-01 | Phase 3 | Complete |
| GOSS-02 | Phase 3 | Complete |
| GOSS-03 | Phase 3 | Complete |
| GOSS-04 | Phase 3 | Complete |
| TEST-01 | Phase 2 | Pending |
| TEST-02 | Phase 3 | Complete |
| INTG-01 | Phase 4 | Pending |
| INTG-02 | Phase 4 | Pending |
| INTG-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14 ✓
- Unmapped: 0

---
*Requirements defined: 2026-10-12*
*Last updated: 2026-10-12 — traceability filled by roadmap creation (Phase 1: BSTP-01..03, Phase 2: BSTP-04..05 + TEST-01, Phase 3: GOSS-01..04 + TEST-02, Phase 4: INTG-01..03)*
