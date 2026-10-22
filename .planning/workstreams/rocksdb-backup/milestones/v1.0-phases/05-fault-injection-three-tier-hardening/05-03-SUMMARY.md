---
phase: 05-fault-injection-three-tier-hardening
plan: 03
subsystem: testing
tags: [fault-injection, http-stub, conformance-kit, s3, c++]

requires:
  - phase: 05-fault-injection-three-tier-hardening
    provides: the labeled Tier1 lane + audit (05-01) and the fake per-key/flip seams with the store matrix (05-03 Task 1, same plan)
provides:
  - Systematic loopback-stub fault matrix at the real MinioS3Client (502/503/504, two truncation cut points + mid-headers cut, text + binary garbage shapes, third 412 wire variant) with D-06 inline recovery on every case
  - Backend-generic Has/GetSize fault-honesty cases inside the conformance kit (every backend instantiates them free)
affects: [phase verification, v1.0 milestone close]

actuals:
  tokens: 6500
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Assert mapper OUTCOMES only - never re-classify responses in tests, never re-verify what the store already verifies (layer-discipline git-grep gate)"

key-files:
  created: []
  modified:
    - thirdparty/sgns-blockstore/src/InMemoryS3Client.hpp
    - thirdparty/sgns-blockstore/src/InMemoryS3Client.cpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/S3BlockStore.hpp
    - thirdparty/sgns-blockstore/test/s3_block_store_test.cpp
    - thirdparty/sgns-blockstore/test/upload_drainer_test.cpp
    - thirdparty/sgns-blockstore/test/minio_s3_client_test.cpp
    - thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp

key-decisions:
  - "FaultFor(S3FaultKind) extracted as a static mapper so the key-scoped overlay and the op-level table share one classification body (FaultGate keeps its gate role)"
  - "ClearFaults clears BOTH fault tables (op-level + key-scoped); the flip set clears per key - the letter of the plan's bulk-clear rule"
  - "Connection-refused recovery proves the transport itself recovers: stub restarted on a fresh ephemeral port + a new client fetches good bytes (the dead port is unreachable by construction)"

patterns-established:
  - "Per-case recovery tail (D-06): every fault case ends in its own body with fault cleared and a good fetch succeeding - no cross-test state clearing"

requirements-completed: [TEST-02]

coverage:
  - id: D1
    description: "Fake fault-seam extensions (SetFaultForKey key-scoped overlay with documented precedence; SetFlipBytesForKey success-slot flip) + store-level remote-corruption matrix + D-12 Has/GetSize notes"
    requirement: TEST-02
    verification:
      - kind: unit
        ref: "s3_block_store_test + in_memory_s3_client_test: 100% - GetScriptedFlip...ReFetchStaysCorruptAndRecoversInline and GetTruncatedRemoteBodyIsCorruptRemote OK individually"
        status: pass
      - kind: other
        ref: "containment gates: seam symbols in the fake header only; S3Client.hpp frozen (token-gated); D-12 'not content-verifying' present on Has+GetSize; layer-discipline grep (no CidOf in transport suite) green"
        status: pass
    human_judgment: false
  - id: D2
    description: "Drainer key-scoped partial failure: one item fails mid-drain while siblings upload and advance, failed item retained pending, re-drain retries exactly the still-pending block"
    requirement: TEST-02
    verification:
      - kind: unit
        ref: "upload_drainer_test 100% - PartialPutFaultFailsOneKeySiblingsAdvanceAndReDrainRetriesOnlyPending OK individually (71ms)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Systematic stub fault matrix at the real MinioS3Client (SC1 letter: connection-refused, systematic 5xx, truncated bodies, garbage responses - correct taxonomy class each, no sticky negative caching) + backend-generic kit fault cases (D-07)"
    requirement: TEST-02
    verification:
      - kind: unit
        ref: "minio_s3_client_test + memory/local/s3 store suites: 100%; new cases (502/503/504, both new truncation cuts, binary garbage, binary-body 412) OK individually; kit FaultOnHas/FaultOnGetSize OK in the LocalBlockStore instantiation and green across all three backend suites"
        status: pass
      - kind: other
        ref: "phase-final battery: ctest -L Tier1 12/12 including tier1_static_audit (audit scans all new test content clean)"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-10-22
status: complete
---

# Phase 5 Plan 03: Fault-Matrix Breadth Summary

**SC1's letter is fully formalized: connection-refused, systematic 5xx, truncated bodies, and garbage responses each surface the correct taxonomy class at the real adapter with inline recovery - and every backend now inherits Has/GetSize fault honesty free from the kit.**

