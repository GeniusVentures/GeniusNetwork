# Phase 2: Bitswap Callback Reentrancy - Context

**Gathered:** 2026-10-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Consumer callbacks are safe to call from — Bitswap never invokes them under an internal mutex, and a re-entrant consumer (cancel its own request, chain new requests) cannot deadlock the protocol or trigger use-after-free. The C-7 move-out shape landed in Phase 1 inside `HandleResponse`; Phase 2 owns the outer integration (request-map erase-under-lock/dispatch-after, `messageSent` arming, `processReceivedBlocks`), the reentrancy guarantees (`shared_from_this()` lifetime during dispatch), late-registration semantics (SC3), and the TEST-01 extension — the full race-ordering regression suite green on the single-branch chain `dev_timer_correctness` (HEAD `e2dc906`, cut from `d2ec18af`). Scope is the block-request paths only; `ContentRequestContext` fixes remain deferred to v2 (D-05 carry-forward), with a read-only dispatch-site inventory as evidence.

**Carry-forward from Phase 1 (locked — do not re-litigate):**
- D-01/D-02: duration-only timeout injection via defaulted ctor param; no timer abstraction/mock in production headers
- D-03: race tests live in ipfs-bitswap-cpp's own test suite — proven to build and run green on Windows (`bitswap_request_timer_race_test.cpp`, 7 cases, ctest-registered)
- D-04: the under-lock move-out / after-unlock dispatch restructure of `HandleResponse` already landed in Phase 1; Phase 2 verifies and extends it
- D-05: `ContentRequestContext` out of fix scope
- D-06/BSTP-03: genuine timeout → exactly one `REQUEST_TIMEOUT`; consumer cancel and success → no error callback

</domain>

<decisions>
## Implementation Decisions

### Late-registration semantics (SC3)
- **D-01:** Replay terminal result — a request that reached terminal state remembers its outcome (success blocks or error code); a callback registered afterwards is invoked with the stored result. Consumers never silently miss a result. — **Reversibility:** reversible — fork-internal consumer contract; no external published API beyond SuperGenius/GeniusSDK builds.
- **D-02:** Replay runs synchronously at registration — the callback fires before `AddCallback` returns, invoked after any held mutex (including the outer `mutexRequestCallbacks_` in `messageSent`) is released. Matches SC3's "immediately"; the registering caller tolerates its callback running on its own stack — the same reentrancy guarantee BSTP-05 gives consumers.
- **D-03:** Both outcomes are replayable — symmetric contract: a late subscriber to a timed-out request receives the stored `REQUEST_TIMEOUT` error exactly as an on-time subscriber would; a late subscriber to a completed request receives the stored blocks.
- **D-04:** Completed entries are retained until replaced — the completed request stays in `requestContexts_` marked complete (timer disarmed, no fresh timer ever armed on it per SC3), and is replaced when a new request for the same CID arrives. No sweep machinery, no retention timers; map size bounded by distinct requested CIDs. — **Reversibility:** reversible — map-lifecycle policy internal to bitswap.cpp.

### Reentrancy test breadth (BSTP-05 / TEST-01)
- **D-05:** Both flavors get deterministic tests — (a) a callback cancels its own request inline: no deadlock, no UAF, exactly the BSTP-03 outcome semantics; (b) a callback issues a new block request that then completes: chaining works and the new request's callback fires. Nested depth-2 reentrancy was considered and not selected.
- **D-06:** "Without deadlock" is a bounded-step assertion — after driving the reentrant scenario, the test asserts the `io_context` drains (`poll()==0`) and all expected handlers ran within a bounded number of steps. A lock inversion becomes a red, diagnosable assertion; no wall-clock sleeps, no hang-until-CI-timeout.
- **D-07:** UAF evidence = ASan run in WSL — Windows MSVC ASan is painful to build (user experience); instead build and run the race suite under ASan in WSL at `~/gnus/GeniusNetwork/thirdparty`. **NO git inside WSL** (SSH passphrase has never worked there) — the fix-branch source is synced Windows→WSL as file copies (throwaway), and every git operation (branch, commit, probe) stays on the Windows side. The Windows deterministic suite remains the primary acceptance evidence; the WSL ASan run is supplementary UAF evidence. — **Reversibility:** reversible — evidence-only; no production or build-tree change mandated.
- **D-08:** One cross-test covers the SC3×BSTP-05 collision — a live callback reentrantly registers a new callback on an already-completed request; the replayed terminal result must be delivered synchronously inside that callback without deadlock. This is the realistic stress point where replay and reentrancy meet.

