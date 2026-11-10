---
phase: 12
plan: 03
subsystem: cold-storage
tags: [cold-storage, sc4, fresh-clone, ci, tag-build, testing]
requires: []
provides:
  - "SC4 fresh-clone proof: tag-build Tier-1 green on Windows/Linux/OSX Release with cold storage ON from pushed commits only"
  - "tier-label audit (tier1_static_audit) green in the CI lane for the first time"
  - "D-05 minimal checklist evidence record (run 42905264387)"
affects: []
tech-stack:
  added:
  - "installed test-fake headers (InMemoryS3Client/InMemoryS3AdminClient ship with the library)"
  patterns:
  - "header-install ruling supersedes source-overlay approaches for tarball consumers"
key-files:
  created:
  - .planning/workstreams/rocksdb-backup/phases/12-integration-hardening-fault-races-fresh-clone-proof/12-FRESH-CLONE-CHECKLIST.md
  modified:
  - thirdparty/sgns-blockstore/src/CMakeLists.txt
  - thirdparty/sgns-blockstore/include/sgns-blockstore/InMemoryS3Client.hpp
  - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
---

# 12-03 Summary — Fresh-Clone Three-Platform Proof (SC4 closing evidence)

**Status: COMPLETE (2026-11-10)** · All tasks including the blocking D-03 human checkpoint.

## What was built

Tasks 1-3 (completed 2026-10-28, prior session): the tracer initially
introduced a test-source cache variable plus CI sparse overlay, then the
user ruling replaced both with the stronger form — the test fakes are
INSTALLED WITH the library, so every tarball consumer gets them as ordinary
public headers with zero source-tree coupling. The tier-label audit was
ported and registered in the Tier-1 lane. Both CI ON surfaces were wired
(permanent every-push legs plus the tag-build cold-storage dispatch posture
with upload suppression).

Task 4 (the D-03 checkpoint, closed 2026-11-10): the user pushed all three
repos innermost-first, cut the final thirdparty release tag, and dispatched
the tag build. SuperGenius Tag Build run 42905264387 (head 9994718ce, all
fifteen matrix jobs success) consumed the rtti release tag with tests and
cold storage enabled: Windows Release 153/153, Linux x86_64 Release
152/152, OSX Release 155/155 — one hundred percent on every SC4 leg, with
the configure ON flag and the consumed tag verified in each leg's log. The
audit test ran and passed inside the CI lane for the first time.

## Key decisions and deviations

- The header-install ruling (user, 2026-10-28) superseded the planned
  cache-variable tracer approach; recorded in the checklist and the
  approach-change note.
- The final dependency tag is the rti variant of the cold-storage tag: the
  RocksDB RTTI change forced a re-cut over the interim tag. Both are
  recorded in the checklist with their payload boundaries.
- The permanent every-push ON-leg baseline is pending by topology, not
  defect: this branch does not trigger the develop CI workflow, so the
  regression net activates at merge. The tag-build legs prove the identical
  configure.

## Evidence

The minimal-checklist doc carries the full record: per-leg pass counts,
configure ON verification, the run URL, the fail-closed SHA table, and the
audit result. Raw logs live in the run history per the D-05 posture.
