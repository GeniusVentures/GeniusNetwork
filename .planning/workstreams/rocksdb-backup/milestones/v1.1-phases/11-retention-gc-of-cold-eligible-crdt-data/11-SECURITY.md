---
phase: "11"
slug: "retention-gc-of-cold-eligible-crdt-data"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-27"
---

# Phase 11 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Register authored at plan time across all four PLANs; L1 (grep-depth)
> verification with the session's green suites as run evidence; ASVS L1
> short-circuit applied (threats_open 0 + plan-time register + asvs 1).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| operator -> crdt_config.json blockstore.retention | at-rest config arms a destructive capability | retention config (age/knobs; credentials never here) |
| GC thread -> hot CRDT RocksDB + library cold RocksDB | the phase's first code that READS the full DAG and DELETES local state | CID-keyed block bytes, set rows, seal keys, markers |
| GC policy -> Phase-10 durability/staging evidence | eligibility consumes evidence records; misread evidence would arm eviction | journal states, spill timestamps, admin stats |
| pubsub re-delivery -> HasBlock disposed term | untrusted remote data hits the dedup point lookup | CID presence queries (no payloads fetched) |
| peer graphsync request -> responder cold chain for a disposed CID | untrusted requests trigger cold-tier fetches on the serving node | CID-verified block bytes |
| dev machine -> live s3d daemon + Sia network | real uploads (rent) against the funded account; evidence crosses into the repo | block bytes, run captures (redacted) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-11-01 | Tampering | retention config parse/activation | high | mitigate | Absent = no GC actor (byte-identical); required positive age loud (absence AND 0 tracked separately); unknown key/wrong type loud; retention-only never activates (gate (e)) + inert WARN — 7 Retention* matrix cases green; wallet asset guard counts zero `retention` | closed |
| T-11-02 | Tampering/Destruction | eligibility evidence (walk + durability + age) | high | mitigate | Fresh full walk with unconditional traversal (Pitfall-1 regression test); heads-equality exactness abort; strict age tie-to-under-eviction; skew reads young; state EXACTLY Durable (MI-02, Unreadable enum); journal-enumerated only (MI-01) — honesty suite green | closed |
| T-11-03 | Information Disclosure | gc: logging + LogSummary | medium | mitigate | LogSummary renders only the four non-secret retention knobs and only when configured (grep: retention_dry_run knob, no credential members); gc: vocabulary rate-limited and distinguishable; redaction by omission holds | closed |
| T-11-04 | Destruction | eviction decision (wrongful eviction) | critical | mitigate | Four-way gate + delete-time heads-equality vs the mark's OWN snapshot with cancel-keep-bytes + grace + dry_run; every fault case (crash mid-grace, between-halves, cancel) green and landing under-eviction; remote copy + GC-03 bound the blast radius | closed |
| T-11-05 | Tampering | cross-store partial eviction | high | mitigate | D-16 two idempotent single-store halves (library batch + hot batch); keys computed from the block's own delta, never enumerated; orphan re-scan completes half-2; LRU-after-deletes (A6); spy keyspace proof: t/h/k zero ops, other s-rows zero, never-purged end-state byte-guard | closed |
| T-11-06 | DoS/Tampering | disposed-marker store | medium | mitigate | Dual bound (cap 100000 + 30-day age, TrimDisposed one batch, oldest-first) — trim unit green; records written only by the library codec; re-learn converges (re-journal test); marker count in status; 25-delivery storm zero S3 gets | closed |
| T-11-07 | Tampering/Spoofing | cold retrieval of disposed CIDs | high | mitigate | Every cold fetch CID-verified in-library (EquivalentCidClaim strengthens the verify paths; flip-bytes rejected COLD_STORAGE_CORRUPT — never good bytes, never NotFound); D-12 split asserted on both legs; re-warm bounded off the inline path | closed |
| T-11-08 | Tampering/DoS | re-delivery storms / resurrection | medium | mitigate | Marker-term dedup at HasBlock (three inherited call sites, zero audits); storm test proves zero S3 traffic; rehydrate stays bytes-only (no seal restore — SC4 silence asserted), so stale re-delivery cannot resurrect values | closed |
| T-11-09 | Information Disclosure | evidence artifacts (committed secrets) | high | mitigate | Env-var NAMES only in the runbook/captures; credential-value-shape grep over docs/evidence/gc-e2e counts zero; human review at the blocking checkpoint was the second line (numbers confirmed) | closed |
| T-11-10 | Tampering | live-tier tests leaking into CI | high | mitigate | Tier3/Tier2 labels only with env-gated loud skips naming every var (verified green unset); Tier-1 lane re-run hermetic 8/8 + 14/14 after registration; never registered in the CI lane | closed |
| T-11-SC | Tampering | package installs | high | mitigate | No package-manager installs across all four plans: existing superbuild pins only (rocksdb, GTest, minio-cpp via shipped targets); s3d/MinIO binaries are pre-existing local artifacts invoked as test subprocesses; the phase diffs add no dependency entries | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-11-1 | T-11-04 (scope note, not a threat gap) | The Sia-cloud durability leg of the live E2E is unproven this session (uploads staged, finalize not completing on unfunded rent) — the ceiling mode was checkpoint-ruled and log-corroborated; local eviction safety is unaffected (the destructive decision rests on journal evidence, not Sia state) | Operator (blocking checkpoint) | 2026-10-27 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-27 | 11 | 11 | 0 | inline L1 short-circuit (plan-time register, ASVS 1) — grep evidence + the session's green Tier-1/Tier-2/Tier-3 runs |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-27
