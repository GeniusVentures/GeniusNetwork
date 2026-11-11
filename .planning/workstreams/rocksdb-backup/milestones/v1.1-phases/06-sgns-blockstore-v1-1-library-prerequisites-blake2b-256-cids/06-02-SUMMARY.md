---
phase: 06-sgns-blockstore-v1-1-library-prerequisites-blake2b-256-cids
plan: "02"
subsystem: infra
tags: [blake2b, cid, multihash, conformance, s3, key-layout, testing]

requires:
  - phase: 06-01 (same phase)
    provides: 3-arg CidOf overload + blake2 link + committed cross-check vector log
provides:
  - All three backend gates accept exactly {sha-256, blake2b-256} (D-01); sha-512 is the pinned rejection exemplar (D-03)
  - All six verify-on-put/get sites branch on the CID's own multihash (D-04)
  - dag-cbor codec token in S3 object keys (display-only; DeriveKey composition unchanged)
  - Conformance kit extended: pinned real-vector roundtrip suite (3x backends), byte-mismatch Corrupt+Caller, blake2b verify-on-get corruption with attribution, mixed sha256+blake2b PutMany, rejection retarget
affects: [06-03 consumer proof, 08 spill-on-write, 09 cold read fallback]

actuals:
  tokens: 15000
  tasks: 1
  commits: 2

tech-stack:
  added: []
  patterns: [branch-on-own-multihash verify (recompute with cid.content_address.getType()), atomic-green coupling of gate widening + test retarget in one commit]

key-files:
  created: []
  modified:
    - thirdparty/sgns-blockstore/src/MemoryBlockStore.cpp
    - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
    - thirdparty/sgns-blockstore/src/S3BlockStore.cpp
    - thirdparty/sgns-blockstore/test/conformance/BlockStoreConformanceTests.hpp
    - thirdparty/sgns-blockstore/test/memory_block_store_test.cpp
    - thirdparty/sgns-blockstore/test/local_block_store_test.cpp
    - thirdparty/sgns-blockstore/test/s3_block_store_test.cpp

key-decisions:
  - "No gate consolidation - one widened gate copy per backend (v1.0 convention); identical new message names the exact accepted set"
  - "Kit fault-corruption mirror asserts generic attribution (!= Caller && != Unknown) per the suite's convention; the S3 Remote variant is pinned s3-specifically via InMemoryS3Client::SetFlipBytesForKey"
  - "MakeBlake2bCid retained as a no-payload gate probe only (fake digest can never round-trip); real vectors ride MakeDagCborBlake2bCid + HexBytes helpers"

patterns-established:
  - "Rejection exemplar: 64-byte fake sha-512 digest (fits kMaxHashLength=127) so the multihash ctor succeeds and the ENTRY GATE is provably the thrower"

requirements-completed: [LIB-01]

coverage:
  - id: D1
    description: "Gates widened at all three backends with identical message; sha-512 throws at all three + PutMany pre-pass + journal tooling"
    requirement: LIB-01
    verification:
      - kind: unit
        ref: "memory/local/s3 tests: *Sha512* / *RejectedHash* cases green (both kit instantiations)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Six verify sites call 3-arg CidOf with cid.content_address.getType()"
    requirement: LIB-01
    verification:
      - kind: command
        ref: "Select-String 'cid.content_address.getType())' across 3 backend files -> exactly 6"
        status: pass
    human_judgment: false
  - id: D3
    description: "Pinned blake2b/DAG_CBOR vectors round-trip Put->Get byte-identical, CID-verified, on Memory/Local/S3 (kit macro, 3x payloads each)"
    requirement: LIB-01
    verification:
      - kind: unit
        ref: "Blake2bDagCborPinnedVectorsRoundTrip green in Memory/Local/S3 conformance instantiations (+ Repeat)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Byte-flip blake2b Put = Corrupt+Caller; corrupted get-verify = Corrupt with per-backend attribution (Memory/Local kit; Remote pinned via SetFlipBytesForKey)"
    requirement: LIB-01
    verification:
      - kind: unit
        ref: "Blake2bPutMismatchedBytesIsCorruptWithCallerSource + Blake2bFaultCorruptDataGetVerifyRejectedCorrupt + S3BlockStoreTest.Blake2bGetCorruptedFetchIsCorruptWithRemoteSource green"
        status: pass
    human_judgment: false
  - id: D5
    description: "dag-cbor token observable in S3 object keys (DagCborKeyLayoutKnownVector) + mixed sha256+blake2b PutMany accepted, sha-512 batch throws before any write"
    requirement: LIB-01
    verification:
      - kind: unit
        ref: "S3BlockStoreTest.DagCborKeyLayoutKnownVector + PutManyMixedSha256AndBlake2bAcceptedAndSha512ThrowsBeforeAnyWrite green on all backends"
        status: pass
      - kind: command
        ref: "grep 'dag-cbor' src/S3BlockStore.cpp -> 1"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-10-22
