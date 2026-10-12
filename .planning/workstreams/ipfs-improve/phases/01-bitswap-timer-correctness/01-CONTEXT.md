# Phase 1: Bitswap Timer Correctness - Context

**Gathered:** 2026-10-12
**Status:** Ready for planning

<domain>
## Phase Boundary

A canceled Bitswap block-request timer is treated as canceled — never as a timeout — and every block request yields exactly one terminal result, proven by deterministic race-ordering regression tests on a single-threaded `io_context`. The fix lands on a branch cut from ipfs-bitswap-cpp `d2ec18af` (the integrated SHA). Scope is `BitswapRequestContext` in `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` only — `ContentRequestContext` is the port source, not a fix target.

</domain>

<decisions>
## Implementation Decisions

### Timeout Injection Seam
- **D-01:** Constructor default parameter — `BitswapRequestContext(boost::asio::io_context&, boost::posix_time::time_duration = boost::posix_time::seconds(5))`. Production call sites are unchanged (default applies); tests construct the context directly with millisecond-class durations. Mirrors how `ContentRequestContext` keeps its duration as a ctor-initialized member. — **Reversibility:** reversible — additive default parameter, no call-site changes.
- **D-02:** Duration-only injection — the real `boost::asio::deadline_timer` stays; no timer abstraction, factory, or mock type enters the production header. Determinism comes from tiny injected durations plus controlled stepping of a single-threaded `io_context` (`poll()`/`run_one()` ordering). — **Reversibility:** reversible — no production abstraction to unwind.

### Test Harness Location
- **D-03:** The four race-ordering tests live in ipfs-bitswap-cpp's own test suite (new test file under `thirdparty/ipfs-bitswap-cpp/test/`), shipping on the fix branch — self-contained upstream contribution and a Phase-4 content-probe marker in the same submodule as the fix. **Research MUST verify this suite actually builds and runs on Windows in this workspace** (its test CMake is not wired into the thirdparty build); the AsyncIOManager test suite (`thirdparty/AsyncIOManager/test/`) is the documented fallback path if it cannot.

### Phase Boundary (P1 ↔ P2)
- **D-04:** Restructure `HandleResponse` once in Phase 1 — the full in-file port: under lock (completion-flag check, explicit `.cancel()`, callbacks moved out, request marked complete), outside lock (invoke callbacks). This is the exact `ContentRequestContext` shape at bitswap.cpp:575-600. Phase 2 then owns the reentrancy guarantees (context kept alive via `shared_from_this()` during dispatch, cancel-own-request-from-callback), the TEST-01 extension, and BSTP-04 verification — Phase 2 still verifies the move-out even though the code lands in Phase 1. Rationale: two sequential fork branches rewriting the same ten lines creates avoidable merge friction on the branch chain Phase 4 pins. — **Reversibility:** reversible — single-function restructure.

### Fix Scope and Error Semantics
- **D-05:** `BitswapRequestContext` only. `ContentRequestContext`'s residual races (see Deferred Ideas) are explicitly out of scope. — **Reversibility:** reversible — scope declaration, no code.
- **D-06:** The genuine-timeout path maps to the existing `BitswapError::REQUEST_TIMEOUT` (bitswap.hpp:94-106). The current `HandleResponseTimeout` → `OUTBOUND_STREAM_FAILURE` mapping (bitswap.cpp:91-94) is wrong and switches to an existing enum value — no public-header change, no new enum entry. — **Reversibility:** reversible — consumers already compile against the full enum.

### the agent's Discretion
- Fork-branch naming for the ipfs-bitswap-cpp branch cut from `d2ec18af` (Phase 4 records the final pins by content probe)
- Exact race-test file name and GTest case naming within the ipfs-bitswap-cpp suite
- `io_context` stepping mechanics (`poll()` vs `run_one()`) used to realize the four orderings, as long as no sleeps are introduced

### Folded Todos
None — the single todo match (Vulkan capability-probe deadlock, score 0.2) was a spurious keyword match and was reviewed, not folded.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning artifacts
- `.planning/workstreams/ipfs-improve/REQUIREMENTS.md` — BSTP-01..03 definitions (the WHAT for this phase)
- `.planning/workstreams/ipfs-improve/ROADMAP.md` §Phase Details → Phase 1 — success criteria SC1-SC4 (cancel semantics, single terminal result, error semantics, deterministic race tests)
- `.planning/workstreams/ipfs-improve/STATE.md` — pinned SHAs (ipfs-bitswap-cpp `d2ec18af`) and the flagged timeout-injection blocker this context resolves

