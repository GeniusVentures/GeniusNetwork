---
phase: 04-s3blockstore-sia-s3d-roundtrip
plan: 01
subsystem: database
tags: [s3, blockstore, c++, cmake, gtest, object-storage, upload-journal]

requires:
  - phase: 03-minio-cpp-integration-s3client-adapter
    provides: S3Client adapter seam (InMemoryS3Client fake + MinioS3Client), api_hygiene/header_hygiene guards, tier registration patterns
  - phase: 02-localblockstore-rocksdb-cold-tier
    provides: LocalBlockStore journal surfaces (GetPendingUploads, MarkUploadedAccepted, GetUploadState) the drainer composes
provides:
  - Installed S3Client.hpp (promoted from src/ per 03 D-04) with the CORE-05/03-D-03 Delete reconciliation banner
  - S3BlockStore - BlockStore facade over shared_ptr<S3Client> with the BACK-07 codec-preserving key layout and conditional create-only PUTs (ObjectStoreAccepted ceiling)
  - UploadDrainer - installed per-item drain API (D-01..D-04): DrainItem + DrainPendingUploads, Accepted-only journal advance
  - InMemoryS3Client::ObjectKeys() key-observability conformance-test seam
  - Two new hermetic ctest targets (s3_block_store_test, upload_drainer_test) in the default CI lane
affects: [04-02 s3d spike, 04-03 live tiers, Phase 5 fault matrix]

actuals:
  tokens: 14000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Store-over-adapter facade: derive key -> one adapter op -> map into the frozen envelope (taxonomy propagates as-is, default bucket never NotFound)"
    - "Digest-byte fan-out: <xx> = hex(first multihash digest byte) - never the CID string head (bafkrei constant-prefix trap)"
    - "Per-item drain loop: wholesale envelope only for enumeration failure; journal advance only on remote-present outcomes"

key-files:
  created:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/S3BlockStore.hpp
    - thirdparty/sgns-blockstore/src/S3BlockStore.cpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/UploadDrainer.hpp
    - thirdparty/sgns-blockstore/src/UploadDrainer.cpp
    - thirdparty/sgns-blockstore/test/s3_block_store_test.cpp
    - thirdparty/sgns-blockstore/test/upload_drainer_test.cpp
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/S3Client.hpp (git-mv promotion of the former src header, banner rewritten)
    - thirdparty/sgns-blockstore/src/InMemoryS3Client.hpp/.cpp (include swap + ObjectKeys seam)
    - thirdparty/sgns-blockstore/src/MinioS3Client.hpp (include swap)
    - thirdparty/sgns-blockstore/src/CMakeLists.txt (two new sources)
    - thirdparty/sgns-blockstore/test/CMakeLists.txt (two new targets)
    - thirdparty/sgns-blockstore/test/api_hygiene_test.cpp (14 headers + 2 negative traits)
    - thirdparty/sgns-blockstore/test/in_memory_s3_client_test.cpp (include swap - deviation)
    - thirdparty/sgns-blockstore/test/minio_s3_client_test.cpp (include swap - deviation)

key-decisions:
  - "Whole-header promotion of S3Client.hpp with the banner-carried CORE-05/03-D-03 reconciliation (Delete = adapter-internal tooling op; delete-free split rejected as surface-without-risk-removal)"
  - "S3BlockStore Puts are createOnly ALWAYS (blocks immutable + pre-verified); 412 arrives as the alreadyPresent success slot - no client-side locking needed (conditionality is atomic adapter/server-side)"
  - "Durability ceiling: every Put reports ObjectStoreAccepted - Capabilities() advertises the same maximum; no durable claim anywhere"
  - "Fan-out on the first multihash DIGEST byte (256-way), display-only codec token, no CIDv0/v1 normalization (dedup by exact CID - v1 non-goal)"

patterns-established:
  - "Fresh-dir wipe in journal-composing test fixtures (stale dirs across binary runs reopen old journals)"
  - "Fault assertions clear the fault before fault-gated accessor calls (policy::terminate kills .value() on faulted envelopes)"

requirements-completed: [BACK-07, S3D-02]

coverage:
  - id: D1
    description: "S3Client.hpp promoted to the installed include tree (git mv, 82% rename similarity) with rewritten banner; installed-header guards extended and green"
    requirement: BACK-07
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore ctest api_hygiene_test (Pass, 1.1s)"
        status: pass
      - kind: unit
        ref: "thirdparty/sgns-blockstore ctest header_hygiene (Pass, 0.06s)"
        status: pass
      - kind: automated
        ref: "Test-Path promotion checks (old path absent, new path present, deployed tree carries both new headers)"
        status: pass
  - id: D2
    description: "S3BlockStore hermetic backend: full Phase-1 conformance kit over a fresh fake per case + known-vector key layout v1/blocks/raw/b9/bafkrei...36n5e observable in the fake's key set"
    requirement: BACK-07
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore ctest s3_block_store_test (Pass; 25 cases: 16 OK + 9 designed fault-conformance skips)"
        status: pass
  - id: D3
    description: "Store-specific taxonomy honesty: digest-byte fan-out (>=2 distinct components), planted-wrong-bytes Corrupt+Remote attribution, verify=false seam, Head mapping triple, Put fault propagation + no sticky cache, ObjectStoreAccepted capability ceiling"
    requirement: BACK-07
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore ctest s3_block_store_test (Pass - FanoutComponentIsFirstDigestByteHex, GetWrongBytesAtDerivedKeyIsCorruptRemote, GetVerifyDisabledReturnsPlantedBytes, GetSizeAndHasHeadMapping, HeadFaultIsTemporarilyUnavailableNeverAbsent, PutFaultPropagationAndNoStickyFailure, CapabilitiesAdvertiseAcceptedMaximum)"
        status: pass
  - id: D4
    description: "UploadDrainer installed API with journal discipline: happy path Accepted+empty pending+byte identity, fault retention with journal default-success, re-drain convergence, fresh-store alreadyPresent idempotent re-put, local-fault branch, empty-pending empty vector; Durable symbol source-gated absent"
    requirement: S3D-02
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore ctest upload_drainer_test (Pass, 5 cases)"
        status: pass
      - kind: automated
        ref: "Source token gates: MarkUploadedDurable absent from drainer sources; GetPendingUploads/MarkUploadedAccepted/DrainPendingUploads/DrainItem present"
        status: pass
  - id: D5
    description: "Zero regressions: full Phase 1-3 + 04-01 battery green on the Windows/MSVC Debug lane"
    requirement: BACK-07
    verification:
      - kind: automated
        ref: "ctest -R 'all 11 sgns-blockstore targets' - 100% passed (12.3s)"
        status: pass

