---
phase: "8"
slug: "spill-on-write-background-drainer"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-26"
---

# Phase 8 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| remote peer -> CRDT write path | untrusted CIDs/bytes arrive via pubsub sync and reach the decorator set() under dagMutex_ | arbitrary multihash CIDs + block bytes (untrusted) |
| config file -> factory | crdt_config.json blockstore values cross into S3 client construction and directory derivation | endpoint/bucket/access_key/secret_key (credentials) |
| config file -> drainer policy | crdt_config.json backpressure values cross into thread cadence/backoff/watermark behavior | drain_interval_ms/warn_pending/critical_pending/backoff_cap_ms |
| drainer thread -> shared stores | the drain path touches LocalBlockStore concurrently with the publisher path (shared mutex discipline) | journal records + block bytes (local, integrity-sensitive) |
| shutdown path -> thread lifetime | ShutdownNow must not tear stores down under a live drainer | thread handle + store ownership |
| evidence artifacts -> operator decisions | the benchmark/disposition doc shapes what operators believe about CI coverage and write-path latency | documented evidence claims |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-8-01 | Denial of Service | BlockStoreBackedIpfsDatastore::set (dagMutex_ path) | high | mitigate | Defensive `catch(std::invalid_argument)` around the journal Put + `has_value()` guards on every library result — hostile out-of-set-multihash CID yields a loud outcome failure, never a node death. **Verified:** `SuperGenius/src/crdt/globaldb/BlockStoreBackedIpfsDatastore.cpp:62-96` (catch at :89, guards at :64); journal failure fails the publish loudly with rate-limited logging | closed |
| T-8-02 | Information Disclosure | factory + decorator error logging | high | mitigate | Redaction by omission: error lines carry BlockStatus codes/counts only, never access_key/secret_key. **Verified:** `cold_storage_config_gate_test.cpp:217` `LogSummaryContainsEndpointBucketAndNoCredentials` asserts SECRET-ACCESS/SECRET-VALUE absent from the log summary; decorator failure logs emit `code {}` integers only (`BlockStoreBackedIpfsDatastore.cpp:75-83`) | closed |
| T-8-03 | Tampering | decorator set ordering | medium | mitigate | Journal-first ordering + D-04 fail-loud mapping; re-put idempotency and journal-failure-fails-Put test cases. **Verified:** journal-first atomic WriteBatch at `BlockStoreBackedIpfsDatastore.cpp:55`; `re_put_is_idempotent` (:466) + `journal_failure_fails_put_loudly` (:539) in `cold_storage_spill_test.cpp` | closed |
| T-8-04 | Denial of Service | ColdStorageManager lifecycle / ShutdownNow ordering | high | mitigate | stop -> bounded grace -> join BEFORE lifecycle_mutex_ teardown; never detach; member declaration order destroys the manager after the stores. **Verified:** grace window + unconditional `thread_.join()` at `ColdStorageManager.cpp:86-95`, destructor joins first (:41); no detach call exists; `globaldb.cpp:402` `StopColdStorageManager()` sits after `StopBackupLoop()` (:398) and before the `lifecycle_mutex_` teardown (:407); `shutdown_grace_joins` test (:793) | closed |
| T-8-05 | Repudiation | blockstore.backpressure parser | medium | mitigate | Strict single-member loop: non-object/unknown-key/wrong-type/warn>=critical all fail startup loudly naming `blockstore.backpressure.<k>` — no silent disable. **Verified:** `BackpressureUnknownKeyFails` (:307), `BackpressureWrongTypeFails` (:314), `BackpressureNotAnObjectFails` (:324), `BackpressureWarnAtOrAboveCriticalFails` (:331) with exact-message assertions in `cold_storage_config_gate_test.cpp` | closed |
| T-8-06 | Denial of Service | unbounded journal growth during s3d outage (D-01 accepted policy) | medium | mitigate | Dual record-count watermark with always-on alarm, transition + heartbeat logging, and the status getter make growth visible operator signal, never silent (D-02/D-07/D-09); bounded-degrade explicitly rejected in D-01 — visibility is the mitigation. **Verified:** `UpdateWatermark` Warn/Critical transitions + recovery logging + held-watermark heartbeat at `ColdStorageManager.cpp:257-310`; atomics-backed status getter (:111); `s3d_down_window_keeps_publishing` exercises the crossing end-to-end (:713) | closed |
| T-8-07 | Tampering | SC1 benchmark methodology | low | mitigate | Benchmark gate: paused-vs-running with injected latency, never ON-vs-OFF; assertions on BOTH the distribution match and the absolute ceiling. **Verified:** `sc1_set_latency_independent_of_drainer_state` (:882) — 300 ms injected latency, `EXPECT_LT(p99, 100.0)` asserted for BOTH paused (:928) and running (:929) scenarios | closed |
| T-8-08 | Tampering | crash-resume double-upload | medium | mitigate | createOnly idempotency + mark-only-on-remote-present asserted with a pre-loaded remote object (exactly-once convergence, no duplicates). **Verified:** `crash_restart_reconciles` (:651) with D-12/SC3 createOnly convergence — "lost, nothing duplicated" | closed |
| T-8-SC | Tampering | package installs | high | mitigate | No package-manager installs this phase (all in-repo static libraries; test-local wrappers over in-repo fakes only) — gate not triggered; any future install must pass the legitimacy checkpoint. **Verified:** phase artifacts touch only in-repo files (no dependency manifests changed per all three SUMMARYs) | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|

No accepted risks. (Note: T-8-06's unbounded-journal growth is a D-01 **policy** decision — bounded-degrade was rejected, not risk-accepted; the threat itself is mitigated through always-on watermark visibility.)

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-26 | 9 | 9 | 0 | gsd-secure-phase (orchestrator, L1 grep-depth — ASVS L1 short-circuit: register authored at plan time, 0 open threats) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-26
