# 12-soak-evidence — Wall-Clock Soak Runbook & Evidence Trio (TEST-02 SC3 / D-07 / D-09)

Purpose: the dev-gated wall-clock soak for the cold-storage integration
(`cold_storage_wallclock_soak`, Tier3, env-gated — NEVER in the Tier-1
lane) and its committed evidence trio. The soak demonstrates D-06
bounded-journal semantics literally for the soak duration: publishes
never stop during s3d outages, the journal never multiplies (pending
never exceeds distinct published CIDs), the watermark alarms and
recovers, and the journal drains after every outage window. The D-09
true kill-9 leg proves restart reconciliation at process level.

## The binary

- Source: `SuperGenius/test/src/crdt/cold_storage_wallclock_soak.cpp`
- Build: `cmake --build SuperGenius/build/Windows/Debug --config Debug --target cold_storage_wallclock_soak`
- Working directory for a run: `SuperGenius/build/Windows/Debug/test_bin/Debug`
  (the fixture roots are `test-data/cold-storage-wallclock/{hot,cold}`
  relative to the working directory — the SAME dirs are reused by the
  resume relaunch).
- Hermetic: `InMemoryS3Client` / `InMemoryS3AdminClient` fakes only —
  no live s3d/MinIO endpoint, no Docker.

## Env gates (NAMES only — never values in captures)

| Env var | Meaning |
|---------|---------|
| `SGNS_COLD_STORAGE_SOAK_ENABLE` | must be set (any non-empty) to run; unset = loud labelled skip |
| `SGNS_COLD_STORAGE_SOAK_DURATION_MIN` | soak minutes (default 30; 20–40 is the accepted window; the evidence run used 20 + a 17-minute resume) |
| `SGNS_COLD_STORAGE_SOAK_RESUME` | set (=1) for the kill-9 resume mode: same-dir reopen + journal-driven fake pre-load + reconciliation assertions, then the continued soak |

## Run procedure (reproducing the evidence)

1. Launch run 1 from the working directory:
   `SGNS_COLD_STORAGE_SOAK_ENABLE=1 SGNS_COLD_STORAGE_SOAK_DURATION_MIN=20 ./cold_storage_wallclock_soak.exe`
   (redirect stdout to a log — the timestamped `[status ...]` lines ARE
   the status capture). The scenario cycles HEALTHY (2 min) → OUTAGE
   (1 min) windows; publishes never stop; `[status]` lines sample every
   5 s with watermark/pending/accepted/durable/staging/remote-object
   counts.
2. During an OUTAGE window the process prints
   `[kill-window ...] KILL WINDOW OPEN: outage + pending=N` — that is
   the kill point (pending > 0 proves outstanding journal work at the
   crash).
3. Execute the TRUE kill-9 (no atexit, no flush):
   - Windows: `Stop-Process -Id <pid> -Force`
   - POSIX: `kill -9 <pid>`
   Note the kill timestamp and the last pre-kill status line.
4. Relaunch in resume mode against the SAME fixture dirs with the
   REMAINING duration:
   `SGNS_COLD_STORAGE_SOAK_ENABLE=1 SGNS_COLD_STORAGE_SOAK_RESUME=1 SGNS_COLD_STORAGE_SOAK_DURATION_MIN=17 ./cold_storage_wallclock_soak.exe`
   The resume mode re-derives the published set from the on-disk
   journal (`ForEach`), pre-loads the in-memory fake with every object
   whose Put the killed manager had completed (Accepted AND Durable
   records — a real remote holds those across a crash), then asserts
   first-poll reconciliation: the object set converges to the journal
   set exactly (nothing lost, nothing duplicated — createOnly
   convergence), pending drains to zero, watermark returns to None.
   Labelled `[resume ...] RECONCILIATION:` lines mark each stage. The
   soak then runs out the remaining duration and closes with the
   end-of-run drain + `remote == published` equality.

## The D-06 assertion contract the captures demonstrate

- Every publish succeeded during outages (journal-first discipline; a
  failed publish aborts the run).
- `pending` never exceeded `published` at the 5-second sample points
  (no-multiply — retries never duplicate journal records; the journal
  is unbounded by design, alarm-only).
- `watermark` transitions None → Warn → Critical during outage windows
  (with the warn/critical thresholds at 500/1000 pending) and recovers
  to None after each heal; under sustained outages the held-watermark
  heartbeat repeats at 60 s cadence.
- `remote_objects` converges to `published` after every recovery drain
  and holds the exact equality through end of run.

## Kill-9 procedure (summary)

When to kill: a mid-run `[kill-window ...] KILL WINDOW OPEN` line (an
outage window with pending > 0). Windows:
`Stop-Process -Id <pid> -Force`. POSIX: `kill -9 <pid>`. Then the
resume-mode relaunch above. Expected reconciliation: see step 4.

## Files

- `README.md` — this runbook.
- `run-capture.md` — the run transcript: commands, the kill timestamp
  with the pre-kill pending count, the relaunch, and the
  reconciliation lines.
- `status-capture.txt` — timestamped status-line excerpts from both
  processes: watermark transitions, a held-watermark heartbeat,
  no-multiply sample points, the recovery drain, and the post-relaunch
  reconciliation convergence.

## Composition notes

- The wall-clock composition carries no CRDT layer, so the retention GC
  is OFF here (age 0 = the D-02 absent=off posture); the gc_* status
  fields stay zero by design. The GC-inhibition-during-outage actor is
  covered at Tier-1 by the iteration soak
  (`cold_storage_soak_test` → `IterationSoak_OutageThenRecovery_...`).
- Env var NAMES only appear in this evidence set; the redaction grep
  (credential-value shapes = 0 matches) ran over all three files
  before commit.