### Fix surface breadth (BSTP-04 / SC1)
- **D-09:** Block-request paths only — the fix surface is `BitswapRequestContext` plus its outer integration: `requestContexts_` erase-under-lock/dispatch-after-unlock, `messageSent` timer-arming/`AddCallback` path, `processReceivedBlocks` → `HandleResponse`. SC1 is read as scoped to the block-request paths the audit C-7 finding names; the D-05 v2 deferral of `ContentRequestContext` is honored. — **Reversibility:** reversible — scope declaration; Phase 4 pin/content-probe surface stays confined.
- **D-10:** Read-only dispatch-site inventory as evidence — the researcher inventories every other consumer-callback dispatch site in bitswap.cpp (ContentRequestContext paths, `checkContentRequestComplete`, etc.) recording which hold a mutex at dispatch. Findings land as v2 candidates; no fixes, no scope growth. Gives the verification report concrete evidence for how SC1 was scoped.
- **D-11:** Phase 2 lands on `dev_timer_correctness` — commits continue on the existing fix branch (HEAD `e2dc906`), keeping a single linear chain from `d2ec18af` for Phase 4 to content-probe and pin. Matches D-04's anti-merge-friction rationale. Never pushed.

### The agent's Discretion
- `shared_from_this()` lifetime mechanics during dispatch (how the context is kept alive through the callback invocation loop and through reentrant `Cancel()`)
- Exact lock-scoping shape of request-map erase vs dispatch (as long as erase happens under the map lock and dispatch after release)
- How the terminal result is stored for replay (in the retained context entry vs a separate completed-record) provided until-replaced semantics hold
- Test case naming and placement within `bitswap_request_timer_race_test.cpp` (extend) or a sibling file (new `addtest` target)
- WSL sync mechanics (rsync/scp/copy) and ASan toolchain choice (clang/gcc) for the D-07 run
- `io_context` stepping mechanics (`poll()` vs `run_one()`) per Phase 1 carry-forward — no sleeps either way

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream planning artifacts
- `.planning/workstreams/ipfs-improve/REQUIREMENTS.md` — BSTP-04, BSTP-05, TEST-01 definitions (the WHAT for this phase)
- `.planning/workstreams/ipfs-improve/ROADMAP.md` §Phase Details → Phase 2 — success criteria SC1–SC4 (dispatch outside all mutexes, reentrant safety, late-registration, full race suite)
- `.planning/workstreams/ipfs-improve/STATE.md` — pinned SHAs and phase chain

### Phase 1 inheritance (what already landed)
- `.planning/workstreams/ipfs-improve/phases/01-bitswap-timer-correctness/01-CONTEXT.md` — D-01..D-06 decisions carried forward verbatim
- `.planning/workstreams/ipfs-improve/phases/01-bitswap-timer-correctness/01-VERIFICATION.md` — the landed shape: `HandleResponse` restructure (~L94–120), `Cancel()`, race suite inventory (7 cases), branch `dev_timer_correctness` @ `e2dc906` cut from `d2ec18af`, content probes (`completed_`, `REQUEST_TIMEOUT`), Windows test build tree `thirdparty/build/Windows/Debug/ipfs-bitswap-cpp-test`

### Audit origin
- `.planning/research/gnus_libp2p_comparison.md` L63 (§Bitswap → Source-review concerns, finding 2) — the C-7 P0: "`BitswapRequestContext::HandleResponse()` reportedly calls consumers while holding `mutex_`… Move callbacks outside the critical section and test reentrancy."

