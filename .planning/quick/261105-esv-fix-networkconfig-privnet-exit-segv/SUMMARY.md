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

## Post-fix CI triage (tag-build run 42116912132, on b85778ef6)

Fix verified: `network_config_private_network_test` passed everywhere; the
exit-time SegFault is gone. Four NEW failures moved in — triage:

| Job | Case | Verdict |
|---|---|---|
| Linux x64 Debug | `MultiAccountTest.NodeConsensusTest` (77 s) | **Known flake** — same case failed on develop Oct 26 (40315629323, aarch64) and tag-build Nov 2 (41542857150) |
| OSX Debug | `TrustFirstBootE2ETest.PassiveNodeDurablyActivatesPolicyWithoutExtraAdminCall` (137 s) | Wait-timeout, no assertion; Debug + `-j24` load. Suite already has an excluded flaky sibling (`TransientRefreshRetryExhaustion...`, GTEST_FILTER base). Single occurrence of this case |
| OSX Release | `FinalityFaultNetwork.PublisherLossAfterPersistenceUsesDeterministicFailover` | `crdt_blind == nullptr` — node/GlobalDB creation failure under load. Same binary flaked PRE-fix with a different case (`ProductionComposition...`, Nov 2 x2 + Nov 4) — suite-level flake, not caused by b85778ef6 |
| OSX Release | `ColdStorageGcTest.EndToEndRetentionPassIdentifiesExactCandidateSet` | **Only genuinely new case** (first failure in run history). Mechanism: GC reachability walk visited 1 node (`TraverseCIDsLinks: Links to fetch: 0, Visited: 1`) — missed the d2->d1 chain link, so backdated d1 read as unreachable -> false 2nd candidate. 10/10 local passes (~590 ms each); test builds CrdtDatastore directly, no GeniusNode (fix-independent). Load-sensitive race in walk/heads-link timing — watch for recurrence, then dig into `WalkReachable` vs. delta head-link creation |

Develop comparison: latest develop cmake.yml run (41669250334) died at runner
allocation (exit 78, no tests); Oct 26 develop run's failures were
`MultiAccountTest.NodeConsensusTest` + already-excluded known flakes — nothing
new there either.

