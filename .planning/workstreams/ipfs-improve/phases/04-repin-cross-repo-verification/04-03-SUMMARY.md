---
phase: 04-repin-cross-repo-verification
plan: 03
subsystem: infra
tags: [msbuild, abi, rebuild, gtest, genius-sdk, tlog, verification]

requires:
  - phase: 04-repin-cross-repo-verification (plans 01, 02)
    provides: clean bitswap worktree at f899393 + the D-11 baseline logs; the content-proven pin chain (dev_ipfs_p0 @ 97b648a -> root 2e46a2f)
provides:
  - Refreshed integrated Debug tree: three thirdparty packages clean-rebuilt + INSTALLed with 3/3 MD5 hash-equal deployed headers and fresh fix-marker-carrying libs (the live ABI split healed)
  - Bounded SuperGenius rebuild (5 lib projects + 4 focus targets, all /t:Rebuild) with D-08 markers 12/12 True and the D-11 zero-new-failures comparison GREEN (repin runs fully green vs fully-green baseline)
  - GeniusSDK build-only proof: GeniusSDKService Build succeeded with D-16 tlog True x3 against the repinned deployed libs; nothing executed
  - 04-VERIFICATION.md - the phase evidence assembly (quoted outputs throughout)
affects: [milestone v1.0 closeout (this is the final phase)]

actuals:
  tokens: 21000   # chars/4 over the phase-dir evidence + VERIFICATION + SUMMARY set written by this plan (log files are raw capture artifacts, excluded)
  tasks: 3
  commits: 1     # the docs evidence commit (plus zero production commits by design)

tech-stack:
  added: []
  patterns: [deployed-header ABI recipe (inner rebuild -> INSTALL -> MD5 audit -> clean dependents), tlog link-input audit as SDK evidence standard, bounded disk recovery (delete only non-evidence fresh-build outputs)]

key-files:
  created:
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-VERIFICATION.md
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/rebuild-install-audit.txt
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/repin-pubsub_counts_test.log
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/repin-globaldb_integration_test.log
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/repin-pubsub_graphsync_test.log
    - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/repin-transaction_sync_test.log
  modified: []

key-decisions:
  - "libp2p rebuild retargeted from the p2p.vcxproj umbrella (1 TU, 1.25s - the wrapper trap) to protocol/gossip/impl/p2p_gossip.vcxproj (42 TUs, the fix-carrying target) - recorded as a RESEARCH Pattern 2 correction"
  - "Four D-18 adaptations, all operator-visible (two in-session approvals + two build-tree redeploys): AsyncIOManager Debug INSTALL, gnus_upnp Debug INSTALL, gnus_upnp advance to 5aec637, GeniusSDK purpose-built branch from develop + SuperGenius deployment refresh via operator-advised full build + SDK in-place reconfigure"
  "Disk recovery per Pitfall 8: deleted 131 non-focus test exes built by the full build (9.58 GB) after LNK1180; the four focus evidence exes untouched"

patterns-established:
  - "ABI-safe consumer refresh order: refresh the DEPLOYMENT (INSTALL) the consuming repo's cmake actually points at, then reconfigure the consumer in place, then rebuild - a stale deployment explains most cross-repo compile errors"

requirements-completed: [INTG-02, INTG-03]

coverage:
  - id: D1
    description: "D-06/D-07 deployed-tree refresh - three packages rebuilt+installed in order, 3/3 MD5 hash pairs equal, deployed libs fresh, Cancel-marker flipped True"
    requirement: INTG-02
    verification:
      - kind: other
        ref: "rebuild-install-audit.txt: gossip/bitswap/gossip_pubsub hash match=True x3; p2p_gossip 18:29:21 / ipfs-bitswap-cpp 18:31:30 / ipfs-pubsub 18:32:01 vs START 18:28:14; Cancel=True AddCallback=True egress=True ingress=True"
        status: pass
  - id: D2
    description: "D-09/D-10/D-11 bounded SuperGenius rebuild + zero-new-failures comparison"
    requirement: INTG-03
    verification:
      - kind: integration
        ref: "5 libs (31+179+35+21+73 TUs) + 4 targets (2+22+180+180 TUs) /t:Rebuild exit=0; D-08 markers True x12; repin runs 3/3+11/11+1/1+6/6 PASSED; new_failures=0 x4 vs baseline"
        status: pass
  - id: D3
    description: "D-14..D-17 GeniusSDK build-only proof with tlog evidence"
    requirement: INTG-03
    verification:
      - kind: other
        ref: "GeniusSDKService /t:Rebuild Build succeeded=True errors=0 (exe 20:16:22); tlog P2P_GOSSIP=True IPFS-PUBSUB=True IPFS-BITSWAP-CPP=True; nothing executed"
        status: pass
  - id: D4
    description: "04-VERIFICATION.md evidence assembly with quoted outputs and INTG coverage"
    requirement: INTG-02
    verification:
      - kind: other
        ref: "04-VERIFICATION.md: all nine 03-skeleton headings present; INTG-01/02/03 coverage rows; Observable Truths quote actual command outputs"
        status: pass

