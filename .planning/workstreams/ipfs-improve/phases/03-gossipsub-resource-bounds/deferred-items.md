# Phase 03 Deferred Items (out-of-scope discoveries)

Recorded during 03-02 execution. None block the phase; all are pre-existing,
in files this phase's prohibitions forbid touching.

## 1. Upstream assert on gater-rejected secured-connection close (Linux Debug)

- **File:** `thirdparty/libp2p/src/transport/impl/upgrader_session.cpp:88`
  (`Assertion 'close_res' failed` in `UpgraderSession::onSecured`)
- **Found during:** 03-02 Task 2 (D-12 WSL ASan run, `BlockedPeerRedialRejected`)
- **Behavior:** when the connection gater rejects a peer mid-upgrade, closing
  the secured connection returns an error; the unchanged upstream code
  `assert(close_res)`s. Windows builds log `Cannot close secured connection
  rejected by gater: invalid argument` and continue (no abort — different
  assert semantics); Linux Debug builds abort. NOT an AddressSanitizer
  finding (zero occurrences in both ASan logs); pre-existing at 28f6a629.
- **Effect on evidence:** `BlockedPeerRedialRejected` cannot complete inside a
  Linux Debug (ASan) process; it passes on the Windows primary suite. The
  ASan full-suite run therefore excluded exactly this one case
  (`--gtest_filter='-*BlockedPeerRedialRejected'`): 16 ran, 15 passed,
  1 pre-existing failure (MutipleGossipSubObjectsOnSingleChannel),
  0 AddressSanitizer findings.
- **Suggested owner:** libp2p fork maintenance (error handling, not bounds).

## 2. Shared raw fixture teardown can crash a FOLLOWING test (Windows)

- **File:** `thirdparty/ipfs-pubsub/test/src/gossip_pubsub_bounds_test.cpp`
  (`SharedRawPeer` / `BlockedPeerRedialRejected` teardown; lingering fixture
  callbacks)
- **Found during:** 03-02 Task 1 full-suite runs — a test registered after
  `BlockedPeerRedialRejected` crashed in `SetUp()` with SEH 0xc0000005
  (intermittent). 03-02 sidestepped it by registration order (raw-fixture
  tests last); the root cause (late fixture callbacks touching destroyed
  state) is NOT fixed.
- **Suggested owner:** TEST-02 fixture hardening (e.g., quiesce the shared
  raw peer before test end, or make `DialAndSubscribe` callbacks
  self-owned instead of stack-referencing).

## 3. Intermittent process exit-hang after suite summary (Windows)

- **File:** same bounds-test process (static `RawGossipPeer` teardown at
  process exit; observed on both WSL and Windows runs).
- **Behavior:** suite summary prints, then the process sometimes never exits
  (one Windows full run and both ASan watchdog runs needed a post-summary
  kill). Test results are complete before the hang; non-blocking for
  evidence (summary is the assertion surface).
- **Suggested owner:** same as item 2.
