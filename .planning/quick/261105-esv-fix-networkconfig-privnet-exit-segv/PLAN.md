---
gsd_plan_version: "1.0"
task: Fix network_config_private_network_test OSX-Debug exit-time SegFault (tag-build run 41936126485)
status: in-progress
created: 2026-11-05
---

# Quick Task: Fix network_config_private_network_test exit-time SegFault

## Problem

Tag-build run 41936126485 (HEAD be1ca5f5, dev_blockstore) — job `build (OSX, Debug)`:
all 7 `NetworkConfigPrivateNetwork` gtest cases PASS, then the test binary
**SegFaults at process exit** (`Test #30 ... ***Exception: SegFault 26.10 sec`).
Last passing run 41024756227 (72e540004, Oct 30 08:11).

## Root cause (evidence)

Crash report (artifact `macos-Debug-crash-reports-41936126485-1`), crashed thread:

```
std::async worker -> CrdtDatastore::StartRebroadcastHeads()::$_0
  -> CrdtDatastore::RebroadcastHeads()
  -> GraphsyncDAGSyncer::GetPeerInfo -> BasicHost::getPeerInfo
  -> TcpListener::getListenMultiaddr -> enumerateNetworkInterfaces
  -> libp2p::log::createLogger -> soralog::LoggingSystem::getGroup
  -> unordered_map::find -> SEGV @ 0x60
```

A **leaked CRDT rebroadcast worker thread** was still running when `main` returned;
at exit-time static destruction it called `createLogger`, which dereferenced the
destroyed/null libp2p logging global (`thirdparty/libp2p/src/log/logger.cpp`,
anonymous-namespace `logging_system_`; `getLoggingSystem()` has no null guard and
`BOOST_ASSERT` is compiled out in this binary).

Why leaked: `CrdtDatastore::StartRebroadcastHeads()`'s async lambda holds a strong
`self` for the whole loop — if nobody calls `CancelAndCloseNow()`, datastore + thread
live until process exit. `GeniusNode` teardown only stops the GlobalDB if
`tx_globaldb_` is set when `ShutdownForDestruction()` reads it. The shutdown gate in
`StateTransition()` is checked ONCE, BEFORE acquiring `lifecycle_mutex_`, and
`ShutdownForDestruction()` never takes that mutex. A node dropped while its async
init state machine is mid-`INITIALIZING_DATABASE` (this test drops nodes ~2s after
startup starts, on a slow `-j24` Debug runner) lets the destructor pass the
`tx_globaldb_` teardown point (still null) while the detached migration thread then
creates the GlobalDB inside `InitDatabase()` — after teardown — leaking it and its
rebroadcast thread forever.

Why it started failing at be1ca5f5's lane: the regression range changed NO node/CRDT
lifecycle code — only ColdStorageManager diagnostics and `6888b9ca1` (`-Wl,-ObjC` on
Apple, Oct 30 17:57, i.e. right after the last passing run). `-ObjC` force-loads all
static-archive members, registering static dtors that previously never ran /
reordering them — the exit-time destruction of the libp2p logging global now races
the pre-existing leaked thread, deterministically on OSX Debug (Release passed on
timing).

## Fix (surgical — SuperGenius/src/account/GeniusNode.cpp)

1. **`StateTransition()`** — double-checked shutdown gate: after acquiring
   `lifecycle_mutex_`, re-check `shutdown_started_` and bail before running the
   state body. Prevents any state body (incl. `InitDatabase`) from starting after
   shutdown began.
2. **`ShutdownForDestruction()`** — drain barrier: right after the
   `shutdown_started_` CAS succeeds, acquire+release `lifecycle_mutex_`. This waits
   for any in-flight state body to complete, so every member read below
   (`tx_globaldb_` in particular) observes final state; the existing
   `tx_globaldb_->ShutdownNow()` then stops and joins the CRDT rebroadcast worker.
   Recursive mutex (safe if ever re-entered); barrier sits before io teardown so
   bodies can still complete; bounded by one state body.

Non-goals: restructuring the rebroadcast loop's strong-`self` hold (latency
semantics risk — follow-up candidate); guarding `libp2p::log::createLogger` against
a destroyed system (can't detect destruction portably).

## Verification

- Build SuperGenius (Windows local) + run `network_config_private_network_test` and
  `network_config_precedence_test` (same fail-close base note).
- macOS lanes validate on the next tag-build CI run.

## Files

- `SuperGenius/src/account/GeniusNode.cpp` (2 edits)
