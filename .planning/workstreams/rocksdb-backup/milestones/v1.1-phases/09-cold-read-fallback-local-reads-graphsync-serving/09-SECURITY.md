---
phase: "9"
slug: "cold-read-fallback-local-reads-graphsync-serving"
status: verified
threats_open: 0
asvs_level: 1
created: "2026-10-27"
---

# Phase 9 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| local read paths → cold-store tiers | CRDT worker / pubsub-receive threads reach LocalBlockStore + S3BlockStore through the ColdReadService chain | block bytes (content-addressed), CIDs |
| peer requests → responder wrapper | Remote peers trigger cold misses (and thus background re-warms) on this node — remotely induceable | CID requests; re-warmed bytes later served to peers |
| cold-store bytes → peers | Re-warmed blocks are served back to remote peers — integrity must hold before serving | block bytes (must be CID-verified) |
| executor ↔ drainer | Two threads touch one MinioS3Client-backed store with no concurrent-call contract | S3 operation stream |
| fault kit → tests | Scripted faults simulate adversary-controlled store state inside hermetic tests | test-only; no live endpoints |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-9-01 | Tampering | ColdReadService::Get / Rehydrate | high | mitigate | Library Get CID-verifies internally on both tiers; no verify-bypassing ReadOptions anywhere in the service (grep-verified: zero `verify = false` occurrences); Corrupt stops its tier with attribution and corrupted bytes are never re-cached (SC3_CorruptAttributes*, SC3_LocalCorruptServesGoodS3Copy) | closed |
| T-9-02 | Denial of Service | GraphsyncDAGSyncer cold legs | medium | mitigate | Chain runs outside dagMutex_ after hot helpers return; transport faults fail fast and fall through to peers (D-03_LocalUnavailableFallsThroughToS3); duration bounded below the existing 20 s peer-fetch tolerance (SC2 evidence) | closed |
| T-9-03 | Information Disclosure | cold-read failure logging | medium | mitigate | Rate-limited lines carry BlockStatus code/class integers only; grep-verified: zero endpoint/secret/accessKey references in the cold-read sources; cold-vs-peer distinguishable wording (RESEARCH §3.4) | closed |
| T-9-04 | Denial of Service | library entry throw on out-of-set multihash | medium | mitigate | catch std::invalid_argument around every library entry (4 occurrences verified in ColdReadService.cpp: both tiers + HasLocalCold + rehydrate-path precedent) — malformed CIDs degrade to NotFound classification, never a crash | closed |
| T-9-05 | Denial of Service | ColdServeDagService::getNode on the single-thread pubsub io_context | critical | mitigate | Wrapper is delegate → try-enqueue → return (no wait/sleep/lock-across-I/O — source-inspected); worker on its own thread; SC2_HotServeUnderSaturatedSlowQueue + SC2_HotServeUnderOutageFailFastQueueChurning assert < 50 ms hot serve | closed |
| T-9-06 | Denial of Service | re-warm executor under peer-induced cold misses | high | mitigate | Per-CID coalescing (D07_RewarmCoalescesDuplicateEnqueues — exactly one fetch under duplicates); queue bounded at 64 with non-blocking drop+count (D07_RewarmQueueOverflowDropsWithoutBlocking); single worker bounds concurrent S3 loads | closed |
| T-9-07 | Tampering | re-warm fetch path (bytes later served to peers) | high | mitigate | Re-warm reuses the 09-01 chain (library verification unbypassable — T-9-01); the wrapper only ever serves blocks read back from the hot store; corrupted bytes classify Corrupt and are never re-cached | closed |
| T-9-08 | Denial of Service | concurrent S3BlockStore use (re-warm Get vs drainer Put) | medium | mitigate | remote_store_mutex_ serializes all remote-store calls (verified in both ColdReadService.cpp chain Get and ColdStorageManager.cpp per-Put drainer scope) | closed |
| T-9-09 | Information Disclosure | test fixtures and evidence banners | medium | mitigate | Hermetic fakes only (InMemoryS3Client, no live endpoints); evidence banners record latencies and counts only, never config values or credentials | closed |
| T-9-10 | Tampering | acceptance evidence (vacuous gates, label drift) | medium | mitigate | Behavior-level assertions; the one scoped structural search is comment-inclusive over the three new cold-read files (zero matches verified); fail-closed lane via --no-tests=error (5/5 green); registration/label parity guard 5==5 | closed |

*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on (high) count toward threats_open.*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|

No accepted risks.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-27 | 10 | 10 | 0 | inline auditor (Copilot runtime; L1 grep-depth + behavior-test evidence — ASVS L1 short-circuit contract: threats_open 0, plan-time register) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate)
- [x] Accepted risks documented (none)
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-27
