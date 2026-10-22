---
phase: 01-blockstore-contract-memory-backend-conformance-kit
plan: 02
subsystem: api
tags: [contract-freeze, blockstore, memory-backend, outcome, taxonomy, fault-injection]

requires:
  - phase: 01-01
    provides: sgns-blockstore repo skeleton + superbuild target + CidOf/Cid alias (p2p_cid adopted)
provides:
  - Frozen v1.0.0 public header set (8 new headers) + ContractHeaders.cpp compile-firewall anchor
  - Full type system: StatusClass/BlockSource/BlockStatus, Block/BlockInput, ReadOptions/WriteOptions, DurabilityLevel/PutOutcome, BlockStoreCapabilities
  - List-free delete-free BlockStore interface (Put/Get/Has/GetSize/PutMany) with all contract documentation
  - BlockStoreTooling ForEach-only audit surface + ordering contract
  - FaultController public seam (FaultKind + SetFault/GetFault)
  - MemoryBlockStore hermetic reference backend with verify-at-facade + 15/15 green behavior suite
affects: [01-03-conformance-kit, phase-02-local-block-store, phase-05-fault-matrix]

actuals:
  tokens: 11000   # chars/4 over realized diff (~43.3k chars added); plan estimate 42000 was ~4x high
  tasks: 2
  commits: 4     # 8f8b66b (headers), 667cd6c (RED), f484b71 (GREEN) + root SUMMARY commit

tech-stack:
  added: []
  patterns: [verify-at-facade single shared gate, library-local result<T,BlockStatus> alias with policy::terminate, dual public inheritance for dynamic_pointer_cast probing]

key-files:
  created:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStatus.hpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/Block.hpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/Options.hpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/Durability.hpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/Capabilities.hpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStore.hpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStoreTooling.hpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/FaultController.hpp
    - thirdparty/sgns-blockstore/src/ContractHeaders.cpp
    - thirdparty/sgns-blockstore/include/sgns-blockstore/MemoryBlockStore.hpp
    - thirdparty/sgns-blockstore/src/MemoryBlockStore.cpp
    - thirdparty/sgns-blockstore/test/memory_block_store_test.cpp
  modified:
    - thirdparty/sgns-blockstore/include/sgns-blockstore/Cid.hpp
    - thirdparty/sgns-blockstore/src/CMakeLists.txt
    - thirdparty/sgns-blockstore/test/CMakeLists.txt

key-decisions:
  - "Result-envelope policy: library-local result<T, BlockStatus> alias with policy::terminate - boost default_policy resolves exception_ptr_rethrow observers for struct error types, which cannot instantiate for BlockStatus; D-01's envelope shape (result<T,BlockStatus>) is preserved and the deviation is documented in Cid.hpp"
  - "CidOf (1-arg result, std::error_code error) failures are mapped explicitly at the facade - never OUTCOME_TRY'd across the BlockStatus-typed envelope (mismatched error types)"
  - "The D-08 entry gate applies to every public op (Put/Get/Has/GetSize/PutMany): non-sha256 multihash throws std::invalid_argument before any mutation"
  - "PutMany outer envelope reserved for wholesale malfunction (fault gate); per-element results for everything else (research Q4 resolution made executable)"

patterns-established:
  - "Verify-at-facade: one shared ValidateCidHash gate + verification at the backend's shared path - never per-call-site, never #ifdef'd out"
  - "FaultGate: Unavailable/Unauthorized return pre-storage failures so Has NEVER surfaces false under fault (CORE-02 non-conflation)"

requirements-completed: [CORE-02, CORE-03, CORE-04, BACK-01]

coverage:
  - id: D1
    description: "Frozen v1.0.0 contract header set compiling as one unit (compile-firewall anchor)"
    requirement: CORE-03
    verification:
      - kind: other
        ref: "cmake --build sub-build (Task 1) - ContractHeaders.cpp compiles all nine headers; interface-clean grep gate passed (no Remove/Erase/Delete/List/Enumerate declarations)"
    human_judgment: false
  - id: D2
    description: "MemoryBlockStore behavior suite - taxonomy non-conflation, verification attribution, D-08 throw, EvictLocal, PutMany, faults (BACK-01/CORE-02/CORE-04)"
    requirement: BACK-01
    verification:
      - kind: unit
        ref: "thirdparty/sgns-blockstore/test/memory_block_store_test.cpp - 15/15 TEST_F green (xunit tests=15 failures=0); cid_spike_test regression green"
    human_judgment: false

duration: 15min
completed: 2026-10-20
status: complete
---

# Phase 1 Plan 02: Contract Freeze + MemoryBlockStore Summary

**The published v1.0.0 contract is frozen as a compiling unit (8 headers + anchor) and MemoryBlockStore proves every taxonomy/verification claim executable — 15/15 behavior tests green with the spike regression intact.**

## Performance

- **Duration:** ~15 min (execution proper)
- **Tasks:** 2/2 (TDD: RED `667cd6c` → GREEN `f484b71`, headers `8f8b66b`)
- **Files:** 14 (12 created, 2 modified)

