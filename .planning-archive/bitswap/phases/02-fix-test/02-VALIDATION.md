---
phase: 2
slug: fix-test
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-08
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | GTest ~1.14.0 via SuperGenius cmake/functions.cmake addtest() |
| **Config file** | SuperGenius/test/src/bitswap/CMakeLists.txt |
| **Quick run command** | `ctest -R concurrency_cache_dir_test --output-on-failure` |
| **Full suite command** | `ctest -R concurrency_.*_test --output-on-failure` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `ctest -R <test_name> --output-on-failure`
- **After every plan wave:** Run `ctest -R concurrency_.*_test --output-on-failure`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|--------|
| 02-01-01 | 01 | 1 | FIX-01 | C-1 | cacheDir_ protected by mutex, no data race | unit | `ctest -R concurrency_cache_dir_test` | ⬜ pending |
| 02-01-02 | 01 | 1 | FIX-02 | C-2 | Config setters are atomic, no torn reads | unit | `ctest -R concurrency_config_test` | ⬜ pending |
| 02-01-03 | 01 | 1 | FIX-02 | C-4 | GetBlock() no longer const, no const_cast | unit | `ctest -R concurrency_get_block_test` | ⬜ pending |
| 02-01-04 | 01 | 1 | FIX-01, FIX-04 | C-3 | PublishFile/PublishDirectory use io_context::post | unit | `ctest -R concurrency_publish_test` | ⬜ pending |
| 02-02-01 | 02 | 2 | FIX-01, FIX-04 | C-5 | ContentRequestContext strand-confined, no race | unit | `ctest -R concurrency_content_request_test` | ⬜ pending |
| 02-02-02 | 02 | 2 | FIX-02 | C-6 | BitswapRequestContext timer-safe, no race | unit | `ctest -R concurrency_request_context_test` | ⬜ pending |
| 02-02-03 | 02 | 2 | FIX-02 | C-7 | Callbacks not invoked under mutex, no deadlock | unit | `ctest -R concurrency_callback_test` | ⬜ pending |
| 02-03-01 | 03 | 3 | DOCS-01 | C-8,C-9,C-10 | Dead code removed, thread contracts documented | manual | grep verification (see RESEARCH.md §4.2) | ⬜ pending |
| 02-03-02 | 03 | 3 | TEST-02 | — | Combined stress test passes, no crashes | integration | `ctest -R concurrency_stress_test` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `SuperGenius/test/src/bitswap/stubs.hpp` — StubHost, StubRouter declarations
- [ ] `SuperGenius/test/src/bitswap/stubs.cpp` — StubHost, StubRouter implementations
- [ ] `SuperGenius/test/src/bitswap/CMakeLists.txt` — Test target registration
- [ ] `SuperGenius/test/src/CMakeLists.txt` — `add_subdirectory(bitswap)` line

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Lock documentation completeness | DOCS-01 | All 6 existing mutexes + 1 new mutexCacheDir_ must have Doxygen blocks; no automated check for comment quality | `rg 'mutex' thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp -n` — verify every mutex/find_group has Doxygen |
| Strand confinement audit (C-5) | FIX-04 | Complex call graph through libp2p → Bitswap boundary; automated test can detect crashes but not prove all paths dispatched | Verify 3 entry points in RESEARCH.md §C-5 have dispatch wrappers |
| Dead code removal (C-8) | FIX-02 | Binary check: if method removed, no linker errors for consumers | `rg 'cleanupStaleProviders' --include='*.hpp' --include='*.cpp' -n` — zero results |
| const_cast elimination (C-4) | FIX-02 | Should be caught by grep, but runtime verification needed for correctness | `rg 'const_cast' thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp -n` — zero results |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or manual verification
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all missing references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