duration: 95min
completed: 2026-10-21
status: complete
---

# Phase 4 Plan 01: S3BlockStore hermetic core + UploadDrainer + header promotion Summary

**Terminal cold tier's hermetic core: promoted S3Client.hpp (03 D-04), S3BlockStore with the BACK-07 codec-preserving key layout and create-only PUTs, and the installed UploadDrainer - all proven against the fake in the default CI lane.**

## Performance

- **Duration:** ~95 min (3 tasks)
- **Commits:** 3 (sgns-blockstore @ main: 40ab363, 8d4e4bc, efd178d)

## Accomplishments

- git-mv promotion of the adapter header from its former src location to the installed include tree (rename detected at 82%); banner rewritten with the promotion reality + CORE-05/03-D-03 Delete reconciliation + rejected-alternative note (costly-not-one-way)
- S3BlockStore: entry gate throws on non-sha256; verify-at-facade (CidOf explicit mapping, never OUTCOME_TRY); DeriveKey in one place (prefix/codec-token/digest-byte-hex/toString); Put always createOnly -> PutOutcome{ObjectStoreAccepted, alreadyPresent}; Get re-verifies with Corrupt+Remote attribution; Has maps Head exists; GetSize maps exists=false -> NotFound; PutMany per-element loop
- UploadDrainer: installed header + impl; snapshot -> per-CID local.Get -> remote.Put -> MarkUploadedAccepted only on success slots; per-item record-and-continue; wholesale envelope only on GetPendingUploads failure
- api_hygiene: 14 installed headers in the include-everything TU; !HasHead<!HasDelete negative traits for S3BlockStore; stale internal-seam comment rewritten
- InMemoryS3Client::ObjectKeys() sorted-key seam (CONFORMANCE-TEST SEAM)
- Full battery 11/11 green (Phases 1-3 + 04-01) on Windows/MSVC Debug; deployed include tree carries both new headers (INSTALL refreshed - Pitfall 6)

## Deviations from Plan

**[Rule 2 - Missing critical] Two test TUs not listed in files_modified broke on the move** - Found during: Task 1 | `test/in_memory_s3_client_test.cpp:21` and `test/minio_s3_client_test.cpp:32` used the quoted `#include "S3Client.hpp"` that the promotion moved out of src/ | Fix: swapped both to `<sgns-blockstore/S3Client.hpp>` | Files: the two test files | Verification: full battery green | Commit: 40ab363

**[Rule 2 - Wrong API name in plan] Multihash member is `content_address`, not `content_hash`** - Found during: Task 1 (first compile) | this libp2p pin's ContentIdentifier exposes `Multihash content_address`; the plan's token gate expected `content_hash` | Fix: used `content_address.getHash()` in impl + test; token gate satisfied with the corrected name | Commit: 40ab363

**[Rule 3 - Plan verify defect] Task-1 V5 deployed-tree filter is self-defeating** - the exclusion regex `include\sgns-blockstore\S3BlockStore.hpp$` also matches the deployed copy, so no file can ever survive it | Fix: satisfied the check's INTENT with a corrected filter; deployed headers verified present at `thirdparty/build/Windows/Debug/sgns-blockstore/include/sgns-blockstore/`

**[Rule 3 - Test-shape adjustment] "Exactly one of two items fails" in a single drain is not mechanically expressible** - both fault tables (fake SetFault, local FaultController) are op-kind-grained | Fix: record-and-continue + journal-default + pending-retention asserted per item on all-failing drains; sibling independence proven via fault-then-clear convergence and the fresh-store mixed path (alreadyPresent re-put); documented in the test file banner

**[Rule 3 - Test-shape adjustment] Local-miss branch exercised via the local fault seam** - the literal bytes-without-journal state is unreachable (EvictLocal removes bytes AND journal atomically; journal births WITH bytes in one batch) | Fix: local FaultKind::Unavailable drives the per-item local-failure path; documented in the test

**[Rule 3 - Test bug] Fresh-dir wipe added to the drainer fixture** - the monotonic dir counter resets each process run, so stale dirs from previous runs reopened old journals and broke determinism (EmptyPending saw non-empty pending) | Fix: FreshDir() wipes before Open | Also fixed: GetUploadState assertions moved after fault clear (fault-gated accessor + policy::terminate killed the binary)

**Total deviations:** 6 (2 Rule-2 auto-fixed, 4 Rule-3 test-shape/verify). **Impact:** none on the plan's truths - every must-have assertion is pinned; two extra files touched beyond files_modified (both mechanical include swaps).

## Issues Encountered

None - all gates green.

## Next Phase Readiness

Ready for 04-02 (s3d spike + durability finding). 04-01 delivered everything 04-02/04-03 compile against: the promoted header, S3BlockStore::Open(shared_ptr<S3Client>), the drainer, and the fake's key seam.
