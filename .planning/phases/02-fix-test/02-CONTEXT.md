# Phase 2: Fix & Test - Context

**Gathered:** 2026-07-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply synchronization fixes to all 10 findings identified in the Phase 1 CONCURRENCY-MAP.md audit, write GTest concurrent stress tests covering every finding-aligned race scenario, and document the Bitswap concurrency model. Requirements covered: FIX-01, FIX-02, FIX-03, FIX-04, DOCS-01. TEST-02 is also in scope (GTest stress tests, located in SuperGenius test tree).

FIX-05 (benchmarks), TEST-01 (TSAN build config), TEST-03 (TSAN-clean verification), and DOCS-03 (TSAN suppression file) are **deferred** — the monolithic thirdparty build makes TSAN platform setup impractical at this stage.

</domain>

<decisions>
## Implementation Decisions

### Fix Sequencing & Risk (FIX-01..FIX-04)
- **D-01:** Severity-first ordering: CRITICAL → HIGH → MEDIUM → LOW.
- **D-02:** Within the HIGH tier, simple/standalone fixes first: C-2 (config → atomics) and C-4 (remove const from GetBlock) before C-3 (detached threads → io_context::post) and C-5 (ContentRequestContext strand violation).
- **D-03:** Full sequenced order: C-1 → C-2 → C-4 → C-3 → C-5 → C-6/C-7/C-8/C-9 → C-10.

### Detached Thread Replacement (FIX-01, FIX-04)
- **D-04:** Replace `std::thread(...).detach()` in PublishFile() and PublishDirectory() with `boost::asio::post(context_, ...)` targeting Bitswap's existing io_context.
- **D-05:** Preserve the PublishCallback parameter — callback now fires on io_context instead of detached thread. Document as a threading contract change for Phase 3 consumers.

### Test Organization & Scope (TEST-02)
- **D-06:** Tests live in `SuperGenius/test/src/bitswap/` — reuse existing GTest macros (EXPECT_OUTCOME_TRUE, literals), CMake addtest() infrastructure, and existing Bitswap link dependency.
- **D-07:** One test fixture per finding — all finding-aligned scenarios (~7-8 fixtures) covering: wantlist race, publish race, callback interleaving, content request race, provider race, config race, cache dir race.
- **D-08:** Multi-threaded stress test style — spawn N threads hammering Bitswap ops concurrently for M iterations, check invariants (no corruption, no crashes, correct results).

### Deferred Items
- **D-09:** FIX-05 (throughput benchmarks) — skipped. Focus on correctness (data-race-free) first.
- **D-10:** TEST-01 (TSAN build config), TEST-03 (TSAN-clean verification), DOCS-03 (TSAN suppression file) — deferred. Monolithic MSVC thirdparty build makes TSAN platform setup impractical.

### the agent's Discretion
- Mock/fixture strategy for Bitswap tests (how to create a minimal Bitswap instance with mock libp2p host for isolated concurrent testing).
- Exact lock documentation format within code (comments, header annotations, or both).
- Whether `cacheDir_` fix uses mutex or an immutable-post-init pattern.
- Whether `ContentRequestContext` fix uses a mutex or enforces strand confinement through post/dispatch.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Findings (Phase 1 Output — PRIMARY REFERENCE)
- `.planning/phases/01-audit/CONCURRENCY-MAP.md` — Complete thread-safety audit: 10 findings (C-1 through C-10) with severity, category, location, evidence, confidence, and recommended fixes. **This is the definitive list of what needs to be fixed.**
- `.planning/phases/01-audit/01-CONTEXT.md` — Phase 1 decisions (severity scale, finding categories, CONFIRMED/SUSPECTED confidence flag)

### Bitswap Source
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` — Full class definition: 6 mutex domains, member declarations, ContentRequestContext/BitswapRequestContext structs
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` — Full implementation (2098 lines): all lock usage, detached threads (lines 1354-1431), const_cast (line 1492), cacheDir_ access, io_context wiring

### Project Planning Docs
- `.planning/ROADMAP.md` — Phase 2 goal, requirements FIX-01..05 + TEST-01..03 + DOCS-01,DOCS-03, 5 success criteria
- `.planning/REQUIREMENTS.md` — Detailed per-requirement spec for FIX-01 through DOCS-03
- `.planning/PROJECT.md` — Project scope, constraints, coding standard (Ullman braces, PascalCase, m_ prefix), out-of-scope items

### Codebase Maps
- `.planning/codebase/TESTING.md` — GTest framework (~1.14.0), addtest() CMake macro, test directory organization (mirror source tree under SuperGenius/test/src/), custom outcome macros
- `.planning/codebase/ARCHITECTURE.md` — Threading model (Boost.Asio io_context pool, strand-based serialization), component dependencies, Bitswap integration points in SuperGenius
- `.planning/codebase/CONCERNS.md` — Known concerns including recursive mutex in processing_service, debug cout/cerr usage