## Performance

- **Duration:** ~55 min (3 tasks)
- **Tokens (actuals):** ~6.5K over 7 changed files

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 3e8bbe7 (sgns-blockstore) | fake fault-seam extensions + store corruption matrix (D-05b/D-08/D-10..D-12) |
| 2 | 6659bfb (sgns-blockstore) | drainer key-scoped partial failure (D-05c/D-06) |
| 3 | 3239939 (sgns-blockstore) | systematic stub matrix + kit fault cases (D-05a/D-06/D-07/D-08) |
| ptr | 1eb4b0b (thirdparty) | sgns-blockstore pointer bump |

## What Was Built

- **Fake seams (Gap A/B):** `SetFaultForKey(key, op, kind)` - key-scoped overlay consulted BEFORE the op table (keyed fault wins for that key; None clears; ClearFaults clears both tables) - and `SetFlipBytesForKey` - Get serves the SUCCESS slot with a first-byte-flipped copy so the store's CID verify is the detector (D-08 layer split). Both CONFORMANCE-TEST SEAM documented; the installed S3Client.hpp interface is untouched (token-gated).
- **Store corruption matrix:** scripted-flip case proves Corrupt+Remote -> re-fetch STILL Corrupt (no bad-byte cache, D-11) -> post-repair Get succeeds (no sticky negative cache, D-06) -> ObjectKeys proves the remote block NEVER deleted (CORE-05); truncated-body case proves exact-byte CID verification (wrong length = Corrupt at the STORE layer). Has/GetSize carry the D-12 not-content-verifying notes.
- **Drainer partial failure:** the middle of three blocks key-faulted on Put - same-drain mixed outcome (failed item TemporarilyUnavailable/Remote + journal default-success; both siblings upload AND advance), exactly the failed CID stays pending, re-drain returns exactly one item (achieved, not alreadyPresent) and empties the set. Banner limitation note rewritten as LIFTED.
- **Stub matrix:** 502/503/504 cases; second truncation cut (body cut after first byte) + mid-headers cut; binary-noise garbage shape; third 412 wire variant (unparseable binary body -> success-slot alreadyPresent, guarding the mapper trio). EVERY fault case retrofitted with the D-06 inline recovery tail in its own body.
- **Kit (D-07):** FaultOnHas...NeverFalse and FaultOnGetSize...NeverNotFound join the macro body - every backend instantiates them free; [fault-conformance] loud-skip probe intact; existing four fault cases unchanged and green.

## Verification Evidence

- Phase-final battery: `ctest -L Tier1` **12/12** including tier1_static_audit (the audit scanned all newly added test content clean - the hermeticity tripwire holds over the phase's own additions).
- Per-case: all seven new stub cases, both new kit cases (verified in the LocalBlockStore instantiation; green across memory/local/s3 via their suite passes), both store cases, and the drainer case individually OK.
- Layer discipline: no CidOf in the transport suite (git grep gate); taxonomy asserted via mapper OUTCOMES only.

## Deviations from Plan

**[Rule 1 - Build fix] Fuzzy header edit dropped the ClearFaults declaration** — Found during: Task 1 build | Issue: the multi-edit's whitespace-tolerant match consumed the ClearFaults declaration from InMemoryS3Client.hpp (C2039 at compile) | Fix: re-inserted the declaration (now documenting that ClearFaults clears BOTH tables) | Files: thirdparty/sgns-blockstore/src/InMemoryS3Client.hpp | Verification: build green, both suites 100% | Commit: 3e8bbe7 (fixed before commit, same atomic commit)

**[Rule 1 - Test bug] Cross-container iterator pair in the never-deleted assertion** — Found during: Task 1 test run (MSVC debug assertion "vector iterators in range are from different containers") | Issue: `fake_->ObjectKeys().begin()` and `fake_->ObjectKeys().end()` were two separate calls returning two distinct temporary vectors | Fix: bind one `const auto keys = fake_->ObjectKeys();` and build the set from its iterators | Files: thirdparty/sgns-blockstore/test/s3_block_store_test.cpp | Verification: both new cases pass individually | Commit: 3e8bbe7 (fixed before commit, same atomic commit)

**Total deviations:** 2 auto-fixed (both Rule 1, both caught by this phase's own gates before commit). **Impact:** none - all D-05..D-12 truths hold as written.

## Self-Check: PASSED

- All tasks executed and committed individually
- SUMMARY created in the plan directory
- Acceptance criteria re-verified green (stub breadth + kit cases per-case, containment/token/layer gates, phase-final -L Tier1 battery incl. the audit)
