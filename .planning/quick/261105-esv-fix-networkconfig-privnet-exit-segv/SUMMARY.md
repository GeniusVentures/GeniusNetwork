---
gsd_summary_version: "1.0"
task: Fix network_config_private_network_test OSX-Debug exit-time SegFault (tag-build run 41936126485)
status: complete
completed: 2026-11-05
commit: b85778ef6
repo: SuperGenius (dev_blockstore)
---

# Summary

## Outcome

Fixed. Root cause was a shutdown-vs-async-init race in `GeniusNode` that leaked a
CRDT rebroadcast worker thread to process exit; the macOS `-ObjC` link change
(6888b9ca1, right after the last passing run 41024756227) registered static dtors
that previously never ran, turning the leak into a deterministic exit-time SEGV on
OSX Debug when the leaked thread called `libp2p::log::createLogger` on the
destroyed logging global.

## Evidence chain

- Run 41936126485 `build (OSX, Debug)`: all 7 gtest cases PASS, binary SegFaults
  at exit (crash captured by the new round-13 crash-report step).
- Artifact `macos-Debug-crash-reports-41936126485-1`: crashed thread =
  rebroadcast `std::async` worker → `RebroadcastHeads` → `GetPeerInfo` →
  `TcpListener::enumerateNetworkInterfaces` → `createLogger` → `getGroup` →
  `unordered_map::find` SEGV @ 0x60.
- Regression range 72e540004..be1ca5f51 changed no node/CRDT lifecycle code —
  only ColdStorageManager diagnostics and the `-ObjC` link flag.
- Leak mechanism: `StateTransition` shutdown gate checked pre-lock;
  `ShutdownForDestruction` never holds `lifecycle_mutex_`; node dropped mid-
  `INITIALIZING_DATABASE` (exactly what this suite does on the fail-close base)
  → `InitDatabase()` creates GlobalDB + rebroadcast worker after teardown read a
  null `tx_globaldb_` → nothing ever stops the worker (async lambda holds strong
  `self`).

## Changes (SuperGenius commit b85778ef6)

- `src/account/GeniusNode.cpp` `StateTransition()`: double-checked shutdown gate
  after acquiring `lifecycle_mutex_`.
- `src/account/GeniusNode.cpp` `ShutdownForDestruction()`: lifecycle drain
  barrier after the `shutdown_started_` CAS so in-flight state bodies complete
  before teardown reads members; existing `tx_globaldb_->ShutdownNow()` then
  stops/joins the CRDT workers.

## Verification

- Windows Release: `network_config_private_network_test` 7/7, exit 0;
  `network_config_precedence_test` 6/6, exit 0; no teardown stalls (suite
  runtime unchanged ~23.7s).
- macOS confirmation pending next tag-build CI run (crash was OSX-Debug-only in
  manifestation).

## Follow-up candidates (not done here)

- Restructure `CrdtDatastore::StartRebroadcastHeads` strong-`self` hold (like
  the HandleNext loop) so a dropped datastore can't pin itself — riskier
  (changes rebroadcast wake latency semantics), needs its own phase/plan.
- Guard `libp2p::log::createLogger` against a dead/absent logging system for
  exit-time robustness (thirdparty patch).
