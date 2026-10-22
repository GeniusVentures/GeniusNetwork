---
phase: 03-minio-cpp-integration-s3client-adapter
plan: 03
subsystem: sgns-blockstore/src
tags: [minio-adapter, taxonomy, fault-matrix, containment]
requires: [03-01 spike + stub/harness, 03-02 S3Client interface]
provides: [MinioS3Client (SDK-backed adapter), one-place MapMinioFailure, D-08 fault matrix, complete SC2 guard chain]
affects: [sgns-blockstore static library, api_hygiene guards]
tech-stack:
  added: []
  patterns:
    - "pimpl adapter with ALL SDK usage in one TU (LocalBlockStore/rocksdb discipline)"
    - "one-place string-prefix failure mapping with never-NotFound default"
key-files:
  created:
    - thirdparty/sgns-blockstore/src/MinioS3Client.hpp
    - thirdparty/sgns-blockstore/src/MinioS3Client.cpp
    - thirdparty/sgns-blockstore/test/minio_s3_client_test.cpp
  modified:
    - thirdparty/sgns-blockstore/test/api_hygiene_test.cpp
    - thirdparty/sgns-blockstore/src/CMakeLists.txt
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
key-decisions:
  - "SDK Client SNAPSHOTS BaseUrl at construction: port/virtual_style must be fully set BEFORE client init, or every op silently targets port 0/80 (matrix spike finding - failure-shape tests can mask it because connect failures also map TemporarilyUnavailable)"
  - "Plain (non-createOnly) Put computes alreadyPresent via read-before-write StatObject; a failed pre-check never blocks the Put (the Put reports the real failure); createOnly gets it for free via the 412"
  - "Head authoritative miss detected by IsAuthoritativeAbsence (NoSuchKey:/NoSuchBucket: prefixes) BEFORE MapMinioFailure, returning the success slot exists=false per the 03-02 interface contract"
requirements-completed: [BACK-06]
duration: 35 min
completed: 2026-10-21T20:55:00Z
coverage:
  - deliverable: "MinioS3Client pimpl implementation + one-place mapper (BACK-06)"
    verification:
      - kind: command
        ref: "SDK-confined-to-one-TU grep guard; one-place mapper guard (6 occurrences all in MinioS3Client.cpp); library build green"
        status: pass
    human_judgment: false
  - deliverable: "D-08 hermetic stub fault matrix (SC4 mapping half)"
    verification:
      - kind: tests
        ref: "inner-tree ctest#minio_s3_client_test (Passed - 8 matrix cases + 3 live-tier skips)"
        status: pass
      - kind: command
        ref: "tier-gate -VV label check with env unset; 7 required case names present"
        status: pass
    human_judgment: false
  - deliverable: "SC2 guard chain complete"
    verification:
      - kind: tests
        ref: "api_hygiene_test + header_hygiene green with the SDK + MinioS3Client compiled into the lib"
        status: pass
      - kind: command
        ref: "git grep minio-include over include/ exits 1 (installed headers SDK-free)"
        status: pass
    human_judgment: false
  - deliverable: "Live MinIO roundtrip + real-412 (SC4a, env-gated)"
    verification: []
    human_judgment: true
    rationale: "SGNS_BLOCKSTORE_TEST_MINIO_BIN unset on this box (D-07 opt-in by design); the live cases are wired through the same harness proven in 03-01 and skip loudly - needs a bring-your-own-binary run"
---

# Phase 3 Plan 03: MinioS3Client + Fault Matrix + Containment Guards Summary

One-liner: the SDK-backed adapter lands with every failure string classified in exactly one place (never-NotFound default proven per wire shape), the D-08 stub matrix proves all four fault classes plus both 412 shapes hermetically, and the SC2 guard chain (compile + grep + ctest) is complete — Phase 4 composes over a proven seam.

Duration: 35 min | Tasks: 3 | Files: 6

## Accomplishments

