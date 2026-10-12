# Pitfalls Research

**Domain:** P0 correctness/resource-bound remediation in a live C++17 libp2p/IPFS stack (Boost.Asio, std::mutex)
**Researched:** 2026-10-12
**Confidence:** HIGH for code-grounded pitfalls (read directly from the pinned integrated sources at `thirdparty/`); MEDIUM for external-reference claims (marked inline)
**Scope:** Mistakes made when *adding* three fixes to the existing GNUS stack — (1) Bitswap canceled-timer handling, (2) Bitswap callback dispatch outside mutex, (3) GossipSub per-peer bounds. CI, protocol upgrades, transports, benchmarks are out of scope.

## Verified baseline (what the fixes will actually touch)

These facts were confirmed by reading the **pinned workspace submodules** on 2026-10-12 (`git submodule status`):

- `ipfs-bitswap-cpp` @ **`d2ec18af`** (matches the audit doc's pin)
- `libp2p` @ **`28f6a629`** (does **not** match the audit doc's `10166f9c` — the pin has moved)
- `ipfs-pubsub` @ **`b6eb6268`** (does **not** match the audit doc's `b9f051f8`)

Code state at these pins — this is the mixed state the fixes land on:

- `BitswapRequestContext` (`bitswap.cpp:60-99`) — **still buggy**: the `async_wait` handler ignores `ec` entirely (`[self](const boost::system::error_code &) { self->HandleResponseTimeout(); }`), so *any* cancellation is treated as a timeout. `HandleResponse()` disarms via `expires_at(pos_infin)` — which **is** a cancellation and delivers `operation_aborted` — and invokes all `callbacks_` **while holding `mutex_`**.
- `ContentRequestContext` timeout path (`setupContentRequest`, `bitswap.cpp:565-605`) — **already carries the fixed pattern**: `if (ec) return;`, move-callback-out-under-lock, invoke outside lock, `timedOut` flag set under lock before dispatch (comments reference "C-5"/"C-7" fixes).
- `processReceivedBlocks` (`bitswap.cpp:280-306`) — already does erase-under-lock + `HandleResponse` outside lock.
- GossipSub: `RemoteSubscriptions::table_` unbounded (`remote_subscriptions.hpp:75-77` TODO: "bound table size (which may grow!) by removing items not subscribed to locally. LRU(???)"); `Stream::pending_buffers_`/`pending_bytes_` unbounded (`stream.hpp:64-70` TODO: "limit pending bytes and close slow streams"); `Config` has no bound fields (`gossip.hpp:50-100`).

Implication: **the repo already contains the target patterns** — the fix work is porting them to `BitswapRequestContext` and adding bounds, not inventing new patterns. Pitfalls below are dominated by "half-port" and "divergent-pattern" mistakes, plus reintroduction at repin time.

---

## Critical Pitfalls

### Pitfall 1: Treating `operation_aborted` as a timeout (the exact bug, re-introduced subtly)

**What goes wrong:**
The current handler runs `HandleResponseTimeout()` unconditionally. The naive fix is `if (ec == operation_aborted) return;`. Two subtle reintroductions remain:

1. **Disarm-by-rearm is still a cancel.** `HandleResponse()` currently "cancels" via `responseTimer_.expires_at(pos_infin)`. Setting a new expiry on a timer with a pending wait **cancels the pending wait and posts the handler with `operation_aborted`** (Boost.Asio `basic_deadline_timer` semantics; verified from the boost.org 1.83 reference). If any code path re-arms the timer without the `ec` check (or with a check that only excludes `ec` but races a *real* expiry already dequeued), the false-timeout fires again. Prefer explicit `.cancel()` for disarm — it makes intent and the aborted-handling contract obvious.
2. **The race window.** A real timeout can be dequeued and *in flight* while `HandleResponse()` re-arms/cancels on another thread. Then both run: timeout handler calls `HandleResponse(error)` and the response path calls `HandleResponse(block)`. With callbacks cleared under the mutex the *second* invocation is a no-op for callbacks — but only if callback-list clearing and the completion flag are checked/set atomically under the same mutex. If the refactor splits "check completed" from "clear callbacks," you get double-delivery or zero delivery.

**Why it happens:**
Boost.Asio's cancel-then-post-with-error design is counterintuitive: developers expect cancel to mean "handler never runs." It always runs, once, with `operation_aborted`. Also, `expires_at(pos_infin)` *looks* like a disarm, not a cancel.

**How to avoid:**
- Handler contract: `if (ec) return;` for *any* error (aborted is the only expected one); treat success as the only timeout path.
- Use `.cancel()` for disarm, never `expires_at(pos_infin)`.
- Add a `completed_` flag (or empty-callbacks check) set atomically with callback clearing under `mutex_`, so racing invocations are idempotent.
- Keep every `responseTimer_` operation (arm/cancel/wait) under `mutex_` — `deadline_timer` is **not thread-safe**; concurrent `cancel()` + `async_wait()` is UB even when each call site "looks" locked.

**Warning signs:**
- Log lines "request timeout" immediately following a successful block receipt.
- Callbacks receiving `OUTBOUND_STREAM_FAILURE` for peers with healthy RTTs.
- A handler signature still taking `const boost::system::error_code &` without naming it *and* without a comment — grep for `( const boost::system::error_code & )` with an empty/unnamed parameter in the diff.

**Phase to address:**
Phase 1 (Bitswap timer/cancellation) — this is the core deliverable; regression test in the same phase (see Pitfall 9).

---

### Pitfall 2: Timer object thread-safety violations introduced *by* the refactor

**What goes wrong:**
Today all `responseTimer_` ops happen under `mutex_` (arm in `AddCallback`, rearm in `HandleResponse`) — accidentally safe. The refactor moves *callbacks* outside the lock; developers often "helpfully" move timer operations outside too (e.g., cancel before dispatching callbacks so the timer stops while user code runs). Now `AddCallback` (arming under `mutex_`) races `HandleResponse` (canceling outside it) on the same non-thread-safe `deadline_timer` — heap corruption or lost cancels that surface as intermittent hangs weeks later.

**Why it happens:**
"Callback outside mutex" gets generalized to "everything that isn't shared state outside mutex." The timer *is* shared state.

**How to avoid:**
- Rule: the mutex protects {callbacks list, completed flag, timer object} as one invariant; only the *user callback invocation* leaves the lock.
- Cancel under the lock, copy callbacks out under the lock, release, then invoke.
- If timer ops must happen off-lock, migrate the whole context to a strand/executor instead of a mutex — don't mix.

**Warning signs:**
- A diff where `cancel()` or `expires_*()` moved out of a `lock_guard` scope while the mutex itself stayed.
- TSAN reports on `deadline_timer` internals (two writers, no synchronization).

**Phase to address:**
Phase 1 (and re-verify in Phase 2's reentrancy tests — the bug class is created by their interaction).

---

### Pitfall 3: Handler/lifetime regressions when touching capture lists

**What goes wrong:**
The current `AddCallback` deliberately captures `shared_from_this()` (comment explains: raw `this` dangles once `requestContexts_.erase` drops the last external `shared_ptr` while the timer is pending). Refactors that add a new timer, or "simplify" captures, reintroduce dangling: the most common variant is a *new* retry/reset timer lambda capturing raw `this` (or `ctx` raw pointer) — runs fine in tests where the caller holds a reference, crashes in production where the map entry is erased first. The mirror-image bug: a self-capturing `shared_ptr` chain (like the retry timer at `bitswap.cpp:502-510`, which holds `timer` inside its own handler) that keeps an object alive forever if the handler never fires because the io_context was stopped — shutdown hang.

**Why it happens:**
Both directions look correct in isolation; only lifetime *timing* differs. The existing code comments (lines 74-77) exist precisely because this was hit before — any new code lacks that scar tissue.

**How to avoid:**
- Every async handler on a context object: `shared_from_this()` capture, or `weak_from_this()` + expired-check when the object should be collectable (gossip `Stream` uses the weak pattern; `Bitswap` handlers use weak; `BitswapRequestContext` uses shared).
- Document the chosen ownership per timer in a comment, mirroring the existing style.
- For "timer that must not extend lifetime," use `weak_from_this` + no-op on expired, and ensure `cancel()` happens in a destructor-owned path or shutdown.

**Warning signs:**
- New lambda captures of `this` in the diff (grep `[this` / `[ctx = this` / `[ctx` where ctx is a raw pointer).
- Objects never destroyed after `io_context::stop()` (leak report / stuck shared_ptr counts in tests).

**Phase to address:**
Phase 1 (timer changes) and Phase 3 (gossip stream bound code adds new early-close paths where `closed_`/`weak_from_this` checks must be respected — see Pitfall 8).

---

### Pitfall 4: Moving the callback outside the lock — but creating a TOCTOU with late `AddCallback` (lost wakeup)

**What goes wrong:**
After the refactor, `HandleResponse` will: lock → copy callbacks → mark completed → clear → unlock → invoke copied callbacks. A concurrent `AddCallback` that slips in *after* the clear but *before/after* dispatch: it appends a new callback and arms a fresh timer for a request that has **already completed**. Depending on ordering, the new callback either (a) never fires until the new timer times out — caller sees a phantom 5s delay then failure for a block that arrived, or (b) fires with stale/absent data. Inbound `processReceivedBlocks` erases the context from `requestContexts_` before `HandleResponse`, so new requests create a *new* context — but any direct `AddCallback` path on a still-referenced context has the race.

**Why it happens:**
"Callback outside lock" fixes deadlock but silently changes the state machine: the check-then-act pair (is-completed? / append) now straddles the region where completion happens outside the mutex's protection of *semantics*.

**How to avoid:**
- Add `completed_` under the mutex; `AddCallback` on a completed context must fail fast (invoke callback immediately with an error, or deliver the already-received block) — never arm a timer.
- Keep map-erase and completed-flag transitions atomic under the *same* lock that guards the map (`mutexRequestCallbacks_` / `mutex_`), then dispatch outside.
- Define and document the post-completion contract in one place; both `HandleResponse` and `AddCallback` consult it.

**Warning signs:**
- `AddCallback` bodies whose only change is the timer fix, with no completed-state check.
- Test flakiness where a callback arrives exactly ~5s late (the armed-but-orphaned timer).

**Phase to address:**
Phase 2 (callback dispatch refactor).

---

### Pitfall 5: Erase-while-iterating / iterator invalidation when hoisting locks

**What goes wrong:**
The existing correct pattern (`processReceivedBlocks`) uses a scoped block: lock → find → copy `shared_ptr` → erase → unlock → then `HandleResponse`. When porting this to `BitswapRequestContext` or extending it (e.g., to sweep multiple blocks or contexts), easy mistakes: holding `mutexRequestCallbacks_` across the whole `for (blockIdx...)` loop while calling `HandleResponse` inside (deadlock — `HandleResponse` takes `mutex_`, and the callback may reenter `Bitswap` methods that take `mutexRequestCallbacks_` again); or erasing from `requestContexts_` / `providers_` / `contentRequests_` while iterating the same map in a new cleanup sweep. The GossipSub table-bound work has the identical hazard: an LRU sweep erasing from `RemoteSubscriptions::table_` while iterating it under `table_mutex_` (and `onPeerDisconnected` iterates a swapped-out set calling `onPeerUnsubscribed`, which re-locks per topic — a sweep holding the lock across that path deadlocks).

**Why it happens:**
Each individual map's code was safe; the *new* sweep/batching code crosses lock domains (`mutexRequestCallbacks_` vs `mutex_` vs `table_mutex_` vs per-peer `PeerContext` state). Lock-order graphs only become visible when two existing locks meet in new code.

**How to avoid:**
- Fixed lock order, documented: outer `Bitswap` maps (`mutexRequestCallbacks_`, `mutexContentRequests_`, `mutexActiveStreams_`, `mutexProviders_`) **never** held while calling into `BitswapRequestContext`/`ContentRequestContext` methods that take their internal mutex; contexts never call back into `Bitswap` while holding their internal mutex (they can't — callbacks are invoked outside it, which is the point of the fix).
- For erasure sweeps: collect keys under lock into a local vector, erase, unlock, then act.
- Never hold `table_mutex_` across anything that can call `connectivity_.*` or feedback into peer/message code.

**Warning signs:**
- A `for` loop whose body both locks a mutex and calls a method documented to lock another.
- New "cleanup"/"sweep"/"LRU" functions touching `table_` — review their entire call graph under lock.

**Phase to address:**
Phase 2 (bitswap) and Phase 3 (gossip table bound).

---

### Pitfall 6: `post` vs `dispatch` semantics — ordering inversion and double-completion

**What goes wrong:**
Two ways teams "move the callback out":

1. **`dispatch` from inside the handler** (inline call after unlocking): reentrancy is preserved but if the io thread then re-enters code taking the just-released mutex *while other threads hold it*, you get ordinary lock contention — fine — but if the callback *blocks*, the io thread stalls (all asio work on that thread freezes; in this stack the same io_context runs libp2p reads — a blocking callback freezes the network).
2. **`post` to defer**: safer against blocking, but changes *ordering*. A posted timeout-completion can be overtaken by a posted success-completion (or vice versa) if both paths post without an atomic state transition first. Result: caller receives `CONTENT_REQUEST_TIMEOUT` *after* the block arrived, or receives both.

The existing fixed code (`setupContentRequest` timeout handler) does the state transition (`timedOut = true`, erase, move callback) **under the lock**, then invokes outside — i.e., state first, dispatch second, single owner. Note its comment claims "C-5 dispatch serialization" via io_context: that only holds if `context_->run()` is invoked from exactly one thread. If the host runs the io_context on multiple threads (common in this stack — `context_` is shared), `timedOut` written by one thread and read by another **outside** the mutex is a data race; it's currently only safe because both timeout and completion handlers happen to take `mutexContentRequests_` around their reads/writes of the flag.

**Why it happens:**
asio's `post`/`dispatch` distinction (defer-to-strand/queue vs run-now-if-allowed) is invisible in tests with a single-threaded io_context — everything is "serialized" by accident.

**How to avoid:**
- State transition under the mutex, exactly one winner, then invoke the moved-out callback (directly or via `post` — but decide and document; `post` is the safer default for user callbacks).
- Treat `io_context` multi-thread `run()` as the production assumption: every cross-thread flag must be mutex- or atomic-protected, never "serialized by the io_context."
- Blocking callbacks are forbidden on the io thread — document it as the API contract for `BlockCallback`/`ContentCallback`.

**Warning signs:**
- `dispatch` used because "post made the test flaky" (that flakiness was the real race).
- Flags read outside the lock that were only ever written under it, with a comment citing io_context serialization.
- `use_future`-style synchronous waits (`future.get()` inside a handler) — instant deadlock on single-threaded io_context; none exist today, keep it that way.

**Phase to address:**
Phase 2; revisit the `timedOut`-under-lock invariant explicitly.

---

### Pitfall 7: GossipSub table bound — LRU eviction that breaks Graft/Prune/IHAVE correctness

**What goes wrong:**
The TODO says "bound table size by removing items not subscribed to locally. LRU(???)." Danger: an entry with **no local subscription can still have remote peers subscribed**. Dropping it silently breaks:
- `onGraft` for that topic (falls into the "we don't have this topic anymore" branch → spurious PRUNE back to a peer that grafted legitimately),
- `onNewMessage` fanout and IHAVE gossip for that topic,
- `onPeerUnsubscribed` bookkeeping (peer's `subscribed_to` says subscribed; table says topic unknown → state divergence that accumulates).

**Why it happens:**
"Bound the table" sounds like generic cache eviction; in GossipSub the table is protocol state, not a cache. Also the mispredicted quirk: the TODO's own parenthetical "(???)" signals the original author hadn't resolved this.

**How to avoid:**
- Bound by *empty-entry expiry* first: only entries with zero local AND zero remote subscribers are eligible (they're already erased today when `subs.empty()` — a bound mainly guards against pathological topic spam creating entries via `getItem(topic, true)` from wire-side `onPeerSubscribed`).
- Cap **distinct topics per peer** (a peer sending endless SUBSCRIBEs for unique topics grows both `peer->subscribed_to` and `table_`): reject/ignore subscriptions beyond N topics per peer — this bounds the table at the source rather than evicting live state.
- If a hard table cap is still required, evict only locally-unsubscribed entries with no remote subscribers and log loudly; never evict entries referenced by any `PeerContext`.

**Warning signs:**
- Mesh instability after the change: PRUNE/graft churn in logs, messages seen by fewer peers than mesh size suggests, CRDT updates intermittently missing on some nodes.
- Test that only checks "table size <= cap" without validating graft/prune behavior post-eviction.

**Phase to address:**
Phase 3 (GossipSub bounds) — with an explicit sub-task for graft/prune regression coverage.

---

### Pitfall 8: Outbound queue bound — wrong policy, wrong unit, or bound set below CRDT sync fanout bursts

**What goes wrong:**
Four distinct failure modes when bounding `Stream::pending_buffers_` / `pending_bytes_`:

1. **Wrong overflow policy.** Disconnect-on-first-overflow kills legitimate-but-slow peers (mobile/wireless SuperGenius edge nodes) and creates a disconnect/reconnect storm worse than the memory cost. Go's reference gossipsub uses **drop-new-RPC when the queue is full** (default `peerOutboundQueueSize = 32`, option `WithPeerOutboundQueueSize`; verified from `go-libp2p-pubsub` `pubsub.go`) and relies on *peer scoring* for repeat offenders — a mechanism this stack doesn't have. Without scoring, drop + count + log, and only escalate (close stream) after sustained overflow.
2. **Wrong unit.** Go's 32 counts **RPCs** (each RPC batches many messages); this stack's `pending_buffers_` holds serialized **messages**. Copying "32" verbatim as a message count would throttle far below Go's effective throughput. Bound **bytes** (`pending_bytes_` already exists as a counter — use it), with the message count secondary.
3. **Bound below legitimate CRDT sync fanout.** SuperGenius `PubSubBroadcasterExt` broadcasts CRDT state via gossip; a sync burst (join/rejoin, large state delta) to a peer on a slow link must fit or be droppable *without* losing the CRDT update path — dropped gossip messages here aren't "just" pubsub loss, they're consensus-state divergence until the next sync. Default must be generous (order 1–4 MiB per peer / hundreds of messages), configurable, and drop must be observable.
4. **Where the check lives.** Enforcing in `beginWrite` only (after dequeue) still lets `write()` enqueue unboundedly between writes; enforce at `Stream::write()` entry — increment `pending_bytes_` there, reject/close when over. Also note `closed_` is read/written from multiple threads without synchronization today; new early-close-on-overflow paths will turn that benign-ish pattern into a hard race — protect it (the Stream is used from one scheduler/executor context; keep it that way or add the guard).

**Why it happens:**
Each choice (policy, unit, value, site) is individually defensible from a memory-safety viewpoint; correctness comes from the protocol's expectations, which live outside this repo.

**How to avoid:**
- Config fields with generous defaults + first-drop-per-peer logging (rate-limited) + a metric/counter so operators can see drops.
- Document the interaction with CRDT fanout in the Config comment ("lowering this below typical sync burst size drops consensus traffic").
- Drop-new, not drop-oldest, for gossip (mesh messages have short relevance windows; an old queued IHAVE/control message is worth less than a fresh one) — but *count* drops and close the stream only on sustained overflow (e.g., over-cap for K consecutive heartbeats).

**Warning signs:**
- New Config fields with defaults copied from Go's RPC count.
- Overflow handling that calls `close()`/`reset()` directly on first exceed.
- No log/metric on the drop path ("silent" bounds can't be debugged in the field).

**Phase to address:**
Phase 3; Config surface decisions must be settled in Phase 3 planning (see Pitfall 12 for config-compat gotcha).

---

### Pitfall 9: The regression test is itself racy (timing sleeps, real 5s/30s timers, unsynchronized flags)

**What goes wrong:**
Tests for timer fixes classically flake or pass vacuously:
- **Real-time waits**: arming the production 5s/30s timers and sleeping in the test → slow, and on a loaded CI VM the "cancel before fire" test loses the race in the other direction (timer fires before the cancel) — the test then *proves the bug is fixed* while exercising the buggy ordering.
- **"Must not be called" assertions**: a bool flag `called_ = true` in the callback, checked at test end — but the handler may still be *in flight* when the check runs (posted, not yet executed) → test passes while the bug exists, or fails spuriously.
- **Cancel-from-another-thread tests** reproduce the *timer thread-safety* bug (Pitfall 2) as a test-only crash, misattributed to the fix.
- **Simulated clock vs real io_context**: swapping in a mock scheduler/clock for gossip but real `deadline_timer` for bitswap means cross-component timing tests test nothing deterministic.

**Why it happens:**
asio's async model makes "assert this never runs" fundamentally a synchronization problem, and the code under test mixes `std::mutex` threads with io-context threads.

**How to avoid:**
- Single-threaded `io_context` in the test; drive it with `poll()`/`run_for()` loops; cancel via `post` ordering so the sequence is deterministic: arm → post(cancel) → run → assert handler saw `operation_aborted` and did NOT invoke the user callback.
- Short timeouts (milliseconds) injected via the context/config — this requires the timeout to be injectable; if `responseTimeout_`/`contentTimeout_` are hardcoded constructors (they are, `seconds(5)`/`seconds(30)`), expose them for tests in Phase 1/2 rather than sleeping.
- Completion-counting with condition_variable/future the test waits on — never a bare flag read after `run()` returns.
- For cancellation-vs-timeout determinism, assert on *which* path completed (distinct error codes), not just "callback ran."
- Run the new tests under TSAN/ASAN where available (the libp2p repo has sanitizer CI; bitswap tests run in its own repo — run locally under TSAN on Linux even if CI is out of scope for this milestone). Expect TSAN to also flag pre-existing races (e.g., `timedOut`, `closed_`) — triage rather than block, but *don't silence* them: fix or file.

**Warning signs:**
- `std::this_thread::sleep_for` in any new test.
- Callback assertions on non-atomic bools.
- Tests that only assert the happy path (block arrives, callback once) with no cancel-path test — the bug was in the cancel path.

**Phase to address:**
Phases 1 and 2 (each ships its regression test); Phase 3 tests get a deterministic scheduler mock (the gossip code already runs on `basic::Scheduler`, which is mockable — use it instead of real timers).

---

### Pitfall 10: Fixing on branch tips instead of the pinned integrated commits — reintroduction at repin

**What goes wrong:**
The audit doc's standing warning, now *concrete*: the workspace pins have already moved relative to the audit (`libp2p` `28f6a629` ≠ doc's `10166f9c`; `ipfs-pubsub` `b6eb6268` ≠ doc's `b9f051f8`; only bitswap `d2ec18af` matches). If fixes are developed against `develop`/`master` tips of each fork (which contain later churn — the GNUS fork is hundreds of commits ahead of upstream and tips keep moving), then:
1. The fix may conflict with or duplicate changes already on the tip (the `C-5`/`C-7`-style fixes present at `d2ec18af` show tip work has partially landed before — a second, divergent fix creates two patterns in one file).
2. When `thirdparty` is repinned to whatever the branch tip is *at repin time*, unrelated tip commits ride along with the fix — or, if the integrator pins "the fix commit" cherry-picked onto the *old* pin, the fix can be silently absent from what actually builds (submodule SHA ≠ branch tip you tested).
3. The mixed state means a fix written against the tip's `BitswapRequestContext` may not even apply to `d2ec18af`'s version.

**Why it happens:**
It's natural to work where the code is most current; the integrated product builds from frozen pins that nobody re-freezes daily.

**How to avoid:**
- Branch each fix from the **current pinned SHA** (`d2ec18af`, `28f6a629`, `b6eb6268`), not from tips; merge/cherry-pick toward tips later.
- Record fix SHAs in the workstream plan; at integration, verify by `git submodule status` + a content probe (grep for the fix's distinguishing marker, e.g., the `ec` check) — not by trust.
- Re-run the audit's two source-review checks against each final pinned SHA before declaring the milestone done ("findings from branch tips should be rechecked against these pinned commits" — now applies to our own fixes).

**Warning signs:**
- Plan/commits referencing "develop" or "master" of a thirdparty repo rather than a SHA.
- A `thirdparty` bump whose diff includes many unrelated commits alongside the fix.

**Phase to address:**
All phases' integration steps; enforce via a checklist item in each phase's verification ("pinned SHA contains fix marker X").

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Fix `ec` handling by ignoring *all* errors (`if (ec) return;` everywhere) | Quick, kills the false-timeout | Real errors (bad descriptor, shutdown) silently swallowed; requests hang until outer timeout instead of failing fast | Acceptable for timer handlers whose only pending op is the wait; never for stream ops — add a comment distinguishing |
| Keep `expires_at(pos_infin)` disarm instead of `.cancel()` | No behavioral change, smaller diff | Next reader reintroduces Pitfall 1; handler contract stays implicit | Only if the same PR adds the `ec` check + comment; prefer `.cancel()` outright |
| Bound gossip queues by message count, not bytes | Trivial to implement | Legit large-message peers throttled; CRDT bursts dropped | Never as the *primary* bound; fine as a secondary sanity cap |
| Silent drop on queue overflow (no log/metric) | Fast path stays fast | Undiagnosable CRDT divergence in the field | Never — at minimum a rate-limited warn + counter |
| Test with real timeouts and sleeps | No test-only injection points needed | Flaky CI, vacuous coverage | Never for cancellation tests |
| Fix on branch tips, pin later | Latest code, easier merges | Reintroduction at repin (Pitfall 10) | Only if repin happens same-day and is SHA-verified |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| thirdparty submodule repin | Pinning to a moving branch tip; trusting branch names | Pin exact SHA; content-probe the fix marker; bump one submodule per reviewable change |
| GNUS fork ↔ upstream cpp-libp2p | Cherry-picking upstream fixes (fork is 415+ commits ahead) — won't apply, drops GNUS additions (gating, relay, AutoNAT) | Port the *idea* onto the fork's code; review GNUS-specific call sites the upstream patch never saw |
| bitswap ↔ ipfs-pubsub ↔ SuperGenius consumers | Changing `BlockCallback` timing/contract (now invoked outside lock, possibly posted) without auditing consumers that assumed inline delivery under the caller's thread | Enumerate callback consumers (CRDT/fetch paths in SuperGenius via GeniusSDK); document "may run on io thread, must not block, may run after request map entry erased" |
| Boost.Asio version in tree | Assuming cancel semantics from memory (older docs) | Match the vendored Boost's reference; `cancel()`/re-arm both deliver `operation_aborted` — verified against 1.83 docs |
| Gossip `Config` aggregate initialization | Inserting new bound fields mid-struct — breaks existing designated/aggregate init sites across repos (SuperGenius constructs this Config) | Append fields at the end with defaults; grep all constructing repos before changing field order |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| Holding `mutexRequestCallbacks_`/`mutexContentRequests_` across disk I/O or callback dispatch | Whole bitswap stalls; other peers' requests queue behind one slow consumer | Copy-and-release pattern everywhere (already the C-7 pattern — keep it in new code) | Any peer with slow storage or a slow callback consumer |
| `post`-ing every block callback individually during a large UnixFS traversal (hundreds of blocks) | io_context queue explosion, latency spikes, memory growth in posted handlers | Batch or invoke directly outside the lock (non-posted) when already on the io thread | Large files / multi-block archives (256 KiB chunks → many blocks per file) |
| Unbounded `providers_` map growth (per-CID provider lists, `bitswap.cpp:1591-1670`) amortized by erasing only on failure | Slow memory growth on long-running nodes fetching many CIDs | Not in scope to fix, but don't *worsen*: any new retry logic must reuse existing erase paths | Days-weeks uptime with high CID churn |
| Per-peer byte bound checked at write time only (`beginWrite`) | Burst between writes still unbounded | Check at `Stream::write()` entry | High publish rate to slow peer |
| LRU table sweep under `table_mutex_` on every heartbeat (1s) | Lock contention with `onNewMessage` fanout | Sweep on interval or size-trigger, collect-then-erase | Large topic counts after bound is added |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Accepting the bounds work as "DoS-hardening complete" | The audited gaps (unbounded subscription table, unbounded pending buffers) are *memory-exhaustion* vectors from untrusted peers; a bound that evicts wrong state (Pitfall 7) converts DoS into *correctness attack* (targeted PRUNE starvation) | Graft/prune regression tests + a malicious-peer test: flood unique-topic subscriptions, assert table cap AND mesh integrity |
| Dropping messages without authentication/authorization context | Attacker forcing drops of a victim's CRDT traffic by saturating a shared bound | Per-peer bounds (not global), so one peer's saturation only affects itself |
| New Config surface (bound knobs) without validation | Zero/negative bounds → disable the bound entirely (unbounded again) or reject all traffic | Validate: positive, and reject config load on nonsense values (Go's `WithPeerOutboundQueueSize` errors on non-positive — mirror that) |
| Log-injection via peer-controlled topic strings in new drop/error logs | Log forgery from wire data | Use structured logging with bounded fields (existing logger does this; keep format strings constant) |

## UX Pitfalls

Users here are node operators and SDK integrators (no end-user UI in scope).

| Pitfall | User Impact | Better Approach |
|---------|-------------|------------------|
| Silent behavior change: requests that used to "fail fast" (false timeout) now wait for real completion | Integrators' timeout/UX assumptions shift; previously-aborted flows now succeed slowly and may double-deliver at the app layer | Release note: callback timing contract changed (may arrive later, may arrive outside caller's lock); audit GeniusSDK consumers in-phase |
| New bounds defaulting ON with no visibility | Operator can't tell CRDT sync degradation is from drops | Rate-limited warn log per peer + counter exposed wherever stats live today |
| Error-code reuse: reporting dropped-queue as existing `OUTBOUND_STREAM_FAILURE`/timeout codes | Integrators can't distinguish "peer slow" from "peer dead" from "we dropped" | New distinct error/log reason if surface allows; otherwise distinct log message + metric |

## "Looks Done But Isn't" Checklist

- [ ] **Timer fix:** handler still doesn't name/check `ec` — grep the diff for `error_code` params; every changed `async_wait` lambda must branch on `ec`
- [ ] **Timer fix:** disarm still uses `expires_at(pos_infin)` instead of `.cancel()` (leaves the trap armed for the next editor)
- [ ] **Dispatch fix:** `HandleResponse` invokes callbacks while any lock is held on the stack (check the *call chain*, not just the function — `processReceivedBlocks` callers must not hold `mutexRequestCallbacks_` either)
- [ ] **Dispatch fix:** no `completed_`/post-completion contract on `AddCallback` → late registrants hang until timeout (Pitfall 4)
- [ ] **Dispatch fix:** double-delivery guard — racing timeout+response invoked exactly once (test asserts count == 1, not just "callback ran")
- [ ] **Bounds fix:** per-peer topic cap AND table size cap both present; eviction never removes entries with live remote subscribers (Pitfall 7)
- [ ] **Bounds fix:** byte-based bound enforced at `write()` entry, drop-new policy, sustained-overflow escalation, first-drop log + counter (Pitfall 8)
- [ ] **Bounds fix:** defaults sized above CRDT sync burst; Config fields appended (not inserted); validated positive
- [ ] **Tests:** cancellation test is deterministic (single-threaded io_context, posted cancel, no sleeps); "never called" assertions use synchronization, not bare flags
- [ ] **Tests:** cancel-path and race-path tests exist, not just happy path
- [ ] **Integration:** fixes branched from pinned SHAs (`d2ec18af`/`28f6a629`/`b6eb6268`); final pinned SHA content-probed for fix markers; audit's two source-review checks re-run against final pins
- [ ] **Cross-repo:** callback-timing contract change communicated/audited at SuperGenius/GeniusSDK consumption sites

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| 1. operation_aborted-as-timeout reintroduced | LOW | Localized handler fix + deterministic regression test; ship with the phase |
| 2. Timer thread-safety violation | MEDIUM | Reproduce under TSAN; re-collapse timer ops under mutex or migrate context to strand; audit all timer call sites in the diff |
| 3. Dangling handler capture | HIGH | Crash sites point at freed context; convert captures to shared/weak per existing pattern; add lifetime assertion in tests (destroy context with pending timer in a test loop) |
| 4. Late-AddCallback lost wakeup | MEDIUM | Add completed_ contract + immediate-error delivery for late registrants; grep all AddCallback callers |
| 5. Lock-order deadlock (new sweep code) | MEDIUM | Deadlock stack traces identify the pair; restructure to collect-then-act; document lock order in the file header |
| 6. post/dispatch ordering double-completion | MEDIUM | Move state transition under lock (single-winner) in both completion paths; add race-exhaustion test loop |
| 7. Table eviction breaks graft/prune | HIGH (protocol state corruption, subtle) | Revert eviction to empty-entry-only; add malicious-subscription test; if shipped, force resubscribe/reconnect of affected peers |
| 8. Queue bound breaks CRDT fanout | HIGH (consensus divergence) | Raise default/config; drop counters reveal it; if shipped, trigger CRDT resync on affected topics |
| 9. Racy regression tests | LOW-MEDIUM | Rewrite on single-threaded io_context with posted cancels; inject short timeouts |
| 10. Fix absent at repin | LOW if detected (content probe), HIGH if shipped | Re-branch fix onto correct pinned SHA, repin, re-run probe + regression tests |

## Pitfall-to-Phase Mapping

Assuming the natural three-phase split for this workstream (adjust names to the final roadmap):

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| P1 operation_aborted-as-timeout | Phase 1 — Bitswap canceled-timer handling | Deterministic cancel test asserts `ec`-branch taken; no unconditional `HandleResponseTimeout` in diff |
| P2 timer thread-safety | Phase 1 | All timer ops under one mutex (or strand); TSAN run clean on touched paths |
| P3 handler lifetime | Phase 1 (bitswap) / Phase 3 (gossip stream close paths) | No raw `this` captures in new handlers; test destroys contexts with pending timers |
| P4 late-AddCallback TOCTOU | Phase 2 — callback dispatch outside mutex | Completed-contract test: AddCallback after completion gets immediate error, no 5s hang |
| P5 iterator/lock-order in sweeps | Phase 2 (bitswap maps) / Phase 3 (gossip table) | Deadlock stress test; collect-then-erase pattern in review |
| P6 post vs dispatch ordering | Phase 2 | Race-exhaustion loop: response+timeout concurrently → exactly one callback |
| P7 table eviction correctness | Phase 3 — GossipSub subscription bounds | Graft/prune regression + unique-topic flood test; mesh integrity asserted post-eviction |
| P8 outbound queue bound policy/unit/value/site | Phase 3 — GossipSub outbound bounds | Config documented vs CRDT burst; drop counter + first-drop log verified; slow-peer test stays connected until sustained overflow |
| P9 racy tests | Phases 1-3 (each phase's tests) | No sleeps; single-threaded io_context; synchronization on assertions |
| P10 pinned-SHA reintroduction | All phases' integration step | `git submodule status` + fix-marker probe + re-run audit checks at close |

## Sources

- **Primary (ground truth, read at pinned SHAs on 2026-10-12):** `thirdparty/ipfs-bitswap-cpp` @ `d2ec18af` — `src/bitswap.cpp` (lines 60-99, 280-306, 431-530, 565-640, 900-960, 1591-1670); `thirdparty/libp2p` @ `28f6a629` — `src/protocol/gossip/impl/remote_subscriptions.{hpp,cpp}`, `impl/stream.{hpp,cpp}`, `include/libp2p/protocol/gossip/gossip.hpp` (Config, lines 50-100). **Confidence: HIGH** (direct source inspection of the exact integrated commits).
- **Prior audit:** `.planning/research/gnus_libp2p_comparison.md` (2026-10-12) — source-review concerns #1/#2, pinned-commit table, "recheck against pinned commits" warning. **Confidence: HIGH** (cross-checked: its bitswap pin matches the workspace; its libp2p/pubsub pins do **not** — workspace has `28f6a629`/`b6eb6268`; both facts recorded above).
- **Boost.Asio `basic_deadline_timer::cancel` reference** (boost.org, 1.83): cancel/re-arm posts outstanding handlers with `operation_aborted`; timer not thread-safe. Fetched directly from boost.org during this research. **Confidence: HIGH** (primary vendor documentation, fetched and read).
- **go-libp2p-pubsub `pubsub.go`** (libp2p, master): `peerOutboundQueueSize = 32` default counting **RPCs**, drop-on-full policy, `WithPeerOutboundQueueSize` rejects non-positive. Fetched directly from GitHub raw during this research. **Confidence: HIGH** (primary source code, fetched and read); note it is the *reference implementation's* policy, not a spec mandate.
- **Seam note:** `classify-confidence --provider websearch` returned LOW (provider is unvetted for generic web results); the two external claims above are elevated on the basis of direct primary-source fetch (vendor docs / canonical repo), per the source-hierarchy intent, and are marked as such. No MCP documentation providers were available in this environment; no other external claims are made.

---
*Pitfalls research for: IPFS P0 remediation (ipfs-improve, v1.0) — timer cancellation, callback dispatch, GossipSub bounds*
*Researched: 2026-10-12*
