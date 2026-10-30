# SC4 VM Isolation Runbook — cold storage residuals (rounds 7–8)

Target: SSH into `gv-osx-large` (tart VM, M2 Ultra) once runners are back.
Context: run 41024756227 residuals — OSX fault_race 600s timeout (Rewarm case),
resurrection full-wire 180s deadline (0 candidates). Round 8 (`56175311`) adds
`~WindowGate()` leak-proofing + eligibility diagnostics.

## 0. Get round-8 binaries on the VM

The leftover CI build dir is round 7 (`72e54000`) — no diagnostics. Either:

- Re-dispatch the workflow once (tag `test_coldstorage` already points at `56175311`;
  inputs: `tag=test_coldstorage thirdparty_tag=test_coldstorage zkllvm_tag=develop
  run_tests=true cold_storage=true` — BOTH flags), then reuse its build dir, OR
- On the VM: `cd SuperGenius && git fetch && git checkout test_coldstorage &&
  make -C build/OSX/Debug -j16 cold_storage_fault_race_test cold_storage_resurrection_test`

Build dir (from CI logs): `/Users/gnus-cicd/actions-runner/_work/SuperGenius/SuperGenius/SuperGenius/build/OSX/Debug`

## 1. The decisive isolation ladder (run in order)

Always export the CI env first:

```bash
export SGNS_TEST_P99_BOUND_MS=2000
export GTEST_FILTER='*-LocalPriceManagerTest.*:ConsensusPendingLifecycleTest.CertificateCallbackStallsUntilPostCommitReadbackCanReleaseSameSlot:TrustFirstBootE2ETest.TransientRefreshRetryExhaustionIsCappedCoalescedAndIdle'
```

**Exp A — the two failures solo, no load** (contention-free baseline):
```bash
ctest -R "cold_storage_fault_race_test|cold_storage_resurrection_test" -j 1 --output-on-failure
```
- FAIL here → NOT contention at all: the VM environment itself (scheduling/IO) breaks
  them; parallelism was never the cause. Grep the resurrection log for the NEW line
  `gc: eligibility - scanned=... state=...` — it names the gate directly.
- PASS → go to Exp B.

**Exp B — all 12 cold storage concurrent** (cold-vs-cold contention):
```bash
ctest -R "cold_storage|cold_read" -j 12 --output-on-failure
```
- FAIL → cold-storage co-scheduling is the conflict (contradicts the M2 Pro result —
  then it's VM-specific co-scheduling). Note which pairs collide.
- PASS → go to Exp C.

**Exp C — full CI replica at 24-way** (the real CI posture; this is the one config
local hardware could never reach):
```bash
ctest . -j 24 -C Debug --output-on-failure -LE requires_foundry
```
- FAIL reproduces CI → contention with the heavy neighbors (processing/MNN/Metal tests).
  Re-run with the processing tests excluded to bisect:
  `ctest . -j 24 -C Debug -LE "requires_foundry|processing|child_tokens" --output-on-failure`

## 2. What to capture on failure

- **resurrection**: `grep "gc: eligibility" <log>` — the per-gate breakdown
  (scanned/stamped/skew/age/reachable/state) explains the 0 candidates.
  `state=` high → durability gate; `age=` high → clock/retention issue;
  `scanned=0` → journal enumeration sees nothing (drain never marked them).
- **fault_race if it STILL times out** (round 8 should have converted the hang into
  an ASSERT failure — a fresh 600s hang would be a NEW deadlock path, possibly the
  round-7 pass mutex): during the hang, on the VM:
  ```bash
  sample $(pgrep -f cold_storage_fault_race_test) 10 -file /tmp/fault_hang.txt
  ```
  The all-threads stacks name the deadlocked pair directly.

## 3. Known-separate (do not conflate)

`processing_datatypes/nodes/conformance_*`, `child_tokens` — MNN init aborts
(NSException in `MNN::registerBackend`), started with the MoltenVK-static thirdparty
rebuild, also fail locally on the M2 Pro. Different investigation; on the VM they
fail solo too if it's the same regression.

## Expected outcomes cheat-sheet

| Exp A | Exp B | Exp C | Conclusion |
|---|---|---|---|
| FAIL | — | — | VM environment breaks the tests even idle → host-specific defect |
| PASS | FAIL | — | cold-vs-cold co-scheduling conflict |
| PASS | PASS | FAIL | neighbor-contention deadline failures (budgets/diagnostics fix) |
| PASS | PASS | PASS | intermittent — needs the CI run itself + eligibility logs |