## Accomplishments
- Frozen type system exactly per D-02/D-03/D-13/D-15: StatusClass (4 members, Found = success slot), BlockSource (6 members incl. Caller), BlockStatus rich struct, Block/BlockInput, ReadOptions (verify=true default)/WriteOptions, 4-value DurabilityLevel + PutOutcome, BlockStoreCapabilities
- BlockStore interface: exactly Put/Get/Has/GetSize/PutMany with the verbatim eviction-invariant quote, D-14 no-atomicity + results[i] ordering, D-08 std::invalid_argument contract, blake2b boundary, CORE-05/CORE-06 permanence note — verified by the declaration-shaped grep gate
- BlockStoreTooling ForEach-only surface with lexicographic encoded-CID-byte snapshot ordering contract; FaultController public seam (FaultKind incl. Unauthorized for in-phase taxonomy proof)
- MemoryBlockStore: dual public inheritance (FaultController probe test green), std::map operator< keying, single-threaded v1 contract documented, EvictLocal idempotent, verify-at-facade with Caller/Memory attribution, PutMany pre-validation + no-rollback

## Task Commits

1. **Task 1: contract headers + anchor** — `8f8b66b` (feat)
2. **Task 2 (TDD): RED suite** — `667cd6c` (test)
3. **Task 2 (TDD): GREEN backend** — `f484b71` (feat, includes the result-policy fix + signature repoint)

**Plan metadata:** root-repo commit (this SUMMARY + tracking + thirdparty pointer)

## Decisions Made
- Result-envelope policy::terminate alias (see key-decisions) — the one structural deviation from the plan's spelled `outcome::result<T, BlockStatus>` text; shape and semantics preserved, documented in-header
- Requirements CORE-01/CORE-05 remain open pending 01-03 (shared-ID gate)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Result-envelope policy could not instantiate for BlockStatus**
- **Found during:** Task 2 GREEN build
- **Issue:** boost default_policy resolves exception_ptr_rethrow observers for struct error types; no std::exception_ptr construction exists for BlockStatus → class instantiation fails
- **Fix:** library-local `result<R, S, policy::terminate>` alias in Cid.hpp; all signatures repointed (`result<PutOutcome, BlockStatus>` etc.)
- **Files:** Cid.hpp, BlockStore.hpp, BlockStoreTooling.hpp, MemoryBlockStore.hpp/.cpp
- **Verification:** full build + 15/15 tests green
- **Commit:** f484b71

**2. [Rule 1 - Bug] CidOf error type not TRY-able across the BlockStatus envelope**
- **Found during:** Task 2 GREEN build
- **Issue:** OUTCOME_TRY propagates failure_type<std::error_code> into result<_, BlockStatus> — incompatible error types
- **Fix:** explicit `if (!computed)` mapping (Corrupt+Caller on Put, Corrupt+Memory on Get)
- **Files:** src/MemoryBlockStore.cpp
- **Verification:** build green
- **Commit:** f484b71

**3. [Rule 1 - Bug] Fixture default-constructibility**
- **Found during:** Task 2 build
- **Issue:** ContentIdentifier has no default constructor → `Cid cid_a_;` members deleted the TEST_F default ctor
- **Fix:** member-initializers + static MakeCid helper (declaration order preserved)
- **Files:** test/memory_block_store_test.cpp
- **Commit:** f484b71

**4. [Rule 1 - Bug] Has(bad-cid) throws outside EXPECT_THROW**
- **Found during:** Task 2 test run
- **Issue:** the D-08 gate validates every op, so Has(blake2b-cid) throws — the test called it bare expecting a false value
- **Fix:** wrapped in EXPECT_THROW (strengthens: every-op gate is now asserted)
- **Commit:** f484b71

**5. [Rule 1 - Bug] MSVC debug abort on span-iterator vector temporaries in EXPECT_EQ**
- **Found during:** Task 2 test run
- **Issue:** `std::vector<uint8_t>(span.begin(), span.end())` built from a temporary gsl::span inside EXPECT_EQ hard-aborted under MSVC debug STL (bisected by test trimming)
- **Fix:** vector constructed from string iterators instead
- **Commit:** f484b71

**Total deviations:** 5 auto-fixed (all Rule 1). **Impact:** one structural (policy alias, documented in-header and in STATE decisions); the frozen decision set D-01..D-16 is otherwise untouched.

## Authentication Gates

None encountered.

## Self-Check: PASSED

- Task 1 acceptance verified (9 headers + anchor compile; interface-clean grep; verbatim criteria greps passed)
- Task 2: 15/15 TEST_F green, xunit failures="0", spike regression green, binary in test_bin/, install tree refreshed
- TDD sequence RED (667cd6c, non-compiling suite) → GREEN (f484b71) preserved in history
- Ready for 01-03 (kit instantiates against MemoryBlockStore + FaultController probe)