status: complete
---

# Phase 6 Plan 02: Backend Hash-Gate Widening Summary

**The library now accepts every CID the SuperGenius CRDT DAG produces: gates at all three backends widened to {sha-256, blake2b-256}, six verify sites branch on the CID's own multihash, and the conformance kit proves it with the cross-check-log vectors on every backend.**

## Performance

- **Duration:** ~45 min | **Tasks:** 1 | **Commits:** sgns-blockstore 006e6f7; thirdparty c20be35

## Six-line verify-site grep (plan verification output)

`Select-String 'cid.content_address.getType())'` over `src/{Memory,Local,S3}BlockStore.cpp` → **6 matches** (Put: Memory/Local/S3; Get-verify: Memory/Local/S3). `dag-cbor` in `src/S3BlockStore.cpp` → 1.

## Tier-1 lane result (SC1/SC2/SC3 evidence)

`ctest -L Tier1` → **100% tests passed, 0 failed out of 12** — SC3 proof: every pre-existing v1.0 sha-256 test passes unchanged inside this lane (the retargeted tests are renames, not removals of coverage: blake2b-rejection became sha-512-rejection by design). New-case proof (per-binary gtest filters): all `*Blake2b*`/`*Sha512*`/`*RejectedHash*`/`*PinnedVectors*`/`*Mixed*`/`*DagCbor*`/`*Transitions*` cases `[ OK ]` across memory (incl. `MemoryBlockStoreConformanceRepeat`), local, and s3 binaries — SC1 (vector roundtrips x3 backends) and SC2 (Corrupt attribution: Caller / Memory|Local kit-shape / Remote via `SetFlipBytesForKey`) included.

## Drift vs RESEARCH line anchors

- All six verify-site and three gate anchors accurate within +/-2 lines (Memory 71/108, Local 305/427, S3 124/177; gates 23/35/27).
- RESEARCH Q6's "bafyre..." key-layout example prefix was the cosmetic assumption again — the real pinned key is `v1/blocks/dag-cbor/d3/bafy2bzace...` (fanout 0xd3 = first byte of the a0 digest `d36a...`), asserted in `DagCborKeyLayoutKnownVector`.
- Kit instantiation names: there is a second `MemoryBlockStoreConformanceRepeat` instantiation (adjacency edge self-check) — new kit cases automatically ran there too (4 more green cases).

## Deviations from Plan

**[Rule 1 - implementation detail] Kit compile break, self-inflicted and fixed pre-commit** — Found during: Task 1 build | Issue: (a) a `// nothing written` line comment before the macro continuation backslash spliced past the closing brace (C2246 nested-TEST_F); (b) the kit lacked `content_identifier_codec.hpp` for the new toString assertions | Fix: comment removed; include added | Files: BlockStoreConformanceTests.hpp | Verification: build green, Tier-1 12/12 | Commit: 006e6f7 (single atomic commit - no intermediate broken state was committed).

**Total deviations:** 1 auto-fixed. **Impact:** none; both issues were caught by the build gate before any commit.

## Self-Check: PASSED

- All Task 1 acceptance criteria re-verified post-commit: identical gate message at 3 sites; 6-line grep; byte-flip Corrupt+Caller; stored/fetched corruption attribution per backend; pinned-vector roundtrip green x3 backends; dag-cbor key observable; mixed PutMany atomic + sha-512 pre-write throw; Tier-1 100% with v1.0 suite unchanged; 2-arg CidOf declaration untouched by this plan (this plan's diff contains no Cid.hpp/Cid.cpp change).
- No changes under SuperGenius/ or GeniusSDK/ (the pre-existing root `M SuperGenius` submodule pointer drift predates this phase and was not touched).
