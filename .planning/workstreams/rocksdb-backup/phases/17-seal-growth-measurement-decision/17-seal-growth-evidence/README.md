# Seal-Growth Evidence Runbook (D-08/D-09, v1.2 Phase 17 plan 17-02 Task 3)

How to reproduce every number in `seal_growth_evidence.json` / `seal_growth_table.md`.

## The binary

- Source: `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp` (gtest target `cold_seal_growth_test`)
- Build: `cmake --build SuperGenius/build/Windows/Release --config Release --target cold_seal_growth_test --parallel 8`
- Built binary: `SuperGenius/build/Windows/Release/test_bin/Release/cold_seal_growth_test.exe`

## Working directory

Run from `SuperGenius/build/Windows/Release/test/src/crdt` — the fixture roots are `test-data/cold-seal-growth/...` **relative to that directory** (the CMake default test working directory; ctest runs land there too).

## Env gates (NAMES only — never values in committed captures)

| Name | Effect | Default |
|---|---|---|
| `SGNS_SEAL_BIG_ENABLE` | set ⇒ the big legs run (growing 10⁶→10⁷ dataset, cold variants, 10⁸ extrapolation); unset ⇒ loud labelled skip | unset |
| `SGNS_SEAL_SCALE` | floor/grow target scale | 1000000 |
| `SGNS_SEAL_BIG_SCALE` | big-leg target scale | 10000000 |
| `SGNS_SEAL_REPEATS` | enumeration passes per point (variance input) | 3 |
| `SGNS_SEAL_SEED` | dataset seed baked into content strings | 20261118 |
| `SGNS_SEAL_DEPTH` / `SGNS_SEAL_FANOUT` / `SGNS_SEAL_MIX` | spectrum shape knobs (deep/wide/mixed) | 64 / 8 / 50 |

## Reproduce procedure

1. Build the target (command above).
2. `cd SuperGenius/build/Windows/Release/test/src/crdt`
3. For a from-scratch dataset: delete `test-data/cold-seal-growth/grow` (the persistent root is never wiped by the harness itself; regeneration is an operator act, documented here). The floor/fidelity/density roots are wiped per run automatically.
4. Set the big-leg gate (NAME only): `SGNS_SEAL_BIG_ENABLE=1` (PowerShell: `$env:SGNS_SEAL_BIG_ENABLE = "1"`).
5. Run the full binary (all four legs in one process — floor → fidelity → density → big): `..\..\..\test_bin\Release\cold_seal_growth_test.exe`
6. The status lines + `[evidence-json]` blobs print to stdout (the transcript IS the run capture); per-leg flat JSONs land under each fixture root (`floor/evidence-floor.json`, `fidelity-hot/evidence-fidelity.json`, `density/evidence-density.json`, `grow/evidence-big.json`).
7. Ungated re-run (`SGNS_SEAL_BIG_ENABLE` unset) exercises only the Tier-1 lane posture: floor + fidelity + density green, big leg **skips loudly** naming `SGNS_SEAL_BIG_ENABLE`.

## Files

- `README.md` — this runbook
- `seal_growth_evidence.json` — machine-readable aggregate of the canonical run (nested; the 10⁸ block carries `"extrapolated": true`)
- `seal_growth_table.md` — rendered human table (10⁸ rows labeled EXTRAPOLATED)
- `run-capture.md` — the canonical run's transcript (status lines + verdicts)

## Redaction

Run before every commit of captures: credential-value shapes must match zero times; env VALUES are never committed (NAMES only, per the table above).
