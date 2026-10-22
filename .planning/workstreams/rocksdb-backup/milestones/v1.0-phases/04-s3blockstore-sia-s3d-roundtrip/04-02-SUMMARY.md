---
phase: 04-s3blockstore-sia-s3d-roundtrip
plan: 02
subsystem: database
tags: [sia, s3d, s3, durability, evidence, characterization, c++]

requires:
  - phase: 04-s3blockstore-sia-s3d-roundtrip/04-01
    provides: MinioS3Client adapter (three-shape 412 classifier + IsAuthoritativeAbsence), tier registration pattern
provides:
  - s3d_spike_test (env-gated S3D-TIER live spike, loud CI skip, never manages s3d)
  - Five committed live-evidence artifacts under docs/evidence/s3d-spike/ (stats triple, staged-read headers, sdk-error-shapes)
  - docs/s3d-durability.md - the S3D-03 characterization finding (repo's first prose doc)
  - Durability.hpp ObjectStoreAccepted citation of the finding (D-12)
affects: [04-03 live tiers, Phase 5 fault matrix, future durability polling]

actuals:
  tokens: 9000
  tasks: 3
  commits: 3

tech-stack:
  added: [mc (MinIO client, W:\gnus\mc.exe - dev tool only, sha256-pinned, never referenced by the build)]
  patterns:
    - "Evidence-cited characterization: every doc claim traces to a committed artifact or the pinned tag source (D-13)"
    - "Live-tier env gating: runtime loud-skip, never a CMake gate; test only connects, never manages the server (D-08)"

key-files:
  created:
    - thirdparty/sgns-blockstore/test/s3d_spike_test.cpp
    - thirdparty/sgns-blockstore/docs/evidence/s3d-spike/README.md
    - thirdparty/sgns-blockstore/docs/evidence/s3d-spike/stats-before-put.txt
    - thirdparty/sgns-blockstore/docs/evidence/s3d-spike/stats-after-put.txt
    - thirdparty/sgns-blockstore/docs/evidence/s3d-spike/stats-after-flush.txt
    - thirdparty/sgns-blockstore/docs/evidence/s3d-spike/staged-read-headers.txt
    - thirdparty/sgns-blockstore/docs/evidence/s3d-spike/sdk-error-shapes.txt
    - thirdparty/sgns-blockstore/docs/s3d-durability.md
  modified:
    - thirdparty/sgns-blockstore/test/CMakeLists.txt (s3d_spike_test tier)
    - thirdparty/sgns-blockstore/include/sgns-blockstore/Durability.hpp (citation)

key-decisions:
  - "D-05 contingency NOT executed: s3d v0.2.1 HEAD-missing classifies NATIVELY as authoritative absence (NoSuchKey: prefix) - IsAuthoritativeAbsence unchanged"
  - "412 renders as mapper SHAPE 1 ('PreconditionFailed: ...' XML-parsed prefix) - absorbed to alreadyPresent success slot; three re-puts idempotent at the live endpoint"
  - "The finding: no per-object staged-vs-durable signal at v0.2.1 - pipeline-global counters only, activeUploads transient; accepted-is-max-provable IS the ceiling; POST /objects/flush (blocking) is the only staged-to-durable primitive"
  - "Buckets are S3-API objects (CreateBucket via any SigV4 client) - s3d's CLI has no bucket subcommand and the admin API has no bucket endpoints (verified against the tag's openapi.yml)"

patterns-established:
  - "ASCII capture discipline enforced: PS '>' redirect produced UTF-16LE stats files (the 03-04 anti-precedent, again) - content intact, converted; staged-read noise (PS error wrappers) stripped"
  - "Env re-sourced per terminal command for live sessions - terminal identity is not stable across commands; every live command self-contains `. W:\gnus\s3d-spike-env.ps1`"

requirements-completed: [S3D-03]

coverage:
  - id: D1
    description: "s3d_spike_test instrument: builds in the default lane, loud-skips [SGNS_BLOCKSTORE][S3D-TIER] naming missing vars when env unset, contains no process-management tokens, tier-registered per the 03 pattern"
    requirement: S3D-03
    verification:
      - kind: unit
        ref: "ctest -R s3d_spike_test unset-env lane (skip label present, exit 0)"
        status: pass
      - kind: automated
        ref: "Source token gates (env-var names, createOnly chain, no forbidden process tokens)"
        status: pass
  - id: D2
    description: "Live spike session evidence: both S3dSpike cases green at the real v0.2.1 endpoint; five artifacts committed (stats triple with pending 0->1->0 / uploaded 0->0->1, staged-read wire dumps with 200-OK-from-staging, sdk-error-shapes with version banner + shape-1 412 + native HEAD absence); scripted secret scan clean; ASCII throughout"
    requirement: S3D-03
    verification:
      - kind: e2e
        ref: "ctest -R s3d_spike_test live run (both cases Passed, 0.58s) - banners transcribed to sdk-error-shapes.txt"
        status: pass
      - kind: automated
        ref: "Verify battery: artifacts present, credential scan (len-40/20/20 values absent), content tokens, no UTF-16LE BOM"
        status: pass
  - id: D3
    description: "docs/s3d-durability.md: six-section S3D-03 characterization - verbatim UploadStats inventory, accepted-is-max-provable finding, concurrency limitation, blocking flush, staged reads with proof-of-absence headers, operational notes; all 7 evidence citations resolve on disk"
    requirement: S3D-03
    verification:
      - kind: automated
        ref: "Doc token gates + citation-resolution check (all pass)"
        status: pass
  - id: D4
    description: "Durability.hpp ObjectStoreAccepted doc comment cites docs/s3d-durability.md (D-12); no code/enum changes; hygiene guards green after the edit"
    requirement: S3D-03
    verification:
      - kind: unit
        ref: "ctest api_hygiene_test + header_hygiene (100% passed post-edit)"
        status: pass

duration: 50min
completed: 2026-10-22
status: complete
---

# Phase 4 Plan 02: s3d Day-One Spike + Durability Characterization Summary

**Live s3d v0.2.1 spike proven green with committed evidence: 412 = mapper shape 1, HEAD-missing classifies natively (no D-05 contingency), and the no-per-object-durability-signal finding now ships as the repo's first prose doc, cited by Durability.hpp.**

## Performance

- **Duration:** ~50 min (3 tasks, incl. the human-gated live session)
- **Commits:** 3 (sgns-blockstore @ main: 43ee95d, a1c2cc9, 950356c)

## Accomplishments

- s3d_spike_test: env-gated S3D-TIER instrument with the raw minio-cpp wire probe (the adapter absorbs the 412 before its text is observable — the raw If-None-Match probe is the evidence source)
- Live session at 127.0.0.1 (s3d v0.2.1, commit 312789a): ConditionalRePutShape achieved→alreadyPresent→alreadyPresent; HeadMissingShape exists=false; bucket created via mc (SigV4-only API)
- Five evidence artifacts committed; stats triple shows the staged→flushed movement on a 38-byte single-supplier workload; staged reads 200-OK before flush with NO distinguishing header (proof of absence)
- docs/s3d-durability.md: six-section characterization, 7/7 citations resolve; Durability.hpp cites it; hygiene guards green

## Deviations from Plan

**[Rule 3 - Environment fact] Buckets are S3-API-only at s3d** - the plan's user_setup implied a CLI/admin path; the tag's openapi has no bucket endpoints and the CLI has no bucket subcommand | Fix: created the bucket with the MinIO client (mc.exe, sha256-pinned download to W:\gnus\ - dev tool, never in the build) via MC_HOST env credentials | Commit: evidence session

**[Rule 3 - Runbook correction] curl-with-Basic-auth cannot hit the S3 API (SigV4 exclusively)** - the plan's runbook step 3 staged-read curl shape assumed basic auth | Fix: staged reads captured via `mc --debug stat/cat` (full SigV4 wire dumps incl. response headers) | Artifact: staged-read-headers.txt

**[Rule 3 - Process fact] Endpoint env carries host:port; BaseUrl takes the port separately** - Fix: host:port split in the test's env parsing (port field set on config + raw BaseUrl)

**[Rule 3 - Encoding discipline] Stats captures initially UTF-16LE (PS '>' redirect - the exact 03-04 anti-precedent)** - Fix: converted to ASCII (content intact, verified byte-clean); staged-read PS error-wrapper noise stripped

**Total deviations:** 4 (all Rule-3 environment/process adaptations). **Impact:** none on plan truths; two runbook corrections recorded for the 04-03 session.

## Issues Encountered

None outstanding. Terminal env persistence is unstable across commands — every live command re-sources the env script (recorded as a pattern).

## Next Phase Readiness

Ready for 04-03: the D-05/D-07 entrance gate is satisfied on real-endpoint evidence; the dev endpoint, bucket (sgns-spike), and env script remain usable for the E2E session.
