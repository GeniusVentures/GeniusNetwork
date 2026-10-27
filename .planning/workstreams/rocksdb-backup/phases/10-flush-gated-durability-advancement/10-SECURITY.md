---
phase: "10"
slug: "flush-gated-durability-advancement"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-27"
---

# Phase 10 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| SuperGenius drainer -> s3d admin listener (127.0.0.1:8001 default) | authenticated HTTP crossing to an external process; carries the admin credential and returns evidence the system acts on | HTTP Basic admin password (credential); /stats/uploads counters (semi-trusted) |
| operator -> crdt_config.json / SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD env | config file is at-rest input; env is the credential channel | config keys (non-secret topology + cadence knobs); admin password (secret) |
| s3d admin response -> durability advancement decision | semi-trusted network input parsed and used as the permission to mark records Durable | UploadStats JSON incl. the pendingObjects evidence |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-10-01 | Information Disclosure | S3AdminClientConfig.adminPassword / ColdStorageEnvLookup.admin_password | high | mitigate | env-only resolution (SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD, unset-or-empty = none — globaldb.cpp DefaultColdStorageEnvLookup); LogSummary redaction by omission (adminPassword referenced exactly once in globaldb.cpp: the enabled-config population, never in any summary/log/error); zero logging tokens in S3AdminClient.cpp (grep gate = 0); header doc carries the credential-never-logged tag | closed |
| T-10-02 | Tampering | UploadStats parsing / Flush response handling | medium | mitigate | conservative direction by construction: tampered/non-zero counters => NO advancement (records stay Accepted, fail-safe); strict nlohmann parse with per-field presence + integer-type checks (missing/mistyped => TemporarilyUnavailable); tlsVerify=true default; wire tests prove garbage/missing-field/non-200/timeout all classify TemporarilyUnavailable | closed |
| T-10-03 | DoS | S3AdminClient::Flush blocking the drainer + Stop() join | high | mitigate | per-call client-side read budgets used at both call sites (kCadenceFlushReadTimeoutMs cadence / kFinalFlushBudgetMs shutdown); stop_flag_ checked before initiating a flush; admin calls run on the idle drainer (never inline on the write path); bounded-Stop + black-hole budget tests prove the bounds | closed |
| T-10-04 | Spoofing | s3d admin endpoint exposed beyond loopback | medium | accept | s3d-side configuration, not controllable from this codebase; default endpoint is loopback; docs/s3d-durability.md carries the ops note ("deployments exposing the admin listener beyond loopback must firewall it accordingly") | closed (accepted risk AR-10-1) |
| T-10-05 | Information Disclosure (operator deception) | missing-admin-password posture | medium | mitigate | default-on flush + ONE startup WARN naming SGNS_BLOCKSTORE_S3_ADMIN_PASSWORD exactly (ColdStorageManager::Start, verified present); never silent, never a hard startup fail; last_flush_ok=false / last_flush_valid=false surface the condition in status; outage tests pin the behavior | closed |
| T-10-06 | Tampering | AdvanceDurabilityOnce snapshot discipline under race | high | mitigate | the pre-flush UploadedAccepted snapshot vector (captured under cold_store_mutex_) is the ONLY mark input; the mid-flush acceptance-race test proves a late-accepted CID cannot ride the cycle's evidence; the batched WriteBatch is all-or-nothing over its verified set | closed |
| T-10-07 | Tampering | staging-health predicate on garbage/absent stats | medium | mitigate | strict parse -> TemporarilyUnavailable -> admin_reachable=false -> staging_healthy false (fail-safe direction; GC inhibition defaults to inhibited on unreadable evidence); staging_fail_safe_on_admin_unreachable + garbage-stats tests pin it | closed |
| T-10-SC | Tampering | package installs (npm/pip/cargo) | high | mitigate | no package-manager installs this phase: cpp-httplib and nlohmann_json are existing superbuild pins consumed via find_package — no new external package enters any tree | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

Register origin: both PLANs (10-01, 10-02) carried `<threat_model>` blocks at plan time (`register_authored_at_plan_time: true`); SUMMARYs carried no additional threat flags.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-10-1 | T-10-04 | The s3d admin listener's network exposure is configured on the s3d side (separate process, default loopback-only); this codebase's controls are the loopback default endpoint + the documented firewall obligation in docs/s3d-durability.md §3 | GSD secure-phase (L1, plan-time register), per v1.1 PITFALLS Security table posture | 2026-10-27 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-27 | 8 | 8 | 0 | gsd secure-phase (ASVS L1 short-circuit: threats_open 0 + plan-time register + L1 -> grep-depth verification, no auditor spawn required) |

L1 evidence greps (all verified this run): env-only credential read present (1 hit); adminPassword referenced once in globaldb.cpp (population only); zero logging tokens in S3AdminClient.cpp; both flush budget constants used at their call sites; the missing-password WARN names the env var verbatim; the loopback/firewall ops note present in docs/s3d-durability.md; acceptance-race + staging-fail-safe tests present; staging fail-safe store paths present.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-27
