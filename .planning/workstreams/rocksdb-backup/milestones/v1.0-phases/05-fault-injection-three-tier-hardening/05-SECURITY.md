---
phase: "05"
slug: "fault-injection-three-tier-hardening"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-22"
---

# Phase 5 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| CI lane → test selection | The `-L Tier1` filter decides what untrusted-environment CI executes; a leak runs live-endpoint tests in a hermetic lane | test selection config (build.yml) |
| audit script → test sources | tier1_audit_check.cmake reads developer-authored sources as untrusted input; a bypassable audit is a false tripwire | test source text |
| caller → library Put path | The D-09 hook executes inside the production Put commit tail; a misfire corrupts real stored data | block bytes (RocksDB) |
| crash suite → RocksDB WAL | The tests trust WAL recovery as the crash oracle; any flush/sync in the path silently converts proofs into no-ops | WAL records |
| reopened store → journal state | Journal reconciliation claims are the recovery contract consumers rely on | upload journal records |
| remote (fake) → store Get path | Scripted corrupt bytes cross the fake's success slot into S3BlockStore's CID verification (CORE-04) | object bytes |
| stub wire → real MinioS3Client | Raw HTTP responses from the FIFO stub are untrusted wire input to the SDK + mapper | raw HTTP bytes |
| kit macro → every backend | New generic fault cases become part of the frozen kit surface every backend must satisfy | conformance contract |
| doc inventory → readers | testing-tiers.md is the human-facing tier contract; drift misleads consumers | tier documentation |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-05-01 | Tampering | CI lane restriction (thirdparty/.github/workflows/build.yml) | high | mitigate | Fail-closed `-L Tier1` (never `-LE`); `--no-tests=error` fails empty selections; tier1_static_audit host-scan; count guard — four independent layers, all live-proven (negative probes + lane run) | closed |
| T-05-02 | Tampering | tier1_audit_check.cmake allowlist | medium | mitigate | Allowlist explicit and minimal (MinioServerHarness.cpp, bounded WaitUntilHealthy poll, justification comment); audit registered as a Tier1 ctest so it runs everywhere ctest runs | closed |
| T-05-03 | Information Disclosure | docs/testing-tiers.md drift | low | mitigate | Rows authored from the Task-1 label lines; token gate pins all 15 names + gate env vars + evidence pointers; doc-only drift accepted at low | closed |
| T-05-04 | Tampering | corrupt-after-commit hook (LocalBlockStore.cpp Put tail) | high | mitigate | TEST-ONLY arming: `corrupt_after_commit_` defaults false; settable only via `SetCorruptAfterCommitForTesting` whose Doxygen forbids production use; confined to the new-block Put tail (`!already_present` gate); no config/env/global trigger path | closed |
| T-05-05 | Tampering | hook journal-CF interaction | medium | mitigate | Hook never writes the journal CF (source-verified); StoredCorruptionSelfHealsEvictAndSurface pins the atomic co-evict; FaultCorruptionDoesNotEvict pins the kit seam stays copy-only — both green | closed |
| T-05-06 | Tampering | vacuous WAL proofs | medium | mitigate | Banner forbids Flush/SyncWAL (call-form token gate green); avoid_flush_during_shutdown=true fixed at open; state-3/4 reuse MakeStore/ReopenStore verbatim | closed |
| T-05-07 | Tampering | matrix re-implementing classification | medium | mitigate | All taxonomy assertions check mapper OUTCOMES; layer-discipline gate rejects CidOf in the transport suite (git grep green); the 412-variant case guards the mapper trio | closed |
| T-05-08 | Tampering | corrupt-remote-byte caching or deletion | high | mitigate | D-11 pinned by test: second Get re-fetches and still fails Corrupt+Remote; ObjectKeys() asserts the remote key survives every corruption assertion; repair-then-success asserts no sticky negative cache — all assertions green | closed |
| T-05-09 | Tampering | fake scripting seams callable from production | medium | accept | Established posture (fake ships in the static library); both methods carry CONFORMANCE-TEST SEAM docs; installed S3Client.hpp stays frozen (token-gated) — see Accepted Risks Log | closed |
| T-05-SC (05-01/02/03) | Tampering | package/dependency installs | high | mitigate | Zero package-manager installs across the phase — every commit touches in-repo CMake/C++/Markdown only; nothing to audit for package legitimacy | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-05-1 | T-05-09 | The InMemoryS3Client fake (with its scripting seams) ships inside the static library — established since Phase 3. The new SetFaultForKey/SetFlipBytesForKey seams widen the scripting surface but cross no adapter contract: S3Client.hpp is frozen (token-gated), both methods are documented CONFORMANCE-TEST SEAM (production code MUST NOT call), and no production call site exists. | plan disposition (05-03 threat model) + L1 audit | 2026-10-22 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-22 | 10 | 10 | 0 | execute-phase inline audit (ASVS L1 short-circuit: register authored at plan time, 0 open, L1 grep-depth sufficient) |

Classification basis: every mitigation was verified against the implementation during phase execution — build.yml token gate, audit negative probes, seam/frozen-header token gates, git-grep layer-discipline gate, and the green test battery (`ctest -L Tier1` 12/12) carry the evidence; no threat required a code change post-plan.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
