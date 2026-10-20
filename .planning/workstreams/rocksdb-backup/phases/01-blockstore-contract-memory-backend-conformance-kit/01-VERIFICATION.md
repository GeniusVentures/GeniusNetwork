---
phase: 01-blockstore-contract-memory-backend-conformance-kit
verified: 2026-10-20
verifier: inline (execute-phase verify_phase_goal gate)
goal: "The sgns-blockstore library exists as a buildable/installable thirdparty target whose public contract is frozen and proven — the retrofit-brutal type-system and API-shape decisions land before any real backend exists"
status: passed
requirements_verified: 9/9
must_haves_score: 5/5
backstop_items:
  - "Actual CI workflow run of the new 'Run sgns-blockstore tests' step (local command-shape equivalence proven; run observable only after push — plan declared this a backstop truth)"
---

# Phase 1 Verification

**Goal check:** `sgns-blockstore` exists as a buildable/installable thirdparty target (superbuild ExternalProject, install tree with lib + 10 public headers + package config) and its public contract is frozen (8 contract headers + Cid.hpp, compile-firewall anchor, one structural documented deviation: result alias with policy::terminate) and proven (32 backend/kit test cases + spike + guards, all green). VERIFIED.

**Requirements:** CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, BACK-01, BACK-02, BUILD-01 — all marked complete in REQUIREMENTS.md with evidence below. 9/9 accounted.

## Success Criteria

| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| 1 | Builds through superbuild; installs headers that compile standalone with only CID/bytes/strings | PASS | `cmake --build ... --target sgns-blockstore` green (Task 2, 01-01); install tree `lib/sgns-blockstore.lib` + `include/sgns-blockstore/*.hpp` (10 headers); `api_hygiene_test` = the compiled consumer TU including every installed header, linked against exactly sgns-blockstore + p2p::p2p_cid (ctest Passed); `header_hygiene` script gate passes clean on all public headers (no SuperGenius/GeniusSDK/GeniusWallet/ipfs_lite/minio includes) |
| 2 | Put/Get/Has/GetSize with structured results; miss = NotFound; induced failure = TemporarilyUnavailable/Corrupt/Unauthorized; never conflated | PASS | `memory_block_store_test` 15/15 + kit fault cases green (xunit failures="0"): miss → NotFound failure; Unavailable → failures with Has.has_value()==false asserted; Unauthorized distinct (never NotFound/TemporarilyUnavailable); no sticky negative cache after clear |
| 3 | Bytes not hashing to CID rejected as Corrupt with source attribution, kit-proven | PASS | kit `PutMismatchedBytesIsCorruptWithCallerSource` (source == Caller) and `FaultCorruptDataRejectedCorruptWithBackendSource` (source != Caller, backend-side) both green against MemoryBlockStore |
| 4 | Conformance kit one-step instantiable, green vs MemoryBlockStore in CI (hermetic) | PASS (local) + backstop (CI run) | One macro line per suite (`SGNS_BLOCKSTORE_CONFORMANCE_TESTS`), dual instantiation green in one binary; suite hermetic (no network); CI lane step exists in build.yml (Win/Linux/OSX) and the identical ctest command is green locally (4/4 registrations). The completed workflow run itself is the declared backstop truth — observable only after push |
| 5 | API shape verifiably safe: no delete-shaped method; EvictLocal local-only asserted; enumeration only on the tooling interface | PASS | `api_hygiene_test` static_asserts compiled green: Remove/Erase/Delete/erase/remove/List/ForEach/Enumerate absent on BlockStore (build-breaking if added), EvictLocal false-on-interface/true-on-MemoryBlockStore, BlockStoreTooling not a base; plus the declaration-shaped grep gate on BlockStore.hpp |

## Notes

- One structural deviation from the plans' spelled signatures: library-local `result<T, BlockStatus>` alias with `policy::terminate` (boost's default policy cannot instantiate for a struct error type). Shape and failure-slot semantics preserved; documented in Cid.hpp, STATE.md decisions, and 01-02-SUMMARY.
- Known-vector correction (position 33 `y` not `w`) verified against an independent from-scratch base32 computation.
- Code review (advisory): 0 critical / 0 major / 4 minor / 2 info — disposition in `01-REVIEW-DISPOSITION.md`, none blocking.

**Verdict: passed.**
