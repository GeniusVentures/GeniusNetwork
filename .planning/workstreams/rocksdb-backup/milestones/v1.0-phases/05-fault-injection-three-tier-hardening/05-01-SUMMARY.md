---
phase: 05-fault-injection-three-tier-hardening
plan: 01
subsystem: testing
tags: [ctest, ci, cmake, test-infra, static-analysis]

requires:
  - phase: 04-s3-blockstore-sia-s3d-roundtrip
    provides: the full 14-registration test battery green on the superbuild tree, the env-gate + loud-skip pattern, and the committed s3d evidence artifacts
provides:
  - Tier LABELS on all 15 ctest registrations readable directly from the test CMake configuration
  - tier1_static_audit ctest - fixed-sleep + non-loopback-host static audit with a registration-vs-label count guard
  - Fail-closed CI lane (-L Tier1 --no-tests=error) in the thirdparty build workflow
  - Human-readable tier inventory doc + repo README (D-16/D-17)
affects: [05-02, 05-03, phase verification]

actuals:
  tokens: 3600
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Fail-closed CI test selection: ctest -L (never -LE) + --no-tests=error + a self-inspecting label-count audit"
    - "Host-literal scanning scoped to string-literal segments to avoid C++ qualified-name false positives"

key-files:
  created:
    - thirdparty/sgns-blockstore/test/tier1_audit_check.cmake
    - thirdparty/sgns-blockstore/docs/testing-tiers.md
    - thirdparty/sgns-blockstore/Readme.md
  modified:
    - thirdparty/sgns-blockstore/test/CMakeLists.txt
    - thirdparty/.github/workflows/build.yml

key-decisions:
  - "D-13/D-14/D-15 realized exactly as planned; the audit's host scan was tightened twice during verification (array-declaration and qualified-name false positives) by scoping host patterns to quoted string segments - recorded as deviations, not plan changes"
  - "The tier1 selection is 12 entries (15 registrations minus the Tier2-only minio store tier and the two Tier3 s3d binaries); the plan's '15-entry battery' wording counts registrations, not the -L Tier1 selection"

patterns-established:
  - "Static-audit pattern: clone the header_hygiene CMake -P shape (SRC_DIR guard, glob, per-line pattern tables, FATAL_ERROR with file:line, final STATUS count) for new source-hygiene tripwires"
  - "Negative-probe verification: planted violations in temp trees prove an audit has teeth before trusting a green real-tree run"

requirements-completed: [TEST-01]

coverage:
  - id: D1
    description: "Tier-enforced, inspectable test configuration: LABELS on all 15 registrations, tier1_static_audit ctest with proven teeth, and the fail-closed CI lane restriction"
    requirement: TEST-01
    verification:
      - kind: unit
        ref: "ctest -L Tier1 in thirdparty/build/Windows/Debug/sgns-blockstore/src/sgns-blockstore-build: 12/12 Passed incl. tier1_static_audit and header_hygiene"
        status: pass
      - kind: other
        ref: "negative probes: planted sleep_for / play.min.io literal / unlabeled addtest each fail the audit (non-zero exit with file:line)"
        status: pass
      - kind: other
        ref: "token gates: 15/15 exact label lines + exact restricted ctest string present; SuperGenius cmake.yml untouched"
        status: pass
    human_judgment: false
  - id: D2
    description: "Human-readable tier inventory (docs/testing-tiers.md) mirroring the labels byte-for-byte with env-gate lists, CI lane line, D-15 no-skip-meta-test note, D-17 evidence-reuse note, plus the new repo README linking it and s3d-durability.md"
    requirement: TEST-01
    verification:
      - kind: other
        ref: "token gates: all 15 test names + all gate env vars + docs/evidence/s3d-spike/ pointer + '-L Tier1' present in testing-tiers.md; both doc links present in Readme.md"
        status: pass
    human_judgment: false

duration: 40min
completed: 2026-10-22
status: complete
---

# Phase 5 Plan 01: Tier Enforcement End-to-End Summary

**The three-tier strategy is now enforced and inspectable from configuration alone: every ctest registration carries its tier LABEL, a self-inspecting Tier-1 audit with proven teeth guards the hermetic contract, and the CI lane is fail-closed to Tier1.**

## Performance

