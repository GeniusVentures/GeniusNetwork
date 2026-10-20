---
phase: 01-blockstore-contract-memory-backend-conformance-kit
plan: 03
subsystem: testing
tags: [conformance-kit, gtest, sfinae, ci-lane, api-guards, hygiene]

requires:
  - phase: 01-02
    provides: frozen contract headers + MemoryBlockStore with FaultController seam
provides:
  - BlockStoreConformanceTests kit — one-macro instantiation (SGNS_BLOCKSTORE_CONFORMANCE_TESTS), 17 cases, fault-seam probing, per-case fresh stores
  - api_hygiene_test — include-everything standalone-consumer TU + C++17 SFINAE shape guards (no delete/List members, EvictLocal placement, tooling separation)
  - header_hygiene_check.cmake — script-mode ctest banning SDK-shaped includes from public headers
  - CI lane — "Run sgns-blockstore tests" ctest step in thirdparty build.yml (Windows/Linux/OSX legs)
affects: [phase-02-local-block-store, phase-04-s3-block-store, phase-05-fault-matrix]

actuals:
  tokens: 4500    # chars/4 over realized diff (~18k chars); plan estimate 36000 ~8x high
  tasks: 3
  commits: 4     # e927f93 (kit), 5fd0111 (guards), 416847f (thirdparty: CI + bump) + root SUMMARY commit

tech-stack:
  added: []
  patterns: [macro-parameterized suite generation, per-case factory stores, SFINAE member-detection guards, CMake script-mode hygiene tests]

key-files:
  created:
    - thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp
    - thirdparty/sgns-blockstore/test/api_hygiene_test.cpp
    - thirdparty/sgns-blockstore/test/header_hygiene_check.cmake
  modified:
    - thirdparty/sgns-blockstore/test/memory_block_store_test.cpp
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
    - thirdparty/.github/workflows/build.yml

key-decisions:
  - "Kit fault-Has assertion written via has_value() so success-false, NotFound failure, and TemporarilyUnavailable-only all fail except the exact expected shape"
  - "FaultCorruptData source asserted generically (never Caller, never Unknown) so the kit stays backend-agnostic; the memory backend's Memory attribution is asserted by Plan-02's own suite"
  - "CI-green recorded as backstop truth per plan must_haves — the local run proves the identical command; an actual workflow run completes the evidence"

patterns-established:
  - "Backend onboarding = one include + one macro line (D-09); dual-instantiation self-check proves symbol non-collision"
  - "Three-mechanic guard set (SFINAE compile-time + link-time TU + script-mode grep) — no single guard can go stale silently"

requirements-completed: [CORE-01, CORE-05, CORE-06, BACK-02]

coverage:
  - id: D1
    description: "Conformance kit instantiable in one macro line, green against MemoryBlockStore (BACK-02)"
    requirement: BACK-02
    verification:
      - kind: unit
        ref: "memory_block_store_test ctest 100% — 15 backend + 2x17 kit cases (dual instantiation); xunit contains MemoryBlockStoreConformance entries; kit absent from install tree (D-12)"
    human_judgment: false
  - id: D2
    description: "API-shape guards: no delete/List members ever, EvictLocal placement, tooling separation, standalone consumer (CORE-05/CORE-06)"
    requirement: CORE-05
    verification:
      - kind: unit
        ref: "api_hygiene_test — static_asserts compiled green (any banned member = build failure); ctest Passed"
    human_judgment: false
  - id: D3
    description: "Header hygiene gate: public headers carry only CID/bytes/strings + std/gsl (CORE-01)"
    requirement: CORE-01
    verification:
      - kind: other
        ref: "header_hygiene ctest — script-mode scan over include/sgns-blockstore/*.hpp passes clean; fails via FATAL_ERROR on any banned include"
    human_judgment: false
  - id: D4
    description: "CI test lane — hermetic ctest step in the thirdparty build workflow (success criterion 4 lane)"
    requirement: CORE-06
    verification:
      - kind: other
        ref: "build.yml:370-373 step verified present; the identical ctest command green locally (4/4 registrations); actual workflow run = backstop truth, not claimable locally"
    human_judgment: true
    rationale: "The completed CI run itself can only be observed on the runner; local command-shape equivalence is the provable part"

duration: 10min
completed: 2026-10-20
status: complete
---

# Phase 1 Plan 03: Conformance Kit + Guards + CI Lane Summary

**The verification instruments shipped: any backend now gets the full 17-case conformance suite in one macro line, the API shape is enforced by compiling guards, and the hermetic suite has its CI lane — 4/4 local registrations green on the exact CI command.**

## Performance

- **Duration:** ~10 min
- **Tasks:** 3/3
- **Files:** 6 (3 created, 3 modified)

## Accomplishments
- `SGNS_BLOCKSTORE_CONFORMANCE_TESTS(SuiteName, factory)`: per-case fresh stores via factory, every generated symbol parameterized on the suite name; 17 cases covering round-trips (incl. empty payload), miss-as-NotFound-failure, Has-false-as-success, GetSize precision, alreadyPresent merge, Corrupt+Caller boundary, D-08 throws, PutMany ordering/no-rollback/pre-validation, and all four fault-seam cases (Unavailable never-NotFound/no-sticky-cache, CorruptData backend-source, Unauthorized distinct-and-non-sticky)
- Seam-absent backends get loud `[fault-conformance]` GTEST_SKIPs (D-10); MemoryBlockStore implements the seam → zero skips
- Dual instantiation (`MemoryBlockStoreConformance` + `MemoryBlockStoreConformanceRepeat`) coexists in one binary — the BACK-02 adjacency self-check
- api_hygiene_test: include-everything TU linking exactly sgns-blockstore + p2p::p2p_cid; std::void_t detection for Remove/Erase/Delete/erase/remove/List/ForEach/Enumerate (all false on BlockStore), EvictLocal false-on-interface/true-on-backend, BlockStoreTooling not a base — all static_asserts compiled green
- header_hygiene_check.cmake: script-mode gate banning ipfs_lite/ipfs, SuperGenius, GeniusSDK, GeniusWallet, minio includes from public headers — shell-independent, CI-ready
- build.yml: "Run sgns-blockstore tests" ctest step after Build thirdparty, gated to Windows/Linux/OSX legs (iOS/Android cross-builds excluded by design)

## Task Commits

1. **Task 1: conformance kit** — `e927f93` (test, sgns-blockstore repo)
2. **Task 2: guards** — `5fd0111` (test, sgns-blockstore repo)
3. **Task 3: CI lane + gitlink bump** — `416847f` (ci, thirdparty superproject)

**Plan metadata:** root-repo commit (this SUMMARY + tracking + thirdparty pointer)

## Decisions Made
- Fault-Has assertion via `has_value()` so exactly one outcome shape passes (see key-decisions)
- CI-green is the plan's declared backstop truth — the local run proves command-shape equivalence only

## Deviations from Plan

None - plan executed exactly as written (one in-flight typo `0x b2` fixed before first compile; not a deviation).

## Authentication Gates

None encountered.

## Self-Check: PASSED

- Task 1: kit green (100% ctest, xunit contains kit suites, kit not installed)
- Task 2: both guards green; static_asserts compiled
- Task 3: step present at build.yml:370; full local suite 4/4 green with the CI command shape
- Phase-level gate: one ctest invocation over the sub-build runs all four registrations green, zero network