duration: 150min
completed: 2026-10-14
status: complete
---

# Phase 4 Plan 04-03: ABI Refresh, Bounded Rebuild, Repinned Comparison, SDK Proof

**The integrated Debug tree is healed (3/3 hash-equal deployments, marker flip), the repinned focus runs are fully green against a fully-green baseline (zero new failures), and GeniusSDK builds and links against the repinned libs with tlog-proven consumption - the phase's entire evidence trail assembled and committed.**

## Performance

- **Duration:** ~150 min (three task waves + four D-18 adaptation cycles + one disk recovery)
- **Tasks:** 3/3
- **Commits:** 1 (docs evidence commit; zero production commits by design)

## Accomplishments

- **D-06 refresh:** libp2p (via the gossip-impl target), ipfs-bitswap-cpp, ipfs-pubsub rebuilt + INSTALLed in dependency order; three MD5 hash pairs equal; deployed libs fresh with `Cancel=True` (flipped from verified stale-False), `AddCallback=True` control, egress+ingress True.
- **D-09/D-11:** five lib projects + four focus targets clean-rebuilt (libs before tests); D-08 markers True in every exe (12/12); repinned runs fully green (3/3, 11/11, 1/1, 6/6) vs fully-green baseline - `new_failures=0` x4, no D-13 retries.
- **D-14..D-17:** GeniusSDKService Build succeeded on the purpose-built develop-derived branch; D-16 tlog True x3 (+ networkregistry after in-place reconfigure); SDK binary deliberately not marker-grepped; nothing executed.
- **04-VERIFICATION.md** assembled with quoted outputs across all nine skeleton sections.

## Task Commits

1. **Task 3 evidence commit** - `docs(04): repin evidence - baseline, content probes, rebuild audit, repinned runs, verification` (phase-dir docs only)

## Deviations from Plan

Four D-18 adaptations (all build-tree-only or checkout-drift; two operator-approved in-session; all recorded in rebuild-install-audit.txt and VERIFICATION Regression Notes):

1. AsyncIOManager Debug INSTALL (stale 22/24 deployed headers; unblocked coinprices).
2. gnus_upnp Debug INSTALL (stale deployment vs its own worktree).
3. gnus_upnp worktree 8bb78b8 -> 5aec637 (operator-approved; UPNP::New factory required by SuperGenius develop).
4. GeniusSDK `dev_ipfs_p0_sdkverify` derived from develop (operator-directed) + SuperGenius Debug deployment refresh via operator-advised full build (`cmake --build . --parallel 8 --config Debug`, ~10 min) + INSTALL + SDK in-place cmake reconfigure (networkregistry.lib).

Plus: libp2p retarget (p2p umbrella -> p2p_gossip impl target; Pattern 2 correction) and the Pitfall-8 disk recovery (131 non-focus fresh-build exes deleted, 9.58 GB; evidence exes untouched).

**Impact:** none on the phase goal - every adaptation unblocked pre-existing workspace integration debt; the pinned content, probes, and comparison evidence are untouched by all four.

## Issues Encountered

- LNK1180 (disk) during SDK link -> resolved by the bounded deletion above.
- TEST-02's known post-summary exit-hang recurred at pin time (04-02) - captured-then-killed, documented.

## User Setup Required

None.

## Next Phase Readiness

Phase 4 is the final phase of milestone v1.0 (IPFS P0 Remediation). All three requirements verified; the milestone is ready for completion review. Follow-up candidates surfaced (non-blocking): stale Debug deployments of non-repinned packages, gnus_upnp origin/main merge, GeniusSDK/SuperGenius deployment cadence, MAJ-01 (Phase 3 advisory).

---
*Phase: 04-repin-cross-repo-verification - Plan 03*
*Completed: 2026-10-14*
