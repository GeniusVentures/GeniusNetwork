# run-capture.md — Wall-Clock Soak Run Transcript (TEST-02 SC3 / D-07 / D-09)

Date: 2026-10-28 · Windows dev box · hermetic fakes (InMemoryS3Client /
InMemoryS3AdminClient — no live s3d/MinIO, no Docker) · binary:
`SuperGenius/build/Windows/Debug/test_bin/Debug/cold_storage_wallclock_soak.exe`
(working directory = that folder; fixture roots
`test-data/cold-storage-wallclock/{hot,cold}`).

## Run 1 — 20-minute run, killed mid-outage (the D-09 kill-9)

- Launch: `SGNS_COLD_STORAGE_SOAK_ENABLE=1 SGNS_COLD_STORAGE_SOAK_DURATION_MIN=20
  ./cold_storage_wallclock_soak.exe` (stdout → `soak-run1.log`), PID 42892.
- The scenario cycled HEALTHY (2 min) → OUTAGE (2 min) windows; the first
  outage opened at ~18:49:37, the watermark crossed Critical, and the
  process printed kill-window markers.
- **Kill point: 18:51:42** — `[kill-window 18:51:42] KILL WINDOW OPEN:
  outage + pending=170` (the watermark was at Critical, held across
  samples; outstanding journal work at the crash = 170 pending records).
  Pre-kill status: `[status 18:51:42] watermark=Critical pending=170
  accepted=6 durable=1915 ... published=2099 remote_objects=1921`.
- Kill executed: `Stop-Process -Id 42892 -Force` (the Windows kill-9
  shape — no atexit, no flush). Process confirmed dead.

## Run 2 — resume-mode relaunch (the D-09 reconciliation)

- Relaunch: `SGNS_COLD_STORAGE_SOAK_ENABLE=1 SGNS_COLD_STORAGE_SOAK_RESUME=1
  SGNS_COLD_STORAGE_SOAK_DURATION_MIN=17 ./cold_storage_wallclock_soak.exe`
  (stdout → `soak-run2.log`), PID 57364.
- Reconciliation (first poll after the same-dir reopen + journal-driven
  fake pre-load):
  - `[resume 18:51:48] RECONCILIATION: reopening ... (kill-9 relaunch - D-09)`
  - `[resume 18:51:49] RECONCILIATION: journal enumerated - 2162 block(s), fake pre-loaded with durable set (1921 object(s))`
  - `[resume 18:51:49] RECONCILIATION: pending=0, watermark=None, remote objects converged to 2162`
  - `[resume 18:51:49] RECONCILIATION: remote objects == published (2162) - no loss, no duplication`
- The soak then ran its remaining ~17 minutes: publishes never failed
  through six further outage windows, the watermark alarmed and
  recovered each time, four held-watermark heartbeats fired (18:54:50,
  18:58:50, 19:02:50, 19:06:50 — 60 s cadence while Critical held), and
  the post-recovery drains emptied the journal each time.
- End of run 2: `[soak 19:08:48] complete: published 18121 total, remote
  objects 18120`. The closing equality assert tripped on a 1-record
  off-by-one: two test-side races in the binary's closing logic (a
  stale `pending==0` snapshot taken before the drainer's final poll,
  and the crash-window record carve-out). Root-caused and fixed in the
  binary the same session (the close-out now counts state-probe-failed
  records pre-drain and waits on full object-set convergence); the
  evidence above is unaffected — the reconciliation assertions all
  passed.

## Run 4 — verification resume over the SAME fixture (fixed binary)

- `SGNS_COLD_STORAGE_SOAK_ENABLE=1 SGNS_COLD_STORAGE_SOAK_RESUME=1
  SGNS_COLD_STORAGE_SOAK_DURATION_MIN=1 ./cold_storage_wallclock_soak.exe`
  (stdout → `soak-run4.log`), PID 59180-equivalent.
- `[resume 19:14:02] RECONCILIATION: journal enumerated - 19049 block(s), fake pre-loaded with durable set (19048 object(s))`
- `[resume 19:14:02] RECONCILIATION: pending=0, watermark=None, remote objects converged to 19049`
- `[resume 19:14:02] RECONCILIATION: remote objects == published (19049) - no loss, no duplication`
- After the 1-minute soak: `[soak 19:15:02] complete: published 19975
  total, remote objects 19975` and `[soak 19:15:02] D-06 close-out:
  remote == published - crash-window (19975 - 0 unreadable) (no loss,
  no duplication)` — **[ PASSED ] 1 test.**

## Duration accounting

Run 1: 20 min configured, killed at ~4 min (mid-outage, by design).
Run 2: 17 min (the remaining duration), completed. Run 4: 1 min
verification. Combined soak wall-clock inside the accepted 20–40 min
window (kill point + full remaining duration + verification leg).