- `MinioS3Client` (pimpl, `Open(config)` factory, invalid-argument throw on empty endpoint/bucket): all four ops over `minio::s3::Client`; createOnly → `If-None-Match:*` via the args `headers` Multimap (never `extra_headers`); `IgnoreCertCheck(!tlsVerify)` exactly once as the only TLS control; region pinned `us-east-1`; ALL SDK namespace tokens confined to `MinioS3Client.cpp` (grep-guarded).
- `MapMinioFailure` (anonymous namespace, Doxygen, one place): `NoSuchKey:`/`NoSuchBucket:` → NotFound; `AccessDenied:` → Unauthorized; everything else → TemporarilyUnavailable with the message preserved, Remote source. `IsPreconditionFailure` handles all three 412 evidence shapes and returns the D-02 success slot BEFORE the mapper. No config field ever enters message composition (T-3-03).
- Stub matrix (8 cases, default CI lane): refused/500/truncated/garbage → TemporarilyUnavailable with NOT-NotFound asserted; XML-412 and empty-body-412 → success slot `alreadyPresent=true`; 404 NoSuchKey XML → NotFound; NoStickyNegativeCache recovers on the same client instance.
- Env-gated live tier (3 cases via the 03-01 `MinioServerHarness`): loud `[SGNS_BLOCKSTORE][MINIO-TIER]` skip when unset; live roundtrip, real-412 duplicate, TLS-off-primary-lane documentation case.
- `api_hygiene_test` extended: concrete backends asserted delete-free (D-03), `HasHead` S3-op-name-negative trait across the public family, full-SC2-chain comment. `header_hygiene` unchanged (already bans `minio`).
- Full 9-suite battery 100% green on Windows/MSVC Debug.

## Deviations from Plan

**[Rule 1 - SDK construction-order fact] BaseUrl snapshot at Client construction** — Found during: Task 2 | Issue: matrix cases 5-8 failed with "Could not establish connection" (~2s timeouts): the Impl set `base_url_.port` AFTER the `client_` member was initialized; the SDK snapshots BaseUrl when the Client is built, so the port never reached it — and the four failure-shape cases MASKED the bug because a connect failure also maps to TemporarilyUnavailable (a taxonomy-honest but evidence-empty pass) | Fix: `MakeBaseUrl(config)` helper fully configures port/virtual_style before `client_`'s member-init; member-order note in the Impl Doxygen | Files: MinioS3Client.cpp | Verification: all 11 cases green in 2.5s (was 18.7s of timeouts); response-specific cases now classify real responses | Commit: ce7d343

**[Rule 1 - guard fidelity] SDK tokens in the pimpl header comment** — Found during: Task 1 | Issue: the containment grep matched the header's own documentation comment ("all minio::/miniocpp:: usage...") | Fix: comment reworded to "every minio-cpp namespace token" — the guard now measures code, not prose | Files: MinioS3Client.hpp | Commit: 9f4ba5d

**[Rule 1 - tooling detail] git grep needs tracked files** — Found during: Task 1 | Issue: the plan's git-grep guards silently matched nothing for untracked new files | Fix: `git add -N` (intent-to-add) before the guards | Commit: (with 9f4ba5d staging)

**[Rule 2 - sequencing] Live tier written with the matrix TU** — Found during: Task 2 | Issue: the plan's Task 3 "extends" minio_s3_client_test.cpp, but writing the TU once with both halves avoided a rebuild cycle; Task 3's commit then carried only the api_hygiene extension | Impact: none — both task verify batteries ran green independently

Total deviations: 4 auto-fixed. **Impact:** one real SDK behavioral fact discovered and recorded (BaseUrl snapshot); zero red-line changes.

## Issues Encountered

None blocking. Noted: the failure-shape matrix tests can pass for the wrong reason against a mis-configured client (every transport failure maps TemporarilyUnavailable) — the response-specific cases (412/404/200) are the load-bearing evidence; recorded in the test header comment.

## Authentication Gates

None.

## Commits

- sgns-blockstore: 9f4ba5d (feat MinioS3Client), ce7d343 (test matrix + live tier + BaseUrl fix), 0af8055 (test SC2 guards)
- thirdparty: 8585215 (pointer bump)
- root: e5535b2 (pointer bump)

## Self-Check: PASSED
