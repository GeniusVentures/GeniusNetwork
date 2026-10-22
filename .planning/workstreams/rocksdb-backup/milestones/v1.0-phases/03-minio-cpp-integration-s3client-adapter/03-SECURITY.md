---
phase: "03"
slug: "minio-cpp-integration-s3client-adapter"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-21"
---

# Phase 03 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Library ↔ S3 endpoint | MinioS3Client (internal adapter) speaks S3 over the network to a configured endpoint | Block bytes, bucket/object keys, per-endpoint access/secret keys (config-supplied, never library-generated) |
| Test process ↔ MinIO child | MinioServerHarness spawns a user-provided MinIO server binary as a child on 127.0.0.1 | Per-run random MINIO_ROOT_USER/MINIO_ROOT_PASSWORD via child env; self-signed TLS key/cert in per-test temp dir |
| Superbuild configure ↔ upstream git | miniocpp-deps.cmake clones cpp-httplib (v0.53.1) and inih (r58) at configure time | Pinned upstream source over https; clone failure fails configure loudly (D-12) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-3-01 | Information Disclosure | MinioServerHarness credentials | medium | mitigate | Per-run randomly generated MINIO_ROOT_USER/MINIO_ROOT_PASSWORD (RandomAlnum 8/16, MinioServerHarness.cpp:509-510) via child-process env only; never committed constants, never logged | closed |
| T-3-02 | Spoofing / MITM | S3ClientConfig TLS posture | high | mitigate | `tlsVerify = true` — NEVER default off (S3Client.hpp:60, documented at :48); verification disablement reachable only through the explicit config field, mapped to IgnoreCertCheck in MinioS3Client | closed |
| T-3-03 | Information Disclosure | MapMinioFailure message composition | medium | mitigate | Mapper copies only SDK response text into BlockStatus.message; sole credential reference in MinioS3Client.cpp is the StaticProvider constructor (:provider_(config.accessKey, config.secretKey)) — no config field enters any message/status string; no logging surface in the library | closed |
| T-3-04 | Tampering | miniocpp-deps.cmake configure-time clones | medium | mitigate | Upstream pins enforced by upstream's own checkout logic (cpp-httplib v0.53.1, inih r58); https URLs; submodule SHAs recorded by the superproject; NO PATCH_COMMAND — clone failure fails the configure loudly per D-12 (CommonTargets.cmake minio-cpp entry) | closed |
| T-3-05 | Tampering / DoS | LoopbackHttpStub socket bind | low | mitigate | Stub binds htonl(INADDR_LOOPBACK) ONLY on an ephemeral port (LoopbackHttpStub.cpp:179); no wildcard bind anywhere in the stub sources | closed |
| T-3-06 | DoS | MinIO child process lifecycle | low | mitigate | Fixture Stop(): TerminateChild (terminate → wait → close) then remove_all of the temp dir, all idempotent (MinioServerHarness.cpp:566-570); per-test unique temp dirs | closed |
| T-3-07 | Information Disclosure | In-process generated TLS private key file | low | mitigate | Per-run ephemeral RSA-2048 pair via OpenSSL CSPRNG EVP_RSA_gen(2048) (MinioServerHarness.cpp:345) protecting only a loopback server carrying per-run random credentials; written only into the per-test temp dir that Stop() remove_all's; never committed; in-process generation removed the prior child-process/command-line exposure | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|

No accepted risks.

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-21 | 7 | 7 | 0 | verify-work post-hook (L1 grep-depth, asvs_level 1 short-circuit; register authored at plan time across 03-01..03-04-PLAN.md) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-21
