# Phase 18: User Setup Required

**Generated:** 2026-11-19
**Phase:** 18-role-downgrade-collectibility-policy-gc-walk-gap-exemption (plan 18-03)
**Status:** Incomplete

Complete these items to run the Tier-3 dev-gated live leg. The Tier-1 hermetic legs (cold_downgrade_e2e_test, cold_gc_walk_gap_exempt_test) need NOTHING — this setup is opt-in live-wire confirmation only (D-03/D-11 both-tiers posture).

## Environment Variables

| Status | Variable | Source | Add to |
|--------|----------|--------|--------|
| [ ] | `SGNS_BLOCKSTORE_TEST_MINIO_BIN` | MinIO community-server release download (https://min.io/server) — the established v1.1 TEST-03 gate; NEVER the license-gated minio.exe | shell environment when invoking ctest |

## Account Setup

None — the suite spawns the MinIO server itself on `127.0.0.1:19795` with fixed credentials (`minio-dev` / `minio-dev-secret`).

## Dashboard Configuration

None.

## One-Time Bucket Creation

The installed library surface has no MakeBucket — create the bucket once per data dir:

```bash
mc alias set downgrade-smoke http://127.0.0.1:19795 minio-dev minio-dev-secret
mc mb --ignore-existing downgrade-smoke/downgrade-smoke
```

(The server must be answering first — the suite spawns it only during a gated run; start a throwaway server on the same data dir for the one-time `mc mb`.)

## Verification

After completing setup, verify with:

```powershell
$env:SGNS_BLOCKSTORE_TEST_MINIO_BIN = "<path-to-minio-community-binary>"
ctest --test-dir SuperGenius/build/Windows/Release -C Release -R "cold_downgrade_live_smoke_test" --output-on-failure
```

Expected: `LiveStack_DowngradeTimelineWithExemptionWalk` runs (not skipped) — archive seed, interlock fire, ack-armed prune cycle (erased > 0, marker PRUNED, refusal HISTORY_PRUNED_LOCALLY), and one post-prune GC pass surviving via the exemption (walk-exempted > 0). Without the env gate the suite loud-skips by design — that is the recorded posture, never silence.
