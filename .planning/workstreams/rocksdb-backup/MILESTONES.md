# Milestones

## v1.0 CRDT Cold-Storage BlockStore Library (Sia s3d backend) (Shipped: 2026-10-22)

**Phases completed:** 5 phases, 16 plans, 40 tasks

**Key accomplishments:**
- sgns-blockstore repo bootstrapped, wired into the thirdparty superbuild end-to-end (repo → ExternalProject → install tree), and the C1 CID spike is 3/3 green — `p2p_cid` adopted per D-05/D-06 with the public sha-256-only `CidOf` helper shipped.
- The published v1.0.0 contract is frozen as a compiling unit (8 headers + anchor) and MemoryBlockStore proves every taxonomy/verification claim executable — 15/15 behavior tests green with the spike regression intact.
- The verification instruments shipped: any backend now gets the full 17-case conformance suite in one macro line, the API shape is enforced by compiling guards, and the hermetic suite has its CI lane — 4/4 local registrations green on the exact CI command.
- Durable RocksDB cold-tier backend where one atomic WriteBatch (block bytes + day-one PendingUpload journal record, sync=true) survives close-without-flush and replays from the WAL on reopen - byte-identical, CID-verified, journal enumerable.
- The upload journal became a durable, explicitly-transitioned, restart-recoverable state machine (Mark→Read→Recover), EvictLocal delivers D-10's unconditional one-batch local removal, and the Phase-1 conformance kit runs green against LocalBlockStore.
- The crash-window pair is proven (before-commit leaves nothing, after-commit recovers block+journal together via WAL replay), real on-disk corruption self-heals evict-and-surface (fault-path gated), and journal transitions reconcile exactly across restart — full tree 6/6 green.
- G-3-1 closed — in-process cert generation (OpenSSL C API) plus a TLS-wrapped readiness probe (user-approved option (a)); EnvGatedTlsOnSmoke executed live and passed (1343 ms) with only the MinIO gate set, minio_s3_client_test 11/11, zero skips, hygiene gate green.
- Terminal cold tier's hermetic core: promoted S3Client.hpp (03 D-04), S3BlockStore with the BACK-07 codec-preserving key layout and create-only PUTs, and the installed UploadDrainer - all proven against the fake in the default CI lane.
- Live s3d v0.2.1 spike proven green with committed evidence: 412 = mapper shape 1, HEAD-missing classifies natively (no D-05 contingency), and the no-per-object-durability-signal finding now ships as the repo's first prose doc, cited by Durability.hpp.
- The milestone story proven live end to end: real MinioS3Client→S3BlockStore green against the MinIO binary, and local Put → drain → s3d → fresh-process CID-verified cold retrieval green as two genuinely separate processes with committed evidence.
- The three-tier strategy is now enforced and inspectable from configuration alone: every ctest registration carries its tier LABEL, a self-inspecting Tier-1 audit with proven teeth guards the hermetic contract, and the CI lane is fail-closed to Tier1.
- All four journal-lifecycle crash windows are now proven through in-process reopen + WAL recovery + journal reconciliation, with stored corruption forged API-only through the new D-09 backend seam.
- SC1's letter is fully formalized: connection-refused, systematic 5xx, truncated bodies, and garbage responses each surface the correct taxonomy class at the real adapter with inline recovery - and every backend now inherits Has/GetSize fault honesty free from the kit.

**Stats:** Timeline 2026-10-19 → 2026-10-22 (4 days) · 9,426 LOC across 46 files in `thirdparty/sgns-blockstore` · 15 ctest registrations across three tiers (Tier-1 CI lane 12/12 green, zero regressions in the 14/14 full battery) · live evidence committed for the MinIO tier and the two-run fresh-process s3d E2E.

**Audit:** `milestones/v1.0-MILESTONE-AUDIT.md` — **passed** (21/21 requirements · 5/5 phases · 6/6 integration · 5/5 E2E flows; integration checker found 0 broken seams, 0 orphans).

**Known verification overrides:** 1 newly acknowledged, 1 carried forward from a prior close (see STATE.md Deferred Items). Phases 03/04 verification covered-digests were recorded stale at close — their covered files were legitimately evolved by Phase-5 hardening (fault seams in `InMemoryS3Client`, tier labels in `test/CMakeLists.txt`); both phases verified `passed` at their own close, and Phase-5 verification re-proved the final tree. User-approved `override_closeout`.

---