### Build System
- `thirdparty/build/CommonTargets.CMake` — ipfs-bitswap-cpp build target and dependency chain (any new files must be registered here)
- `SuperGenius/cmake/functions.cmake` — addtest() macro for registering GTest targets

### Consumer Code (for API compatibility awareness)
- `SuperGenius/src/account/GeniusNode.cpp` — Bitswap construction and initialization (write updates if API changes)
- `SuperGenius/src/processing/processing_subtask_queue_accessor_impl.hpp` — Bitswap usage in processing layer
- `SuperGenius/src/processing/processing_service.hpp` — Bitswap usage in processing node

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **6 existing mutex domains** in Bitswap.hpp (mutexBlockStore_, mutexRequestCallbacks_, mutexContentRequests_, mutexActiveStreams_, mutexDiskIndex_, mutexProviders_) — fixes extend existing synchronization, not adding from scratch.
- **GTest test infrastructure** in `SuperGenius/test/` — addtest() CMake macro, EXPECT_OUTCOME_TRUE/ASSERT_OUTCOME_SUCCESS macros, user-defined literals (hex, buffer, hash), FSFixture for filesystem tests.
- **SuperGenius/cmake/functions.cmake** — already has `addtest()` macro and `BUILD_TESTING` option for conditional test compilation.

### Established Patterns
- **Lock scoping:** RAII std::lock_guard, held for minimum scope, released before async callbacks fire. All existing guards follow this — fixes must preserve it.
- **shared_from_this() / weak_from_this():** All async callbacks capture shared_ptr, ensuring object lifetime. The io_context::post fix for detached threads must follow this.
- **Lock ordering:** Only one documented nesting: mutexRequestCallbacks_ → mutexProviders_ (via processReceivedBlocks → markProviderSuccess). No reverse path. Fixes must not introduce new nestings without documenting the order.
- **Stream caching pattern:** activeStreams_ lock released before async write — demonstrates safe lock-release-before-async that other fixes can model.

### Integration Points
- **PublishFile/PublishDirectory:** API entry points used by consumer code. Callback contract preserved (D-05) — consumer code only needs awareness of thread context change, not API surface changes.
- **GetBlock():** const-correctness fix (D-02, C-4) — removing `const` from GetBlock() is a minor API contract change. Consumer code in processing_subtask_queue_accessor_impl.hpp and GeniusNode.cpp may be affected.
- **SetMaxPeerAttempts/SetPeerFailureThreshold:** Config setter methods — converting underlying members to std::atomic (C-2 fix) preserves API surface; setters become atomic stores, readers become atomic loads.

### Pre-Identified Fix Targets (from CONCURRENCY-MAP.md)
- **C-1 (CRITICAL):** `cacheDir_` — 7 access sites, 4 thread contexts, zero protection. Fix: mutex or immutable-post-init.
- **C-2 (HIGH):** `maxPeerAttempts_` / `peerFailureThreshold_` — mixed protection, setters unprotected. Fix: convert to std::atomic.
- **C-3 (HIGH):** Detached threads in PublishFile/PublishDirectory. Fix: io_context::post (D-04).
- **C-4 (HIGH):** GetBlock() const_cast mutates blockStore_. Fix: remove const.
- **C-5 (HIGH):** ContentRequestContext — no sync on context fields. Fix: mutex or strand confinement.
- **C-6 (MEDIUM):** BitswapRequestContext timer race (HandleResponse vs HandleResponseTimeout).
- **C-7 (MEDIUM):** Callback invoked under mutexRequestCallbacks_ lock — re-entrancy deadlock risk.
- **C-8 (MEDIUM):** cleanupStaleProviders() — dead code, never called.
- **C-9 (MEDIUM):** handle() server read loop persistent on libp2p thread — undocumented.
- **C-10 (LOW):** No lock documentation in header — 6 mutexes, zero comments.

</code_context>

<specifics>
## Specific Ideas

The user directed that the focus should be on fixing "potential deadlocks or crashes" — correctness over tooling. The monolithic thirdparty build makes TSAN and WSL impractical, so validation is through code review, manual verification of fix correctness, and GTest stress tests catching regressions in the SuperGenius build.

</specifics>

<deferred>
## Deferred Ideas

- **FIX-05: Throughput benchmarks** — Deferred. Correctness (TSAN-clean/race-free) is the priority. Revisit benchmark when the build system can support instrumented profiling builds.
- **TEST-01: TSAN build configuration for ipfs-bitswap-cpp** — Deferred. Requires Clang/Linux build split from the monolithic MSVC thirdparty build.
- **TEST-03: TSAN-clean test suite with zero data-race reports** — Deferred. Dependent on TEST-01.
- **DOCS-03: TSAN suppression file** — Deferred. Dependent on TEST-01.
- **WSL2 build environment** — Deferred. Setting up an alternate build toolchain for the entire thirdparty dependency graph is impractical for this phase. Consider as a separate infrastructure phase.

</deferred>

---

*Phase: 2-Fix & Test*
*Context gathered: 2026-07-08*
