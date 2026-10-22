---
phase: 02-localblockstore-rocksdb-cold-tier
reviewed_at: 2026-10-20
depth: standard
reviewer: inline (Copilot runtime — gsd-code-reviewer contract)
files_reviewed:
  - thirdparty/sgns-blockstore/include/sgns-blockstore/LocalBlockStore.hpp
  - thirdparty/sgns-blockstore/src/LocalBlockStore.cpp
  - thirdparty/sgns-blockstore/include/sgns-blockstore/BlockStoreTooling.hpp
  - thirdparty/sgns-blockstore/test/local_block_store_test.cpp
  - thirdparty/sgns-blockstore/test/local_block_store_crash_test.cpp
  - thirdparty/sgns-blockstore/test/api_hygiene_test.cpp
  - thirdparty/sgns-blockstore/CMakeLists.txt
  - thirdparty/sgns-blockstore/src/CMakeLists.txt
  - thirdparty/sgns-blockstore/cmake/config.cmake.in
  - thirdparty/sgns-blockstore/test/CMakeLists.txt
  - thirdparty/build/CommonTargets.cmake
counts: { critical: 0, warning: 1, info: 3 }
---

# Phase 02 Code Review — LocalBlockStore (RocksDB Cold Tier)

Scope: all source files changed in phase 02 (`git -C thirdparty/sgns-blockstore log 5fd0111..HEAD` plus the thirdparty superproject diff). Standard depth: per-file analysis with C++-specific checks (ownership, lifetime, error paths, API hygiene).

## Summary

No Critical findings. The implementation faithfully follows the locked decisions (D-01..D-10): pimpl confines every `rocksdb::*` symbol to the .cpp (negative grep green over `include/`); every mutation is exactly one `WriteBatch` committed with `sync=true`; the teardown order releases the Windows LOCK; the D-09 self-heal branch is correctly gated off the fault path; error mapping switches on named Status codes only. One Warning-class latent defect (unreachable for current callers) and three Info notes.

## Findings

### CRITICAL — none

### WARNING

**W-1. No post-Close guard on data-path methods** — `LocalBlockStore.hpp/.cpp`
After `Close()` succeeds, `impl_->db_ == nullptr`; every subsequent `Put/Get/Has/GetSize/PutMany/GetPendingUploads/ForEach/MarkUploadedAccepted/MarkUploadedDurable/GetUploadState/EvictLocal` dereferences `impl_->db_` (e.g. `LocalBlockStore.cpp` Get: `impl_->db_->Get(...)`) — null-pointer UB instead of a taxonomy failure. `Close()` is public and idempotent, so a "closed-then-used" call sequence is legal API usage; today no caller does it (tests and the kit destroy stores instead of closing then reusing, fresh store per case), which is why this is latent rather than live. Recommended fix (small, additive): an entry guard returning `BlockStatus{TemporarilyUnavailable, Local, "store is closed"}` (or folding the check into `FaultGate`) on every public method. Defer to a follow-up plan/quick task — adding ten guards mid-phase-close would expand the diff beyond the executed plans.

### INFO

**I-1. Empty-payload Put untested for the local backend** — `test/local_block_store_test.cpp`
The memory suite covers an empty payload (`GetSize == 0`); the local suite does not. `rocksdb::Slice(reinterpret_cast<const char*>(bytes.data()), bytes.size())` with an empty span passes `(nullptr, 0)`, which RocksDB's Slice constructor stores without dereferencing (verified `rocksdb/slice.h`), and `value.size()` reports 0 — behavior should hold, but it is unproven by test. One-line test addition candidate.

**I-2. Double-open LOCK mapping unproven (T-02-05)** — `src/LocalBlockStore.cpp`
The threat register claims a second read-write open of the same directory surfaces as `TemporarilyUnavailable`; `MapStatus`'s default branch does map RocksDB lock/IO failures there, but no test opens the same directory twice concurrently (the crash-suite raw handle runs only after `Close()` released the LOCK). Mitigated by construction, unproven by test.

**I-3. CF-name constants are per-TU `static constexpr const char*`** — `LocalBlockStore.hpp`
`kBlocksColumnFamilyName`/`kUploadJournalColumnFamilyName` have internal linkage per TU; identical values everywhere and used only as strings (as the plan specified), so no ODR issue for current usage — noted in case future code wants to compare addresses or wrap them in typed handles.

## Security Notes

- Message content carries operation context + `Status::ToString()` only — no credentials/paths-with-secrets (P11 convention holds).
- The raw second `rocksdb::DB` handle (corruption forge) exists only in the test binary, which explicitly links `RocksDB::rocksdb`; the installed library's public link surface is unchanged (api_hygiene TU still links exactly sgns-blockstore + p2p::p2p_cid).
- No new external packages; RocksDB/Snappy consumed from git-pinned superbuild artifacts (T-02-SC).
- Conservative journal decoding keeps undecodable records in the pending set (T-02-03) — verified in `JournalRecord::Decode`.

## Verdict

**0 Critical / 1 Warning / 3 Info — advisory, non-blocking.** The Warning is latent with a clean, additive remediation path; none of the findings gate phase completion.
