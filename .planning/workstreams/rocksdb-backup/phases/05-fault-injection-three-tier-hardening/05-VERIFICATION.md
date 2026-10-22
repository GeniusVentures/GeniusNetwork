---
phase: 05-fault-injection-three-tier-hardening
verified: 2026-10-22T21:55:00Z
status: passed
score: 3/3
requirements: TEST-01, TEST-02
covered_files:
  - thirdparty/sgns-blockstore/test/CMakeLists.txt
  - thirdparty/sgns-blockstore/test/tier1_audit_check.cmake
  - thirdparty/sgns-blockstore/docs/testing-tiers.md
  - thirdparty/sgns-blockstore/Readme.md
  - thirdparty/.github/workflows/build.yml
  - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
  - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
  - thirdparty/sgns-blockstore/test/local_block_store_crash_test.cpp
  - thirdparty/sgns-blockstore/src/InMemoryS3Client.hpp
  - thirdparty/sgns-blockstore/src/InMemoryS3Client.cpp
  - thirdparty/sgns-blockstore/include/sgns-blockstore/S3BlockStore.hpp
  - thirdparty/sgns-blockstore/test/s3_block_store_test.cpp
  - thirdparty/sgns-blockstore/test/upload_drainer_test.cpp
  - thirdparty/sgns-blockstore/test/minio_s3_client_test.cpp
  - thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp
covered_digest: v2:sha256:644903270d91ab7e86dfea1981df710016d8f90de1371ee36ec999dede2856d2
---

# Phase 5 Verification — Fault Injection & Three-Tier Hardening

**Goal (ROADMAP):** The library's trust claims hold under induced failure — taxonomy honesty, crash safety, and corruption rejection are proven, and the three-tier test strategy is complete with CI fully hermetic.

**Method:** goal-backward — each Success Criterion checked against the actual codebase and fresh test runs (2026-10-22, Windows Debug inner tree `thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build`), cross-referenced against the three plan SUMMARYs.

## SC 1 — Stub fault matrix: correct taxonomy, no sticky negative cache — VERIFIED

Evidence in `thirdparty/sgns-blockstore/test/minio_s3_client_test.cpp` (all green, 2026-10-22):
- connection-refused → TemporarilyUnavailable (never NotFound) + inline recovery via stub restart (new client fetches good bytes)
- 5xx systematic: 500 (existing) + **502 / 503 / 504 (new)** → TemporarilyUnavailable each, recovery tail per case
- truncated bodies: zero-byte (existing) + **after-first-byte cut + mid-headers cut (new)** → TemporarilyUnavailable
- garbage: non-HTTP text (existing) + **binary noise (new)** → TemporarilyUnavailable
- no sticky negative cache: `NoStickyNegativeCache` (existing, green) + EVERY fault case now ends with fault-cleared good fetch in its own body (D-06)
- 412 trio regression-guarded: XML body / empty body / **binary body (new)** → success slot `alreadyPresent` (`PreconditionXmlBody…`, `PreconditionEmptyBody…`, `PreconditionBinaryBody…`)

## SC 2 — Crash injection recovers via journal reconciliation; byte-flipped blocks rejected Corrupt with attribution — VERIFIED

Evidence in `thirdparty/sgns-blockstore/test/local_block_store_crash_test.cpp` (100% pass; new cases individually OK):
- Four-state matrix complete: pre-commit (`CrashBeforeCommitLeavesNothing`, existing), pending (`CrashAfterCommitRecoversBlockAndPending`, existing), **uploaded-but-unmarked (`CrashAfterRemoteUploadBeforeMarkReconcilesViaReDrain`, new: reopen surfaces PendingUpload + pending {cid}; re-drain converges `alreadyPresent==true`; journal advances to UploadedAccepted)**, **accepted (`AcceptedStateIsStableAndReDrainIsNoOp`, new: stable reader + no-op re-drain)**
- "mid-temp-write" window: proven ABSENT — the single atomic WriteBatch makes an interrupted local write crash-before-WAL-commit with nothing visible; documented in the suite banner (D-02 window model)
- Byte-flipped LOCAL block: D-09 `SetCorruptAfterCommitForTesting` hook (API-only, FaultController.hpp frozen — token-gated) → first Get Corrupt+Local, self-heal evicts block+journal atomically, re-Put repairs `alreadyPresent==false`
- Byte-flipped / wrong-length REMOTE block (`s3_block_store_test.cpp`): `GetScriptedFlip…ReFetchStaysCorruptAndRecoversInline` (Corrupt+Remote; second Get STILL Corrupt — no bad-byte cache; post-repair Get succeeds; `ObjectKeys()` proves never-deleted) and `GetTruncatedRemoteBodyIsCorruptRemote` (exact-byte CID verification)
- Partial-upload failure (`upload_drainer_test.cpp`): `PartialPutFaultFailsOneKeySiblingsAdvanceAndReDrainRetriesOnlyPending` — one key faulted mid-drain, siblings advance, exactly the failed CID retried and converged

## SC 3 — Three-tier strategy enforced + inspectable, CI fully hermetic — VERIFIED

Evidence in configuration itself (readable without running anything):
- `set_tests_properties(... LABELS ...)` on **all 15 registrations** in `thirdparty/sgns-blockstore/test/CMakeLists.txt` (8 pure Tier1, two `Tier1;Tier2` mixed, one Tier2, two Tier3, header_hygiene, tier1_static_audit)
- CI lane: `thirdparty/.github/workflows/build.yml` "Run sgns-blockstore tests" ends `-L Tier1 --no-tests=error` (fail-closed: `-L` never selects unlabeled tests; empty selection errors)
- `tier1_static_audit` ctest (Tier1): fixed-sleep scan (teeth proven by planted `std::this_thread::sleep_for` probe), non-loopback host scan (teeth proven by planted `play.min.io` probe), registration-vs-label count guard (teeth proven by unlabeled `addtest` probe); real tree passes inside the green lane
- Tier 2 opt-in via `SGNS_BLOCKSTORE_TEST_MINIO_BIN` (loud-skip without it); Tier 3 dev-only with committed evidence under `docs/evidence/s3d-spike/` — reused, never refreshed, per D-17
- Human inventory: `docs/testing-tiers.md` (15 rows mirroring the labels byte-for-byte + interplay rule + exact CI line + D-15/D-17 notes) linked from the new repo `Readme.md`

## Requirement traceability

| Req | Plans | Accounted |
|-----|-------|-----------|
| TEST-01 | 05-01 (frontmatter `requirements: [TEST-01]`, SUMMARY `requirements-completed`) | ✓ |
| TEST-02 | 05-02 + 05-03 (frontmatter + SUMMARY `requirements-completed`) | ✓ |

## Plan cross-reference

3/3 plans have SUMMARYs whose claims were spot-checked against disk and fresh runs: 05-01 (labels/audit/CI/docs — token gates + probes), 05-02 (hook + matrix — per-case runs), 05-03 (fault breadth — per-case runs + layer gates). Phase-final battery: `ctest -L Tier1` **12/12** including `tier1_static_audit`.

## Gaps

None. All three Success Criteria verified against the codebase; no human-verification items (the live Tier-2/Tier-3 lanes remain opt-in/dev-gated by design and are documented in the tier inventory — not phase-blocking).