### Source of truth for the fix
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.cpp` — `HandleResponse` (restructured in Phase 1), `messageSent` (L389 `make_shared` site; arms timer and calls `AddCallback` under outer `mutexRequestCallbacks_`), `processReceivedBlocks` (dispatches responses into `HandleResponse`), `requestContexts_` map lifecycle, `Cancel()`
- `thirdparty/ipfs-bitswap-cpp/src/bitswap.hpp` — `BitswapRequestContext` declaration, `BitswapError` enum (L94–106), the `mutex_` contract comment

### Test wiring
- `thirdparty/ipfs-bitswap-cpp/test/bitswap_request_timer_race_test.cpp` — the 7-case deterministic suite Phase 2 extends (injected durations 60 s / −1 ms, `poll()`/`run_one()` stepping, no sleeps)
- `thirdparty/ipfs-bitswap-cpp/test/CMakeLists.txt` — `addtest()` registration pattern
- `.planning/codebase/TESTING.md` — verification convention: build/test inside the existing `build/<Platform>/<Config>` tree

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 1 race suite (`bitswap_request_timer_race_test.cpp`) — deterministic single-threaded `io_context` harness with injected durations and stepped execution; every Phase 2 test plugs into these patterns
- The landed `HandleResponse` shape — flag check/set → `cancel()` → move callbacks out under `mutex_` → dispatch after unlock: Phase 2 extends this to the outer map/erase/dispatch boundary
- `Cancel()` on `BitswapRequestContext` — landed in Phase 1 (planner-approved), the entry point reentrant consumers call
- The `shared_from_this()` timer capture (landed at `d2ec18af`) — precedent for keeping the context alive across async boundaries; D-07/BSTP-05 needs the same treatment for the dispatch window

### Established Patterns
- Single-lock discipline: only `mutex_` is acquired inside `BitswapRequestContext`; the outer `mutexRequestCallbacks_`/`requestContexts_` guards live at call sites — Phase 2's erase/dispatch split must preserve this layering
- Move-out-then-dispatch idiom (from `ContentRequestContext`, ported in Phase 1) — callbacks are extracted under lock, invoked after release
- Content-probe markers (`completed_`, `REQUEST_TIMEOUT`) — Phase 4 greps the pinned commit; new Phase 2 fix markers should follow the same greppable style

### Integration Points
- `messageSent` — arms the response timer and registers the callback under the outer lock; the replay path (D-01/D-02) must not deadlock this caller
- `processReceivedBlocks` → `HandleResponse` — response ingress; the request-map erase and dispatch-after-unlock integrate here
- `requestContexts_` map — keyed by requested CID; until-replaced retention (D-04) changes its lifecycle from erase-on-complete to replace-on-new-request
- Phase 4 pin chain — single branch `dev_timer_correctness`; all Phase 2 commits land there, never pushed

</code_context>

<specifics>
## Specific Ideas

- TEST-01 full suite = Phase 1's four orderings (already green, must stay green) + new cases: reentrant cancel-own-request (bounded-step drain assert), reentrant chain-new-request (new callback fires), reentrant AddCallback-on-completed (sync replay inside the callback, D-08)
- SC3's second clause is mandatory regardless of replay: no fresh `responseTimer_` is ever armed on a completed request
- WSL ASan environment constraint: target path `~/gnus/GeniusNetwork/thirdparty`; git is unusable there (SSH passphrase); sync source as files from Windows, treat the WSL copy as throwaway
- Windows deterministic suite stays the primary acceptance evidence; WSL ASan is supplementary (D-07)

</specifics>

<deferred>
## Deferred Ideas

- **Non-block-request dispatch-site fixes** — anything the D-10 inventory finds (ContentRequestContext paths, `checkContentRequestComplete`, etc.) is recorded as v2 candidates on their own branch; fixed in a future milestone, not here
- **ContentRequestContext hardening** (carry-forward from Phase 1) — `checkContentRequestComplete` reads `ctx->timedOut` and invokes `ctx->callback` outside `mutexContentRequests_`, a residual success/timeout double-fire race; v2 candidate

### Reviewed Todos (not folded)
- "Fix Vulkan capability-probe deadlock/crash in ProcessingManager::Create path" (`.planning/todos/2026-08-10-fix-vulkan-capability-probe-deadlock-in-processingmanager-cr.md`) — matched this phase only on the keyword "deadlock" (score 0.2); unrelated to Bitswap reentrancy; reviewed in Phase 1 and again here; left for its natural owner.

</deferred>

---

*Phase: 2-Bitswap Callback Reentrancy*
*Context gathered: 2026-10-12*