### Audit origin
- `.planning/research/gnus_libp2p_comparison.md` §Bitswap → Source-review concerns — the P0 finding: "Canceled timers treated as timeouts" (bitswap.cpp:70-99); notes these are source-level concerns to verify against the integrated commit

### Source of truth for the fix
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` L65-95 — the broken `BitswapRequestContext` (ec-ignoring `async_wait` lambda, `expires_at(pos_infin)` disarm, no completion flag)
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` L568-600 — `ContentRequestContext` timeout handler: the in-file C-5+C-7 pattern to port (`if (ec) return;`, `timedOut` flag under `mutexContentRequests_`, callback moved out and invoked outside the lock)
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` L925-940 — `checkContentRequestComplete`: explicit `ctx->timeout.cancel()` precedent; also the residual race being deferred (see Deferred Ideas)
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` L94-106 — `BitswapError` enum (`REQUEST_TIMEOUT` already exists); L108-128 — `BitswapRequestContext` class declaration and the `mutex_` contract comment (note `AddCallback` is called under outer `mutexRequestCallbacks_` in `messageSent`)

### Test wiring
- `thirdparty/ipfs-bitswap-cpp/test/bitswap_server_client_test.cpp` — existing suite pattern the new race-test file follows
- `thirdparty/AsyncIOManager/test/testutil/bitswap_node.hpp` — fallback harness fixture (full libp2p host + bitswap wrapper) if the ipfs-bitswap-cpp suite cannot build on Windows
- `.planning/codebase/TESTING.md` — verification convention: build/test inside the existing `build/<Platform>/<Config>` tree; thirdparty components build via cmake before SuperGenius consumes them

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ContentRequestContext` timeout handler (bitswap.cpp:575-600): the exact porting template — ec check, completion flag under lock, callback extraction, dispatch outside lock
- The `shared_from_this()` timer capture already landed at `d2ec18af` (bitswap.cpp:78-84): the armed timer keeps the context alive; this fix builds on it, does not replace it
- ipfs-bitswap-cpp test suite CMake + GTest wiring (`test/CMakeLists.txt`, `test/src/`) — the new race-test file plugs in here

### Established Patterns
- `std::mutex`-guarded context state with an outer request-map mutex (`mutexRequestCallbacks_` in `messageSent`) — the completion flag must be checked under `mutex_`, and the restructure must not assume `HandleResponse` callers hold other locks
- `boost::asio::deadline_timer` + `boost::posix_time` durations throughout this file — the injection seam (D-01) stays in that idiom

### Integration Points
- `Bitswap::RequestBlock`/`RequestBlocks` create `BitswapRequestContext`s into `requestContexts_`; `processReceivedBlocks` dispatches responses into `HandleResponse`; `messageSent` arms timers via `AddCallback`
- Phase 4 repins the thirdparty submodule pins by content probe — fix markers (and the race tests, per D-03) must be present at the pinned commit

</code_context>

<specifics>
## Specific Ideas

- The four orderings (SC4): cancel-vs-expiry in both orders, response-then-canceled-timer-fires (no failure after success), timeout-then-late-response (no double callback) — driven with tiny injected durations and stepped `io_context`, never sleeps
- The ordering the completion flag must survive: an already-dequeued, genuinely-expired handler firing late with success after a cancel (ROADMAP SC2) — exactly one terminal result regardless
- Error semantics switch is one-directional: genuine timeout → `REQUEST_TIMEOUT`; consumer cancel and success → no error callback at all (BSTP-03)

</specifics>

<deferred>
## Deferred Ideas

- **ContentRequestContext hardening** — `checkContentRequestComplete` (bitswap.cpp:925-940) reads `ctx->timedOut` and invokes `ctx->callback` outside `mutexContentRequests_`, a residual race with the locked timeout handler (possible success/timeout double-fire in a narrow window). Source-level concern, not a reproduced runtime failure, and outside BSTP-01..03. Candidate for a v2 fix on its own branch.
- **TEST-01 full race suite extension** — reentrant-callback-cancels-own-request and the callback-move-out verification belong to Phase 2 per D-04's split.

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-...md`) — matched Phase 1 only on the keyword "path" (score 0.2); unrelated to Bitswap timers; left for its natural owner.

</deferred>

---

*Phase: 1-Bitswap Timer Correctness*