- **Duration:** ~40 min (2 tasks)
- **Tokens (actuals):** ~3.6K over 5 changed files

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 90b7d98 (sgns-blockstore) | tier LABELS on all registrations + tier1_static_audit (D-13/D-14) |
| 1 | 8aca266 (thirdparty) | CI lane restricted to fail-closed -L Tier1 --no-tests=error (D-13) |
| 2 | 1b971f3 (sgns-blockstore) | testing-tiers inventory + repo Readme (D-16/D-17) |
| ptr | 7a57bdc, f8b6421 (thirdparty) | sgns-blockstore pointer bumps |

## What Was Built

- **Labels (D-13):** `set_tests_properties(... LABELS ...)` on all 15 registrations in thirdparty/sgns-blockstore/test/CMakeLists.txt — 8 pure Tier1 binaries, the two `Tier1;Tier2` mixed binaries (hermetic half runs in CI; env-gated live halves loud-skip), `s3_block_store_minio_test` Tier2, both s3d binaries Tier3, plus header_hygiene and the new audit. The shared addtest() macro is untouched.
- **Audit (D-14):** thirdparty/sgns-blockstore/test/tier1_audit_check.cmake (header_hygiene clone) — bans fixed-sleep constructs (sole allowlist: MinioServerHarness.cpp's bounded WaitUntilHealthy poll) and non-loopback host literals (only 127.0.0.1/localhost/::1 allowed; play.min.io explicitly banned), and fails when registrations outnumber LABELS lines. Registered as a Tier1 ctest so it runs in every ctest context including CI.
- **CI lane (D-13):** the "Run sgns-blockstore tests" step in thirdparty/.github/workflows/build.yml now ends with `-L Tier1 --no-tests=error` with the fail-closed rationale recorded in the step comment. SuperGenius cmake.yml untouched (premise correction honored).
- **Docs (D-16/D-17):** thirdparty/sgns-blockstore/docs/testing-tiers.md (15-row inventory, interplay rule, exact CI line, D-15 no-skip-meta-test note, D-17 evidence-reuse note) and the new minimal thirdparty/sgns-blockstore/Readme.md linking it and docs/s3d-durability.md.

## Verification Evidence

- `ctest -L Tier1`: **12/12 Passed** — exactly the hermetic set (Tier2/Tier3-only binaries excluded), including the new tier1_static_audit and header_hygiene rows; the two mixed binaries ran their hermetic halves green.
- Negative probes (teeth): a planted `std::this_thread::sleep_for` alone, a planted `http://play.min.io` string, and an unlabeled `addtest(` registration each fail the audit with a file:line FATAL_ERROR (non-zero exit).
- Token gates: all 15 exact label lines and the exact restricted CI ctest string verified present; testing-tiers.md carries all 15 test names, the complete env-var gate lists, the evidence pointers, and the CI restriction.
- No C++ source changed — the battery running under -L Tier1 is exactly the Phase-4-green set.

## Deviations from Plan

**[Rule 1 - Bug] Audit host-scan false positives (two rounds)** — Found during: Task 1 verification | Issue: the initial bracketed-IPv6 pattern matched `char buffer[4096]` (array declaration), and the compressed-IPv6 tail patterns matched `rocksdb::DB* db` (C++ qualified pointer declarations) — both in real Tier-1 sources, so the audit failed its first real-tree run | Fix: host patterns now run only on double-quoted string segments (host literals reach code only as strings); bracketed literals additionally require a colon; teeth re-proven by the same negative probes (planted `http://play.min.io` string still fails) | Files: thirdparty/sgns-blockstore/test/tier1_audit_check.cmake | Verification: audit Passed in the -L Tier1 lane; sleep-only and host-only probes each fail independently | Commit: 90b7d98 (fixed before commit, contained in the same atomic commit)

**Total deviations:** 1 auto-fixed (Rule 1, two tightly-related fix rounds). **Impact:** none on plan contracts — all D-13/D-14/D-15/D-16/D-17 truths hold as written.

## Self-Check: PASSED

- All tasks executed and committed individually (atomic commits above)
- SUMMARY created in the plan directory
- Acceptance criteria re-verified green (Tier1 lane 12/12, probes 3/3, token gates 15/15 + CI + docs)
- No skip meta-test added anywhere (D-15)
