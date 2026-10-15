---
phase: 04-repin-cross-repo-verification
verified: 2026-10-14T20:30:00Z
status: passed
score: 8/8 must-haves verified
covered_files:
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-01-PLAN.md
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-02-PLAN.md
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-03-PLAN.md
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-01-SUMMARY.md
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-02-SUMMARY.md
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/04-03-SUMMARY.md
  - thirdparty (gitlink 1cbf85a -> 97b648a via root commit 2e46a2f on dev_persisprocresults)
  - thirdparty/ipfs-bitswap-cpp (gitlink d2ec18af -> f899393 via thirdparty commit 97b648a)
  - thirdparty/libp2p (gitlink 28f6a629 -> a54f5c4 via thirdparty commit 97b648a)
  - thirdparty/ipfs-pubsub (gitlink b6eb6268 -> 5c6653c via thirdparty commit 97b648a)
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/d05-rollback-evidence.txt
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-summary.md
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-pubsub_counts_test.log
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-globaldb_integration_test.log
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-pubsub_graphsync_test.log
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/baseline-transaction_sync_test.log
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/content-probes.txt
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/rebuild-install-audit.txt
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/repin-pubsub_counts_test.log
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/repin-globaldb_integration_test.log
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/repin-pubsub_graphsync_test.log
  - .planning/workstreams/ipfs-improve/phases/04-repin-cross-repo-verification/repin-transaction_sync_test.log
covered_digest: "v2:sha256:2db8577c09b208826f3a9d7466134d7a28ea06ad148bbe1297737d8f325090c9"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
---

# Phase 4: Repin & Cross-Repo Verification Report

**Phase Goal:** The fixes verifiably reach the integrated tree — pinned by content, not by branch name — and the consuming repos build and pass against them
**Verified:** 2026-10-14T20:30:00Z
**Status:** passed → **VERDICT: VERIFIED**
**Re-verification:** No — initial verification

## Goal Achievement

Verification stance: goal-backward, adversarial. Every claim was re-checked against actual
command outputs produced during execution (quoted in the Observable Truths table and the
three evidence transcripts): the D-05 restore (diff-vs-e2dc906 emptiness gate + 13-case
suite + contamination tripwire), the D-04 content probes at the exact pinned SHAs, the
D-06 deployed-tree refresh (MD5 hash audits + marker flips), the D-09/D-11 bounded rebuild
and per-case zero-new-failures comparison, and the D-14..D-17 GeniusSDK build-only proof
with the D-16 tlog audit. Pinned SHAs: ipfs-bitswap-cpp `f899393` (dev_timer_correctness,
7 linear commits from d2ec18af), libp2p `a54f5c4` (dev_gossip_bounds, 2 from 28f6a629),
ipfs-pubsub `5c6653c` (dev_ipfs_fix, 3 from b6eb6268) — lineage proven by
`merge-base --is-ancestor` exit 0 x3 before any pin commit.

### Observable Truths

| # | Truth (from plans/ROADMAP SCs) | Evidence (actual output) |
|---|--------------------------------|--------------------------|
| 1 | INTG-01/SC1 lineage: pinned SHAs are descendants of the recorded integrated gitlinks | `git merge-base --is-ancestor d2ec18af f899393` -> bs-lineage=0; `28f6a629 a54f5c4` -> lp-lineage=0; `b6eb6268 5c6653c` -> ps-lineage=0 |
| 2 | INTG-01/SC1 restore (D-05): bitswap worktree byte-exact at f899393 | `git status --short` -> EMPTY (0 lines) at HEAD f899393 on dev_timer_correctness; gated by `git diff e2dc906 --stat -- <3 files>` -> EMPTY (zero novel content; d05-rollback-evidence.txt 4532 bytes, 9 pattern hits) |
| 3 | D-05 restore proof: 13-case suite green from freshly rebuilt standalone binary + tripwire | `[==========] Running 13 tests` / `[  PASSED  ] 13 tests.` exit=0; ASCII byte-greps `ReentrantCancelOwnRequestNoDeadlock=True LateRegistrationOnTimedOutReplaysRequestTimeout=True`; MSBuild transcript: 6 real .cpp compiles |
| 4 | INTG-02/SC2 content probes at pinned SHAs (six, all non-zero, expected counts) | terminalResult_ 2+2; `TEST( RequestContextRaceTest` 13; max_remote_subscriptions_per_peer 1; violation seam 5 files (connectivity.hpp, gossip_core.cpp/.hpp, stream.cpp/.hpp); BlockPeer 8; kSustainedOverflowClosesToBlock 3 — verbatim in content-probes.txt |
| 5 | D-12 pin-time greens | TEST-01: `[  PASSED  ] 13 tests.` exit=0; TEST-02: `17 tests ran / [  PASSED  ] 16 tests. / [  FAILED  ] 1 test: MutipleGossipSubObjectsOnSingleChannel / 1 DISABLED (SecondStartFailed)`, all 5 GossipPubSubBoundsTest OK |
| 6 | Pin chain landed locally (D-01/D-02/D-03) | thirdparty `dev_ipfs_p0` @ 97b648a, `git show --stat` = exactly `ipfs-bitswap-cpp \| 2 +-`, `libp2p \| 2 +-`, `ipfs-pubsub \| 2 +-`; develop untouched at 1cbf85a; root `2e46a2f` on dev_persisprocresults = single thirdparty gitline (`1 file changed`); `git ls-tree HEAD thirdparty` -> 160000 97b648a...; gnus_upnp/MNN/fmt drift unstaged |
| 7 | Never pushed (plan actions) | thirdparty `branch -r`: no dev_ipfs_p0; upstream tracking empty; root remote list unchanged — no push command exists in any task (T-04-03). Remote-state note: origin/dev_persisprocresults advanced 18:22 by the OPERATOR's own sync (confirmed in-session), not by plan action |
| 8 | D-06 ABI integrity: deployed headers hash-equal to source; libs fresh; marker flip | gossip.hpp F244B5B3...==F244B5B3... match=True; bitswap.hpp (flat) B595B857...==... match=True; gossip_pubsub.hpp 320F16B1...==... match=True (1 deployed hit); p2p_gossip.lib 18:29:21 / ipfs-bitswap-cpp.lib 18:31:30 / ipfs-pubsub.lib 18:32:01 (all after START 18:28:14); `Cancel=True (flipped from verified stale-False) AddCallback=True; egress=True ingress=True` |
| 9 | SC3/D-11 zero new failures vs baseline | Baseline (Sep-15 exes): 1/1, 9/9, 1/1, 6/6 PASSED — zero FAILED lines. Repinned (rebuilt exes): 3/3, 11/11, 1/1, 6/6 PASSED — zero FAILED lines. Per-target `new_failures=0` x4 (counts grew: new cases added to source since Sep-15; all pass). No D-13 retries needed |
| 10 | D-08 markers in every rebuilt focus exe | pubsub_counts/globaldb_integration/pubsub_graphsync/transaction_sync .exe -> egress=True ingress=True overflow=True (12/12 booleans True) |
| 11 | SC4/D-14..D-17 GeniusSDK build-only proof | GeniusSDKService /t:Rebuild -> `Build succeeded: True`, errors: 0 (GeniusSDK.lib 20:16:14, GeniusSDKService.exe 20:16:22); D-16 tlog: `P2P_GOSSIP=True IPFS-PUBSUB=True IPFS-BITSWAP-CPP=True` (+ NETWORKREGISTRY.LIB True); SDK binary deliberately NOT marker-grepped (D-16); NOTHING executed (D-15) |
| 12 | D-09 bounded breadth honored | A6: TransactionManager.cpp -> genius_node_objs.vcxproj, INSIDE closure (genius_node ProjectReferences it) — no sixth project; 5 lib projects (31+179+35+21+73 TUs) then 4 test targets (2+22+180+180 TUs), all /t:Rebuild /p:Configuration=Debug; ipfs-lite-cpp not rebuilt; no Release |

### Prohibition Checks

| Prohibition | Check | Result |
|-------------|-------|--------|
| No push by plan actions | branch -r listings recorded in content-probes.txt; no push command in any task | PASS (operator's own 18:22 sync documented separately) |
| No `git add -A` | commit-stat gates: exactly 3 gitlinks (97b648a), exactly 1 root gitlink (2e46a2f); drift unstaged | PASS |
| Never trust branch names | D-04 probes at exact SHAs; branch names only in provenance notes | PASS |
| No Release builds | every invocation carried /p:Configuration=Debug (audit transcript) | PASS |
| No Select-String on binaries | all binary probes via ASCII-decode byte-grep (E4); Select-String only on text (tlog/logs) | PASS |
| No incremental across header change | /t:Rebuild on all three packages, 5 SG libs, 4 test targets, SDK service | PASS |
| Never run SDK binaries | no execution of GeniusSDKService.exe or examples anywhere in the transcript (D-15) | PASS |
| Never delete baseline exes / whole-tree clean | Sep-15 baseline captured BEFORE any rebuild; only the four repin exes exist in test_bin after cleanup; 131 NON-focus fresh-build exes deleted (Pitfall 8 bounded remedy, audit-recorded) | PASS |
| Focus set never widened | exactly 4 targets run; A3/OQ3 contingency did not fire (no fifth log) | PASS |

### Required Artifacts

- thirdparty branch `dev_ipfs_p0` @ `97b648a` (one pin commit naming f899393/a54f5c4/5c6653c) — exists, never pushed
- Root commit `2e46a2f` on `dev_persisprocresults` (thirdparty gitlink 1cbf85a -> 97b648a)
- `d05-rollback-evidence.txt` (4532 bytes) — D-05 bounded investigation + emptiness gate + conclusion
- `baseline-{pubsub_counts,globaldb_integration,pubsub_graphsync,transaction_sync}_test.log` (17 KB / 389 KB / 768 KB / 3.1 MB) + `baseline-summary.md` (provenance + zero-red ledger)
- `content-probes.txt` (4931 bytes) — six SHA-level probes + D-12 re-runs + never-push proof
- `rebuild-install-audit.txt` — D-06/D-08/D-16 transcript + four D-18 adaptations + disk-recovery record
- `repin-*.log` x4 — gtest transcripts of the repinned runs
- Build-tree evidence (not committed): deployed thirdparty libs/headers x3 refreshed; 5 SG lib outputs + 4 focus exes clean-rebuilt; GeniusSDK.lib + GeniusSDKService.exe rebuilt
- This VERIFICATION.md

### Key Link Verification

1. **Pin chain:** fix HEADs (lineage-verified) -> thirdparty `dev_ipfs_p0` 97b648a (3 gitlinks, surgical) -> root 2e46a2f (`git ls-tree` records 97b648a) — complete chain in local git; branch names provenance-only.
2. **Rebuild chain:** inner vcxproj /t:Rebuild (libp2p via the gossip target — see Deviations) -> INSTALL -> MD5-equal deployed headers (3/3) -> fresh deployed libs (marker flip Cancel True) -> 5 SG lib /t:Rebuilds -> 4 focus /t:Rebuilds -> D-08 markers 12/12 True -> repinned runs zero new failures.
3. **SDK chain:** deployed libs (18:29-18:32) -> in-place cmake reconfigure (picks up reinstalled supergeniusTargets.cmake incl. networkregistry) -> GeniusSDKService link -> tlog shows P2P_GOSSIP / IPFS-PUBSUB / IPFS-BITSWAP-CPP (the repinned deployed paths) — D-16 standard, no binary grep.

### Behavioral Spot-Checks

| Command | Observed | Status |
|---------|----------|--------|
| `bitswap_request_timer_race_test.exe` (rebuilt) | `Running 13 tests` / `[  PASSED  ] 13 tests.` | PASS |
| ipfs-pubsub-test.exe (pin time) | 17 ran / 16 passed / 1 pre-existing fail / 1 disabled; 5/5 BoundsTest OK | PASS |
| `Test-BinMarker` on 4 rebuilt focus exes | egress/ingress/overflow = True x12 | PASS |
| Per-target baseline-vs-repin FAILED-set diff | `new_failures=0` x4 (both sets empty) | PASS |
| `Get-FileHash` gossip.hpp / bitswap.hpp / gossip_pubsub.hpp | deployed == source (3/3 match=True) | PASS |
| SDK tlog grep P2P_GOSSIP/IPFS-PUBSUB/IPFS-BITSWAP-CPP | True/True/True | PASS |

### Requirements Coverage

| Req | Plan(s) | Evidence |
|-----|---------|----------|
| INTG-01 | 04-01 (restore half), 04-02 (lineage + pin) | Truths 1, 2, 3, 6 |
| INTG-02 | 04-02 (SHA probes), 04-03 (binary layer) | Truths 4, 5, 8, 10; encoding rule held (no Select-String on binaries) |
| INTG-03 | 04-01 (baseline), 04-03 (rebuild + comparison + SDK) | Truths 9, 11, 12 |

### Regression Notes (non-blocking)

1. **D-05 rollback origin** — actor undetermined by design (RESEARCH OQ1): mtimes 10/13/2026 1:36 PM, content byte-identical to e2dc906, no stash, no checkout since Oct-12 in reflog; bounded evidence in d05-rollback-evidence.txt; restore safe and proven.
2. **Pre-existing reds:** NONE — the D-11 baseline was fully green (17/17 across 4 targets), making the repin bar strictly "also fully green" — met. TEST-02's MutipleGossipSubObjectsOnSingleChannel pre-existing failure (Phase 3) unchanged at pin time (16/1/1); its known post-summary exit-hang recurred and was handled by capture-then-kill (deferred item 3).
3. **D-18 adaptations (all recorded in rebuild-install-audit.txt; all build-tree-only or checkout-drift, no source edits, nothing committed, nothing pushed):**
   - (1) AsyncIOManager Debug INSTALL — deployed headers were 22/24 (HTTPTypes.hpp missing; tokenprice deployed Release only); unblocked coinprices.
   - (2)+(3) gnus_upnp Debug redeploy, then operator-approved worktree advance 8bb78b8 -> 5aec637 (origin/main adds UPNP::New that SuperGenius develop requires; reversible).
   - (4) GeniusSDK derived onto purpose-built branch `dev_ipfs_p0_sdkverify` from develop ce92a16 per operator direction; SuperGenius Debug deployment (Sep-2, stale GetProcessCost signature / no DevFraction) refreshed by full `cmake --build . --parallel 8 --config Debug` (exit=0, ~10 min, operator-advised) + INSTALL; SDK in-place cmake reconfigure picked up networkregistry.lib.
   - These mismatch classes (stale Debug deployments of non-repinned packages; cross-repo in-flight API races) are pre-existing integration debt of the workspace, NOT effects of the repin — every one predates Phase 4 and blocks only the current-checkout build, not the pinned content.
4. **libp2p rebuild retarget (deviation, recorded):** RESEARCH Pattern 2 named `p2p.vcxproj` (umbrella — 1 TU in 1.25 s, the wrapper trap it warned about); the fix-carrying target is `protocol\gossip\impl\p2p_gossip.vcxproj` (42 TUs incl. all 12 gossip-impl sources). INSTALL then deployed everything.
5. **Disk recovery:** full-tree build left 2.03 GB; SDK link hit LNK1180; 131 NON-focus test exes built that same evening were deleted (9.58 GB reclaimed; the four focus evidence exes untouched) — the Pitfall 8 bounded remedy.
6. **Full SuperGenius build scope note:** the operator-directed full build rebuilt all projects (incremental for the ~50 unaffected ones — ABI-safe because they include none of the three changed headers, include-grep verified; the 5 affected projects had already been /t:Rebuilt clean per D-06).

### Gaps Summary

None against the phase goal. INTG-01, INTG-02, INTG-03 all verified with mechanical,
quoted evidence. Follow-up candidates (out of scope, non-blocking): the four D-18
adaptations point at workspace integration debt (stale Debug deployments; SuperGenius
develop's dependency on unmerged gnus_upnp origin/main state; GeniusSDK develop vs
SuperGenius deployment cadence) — flagged to the operator, not Phase 4 gaps. MAJ-01
(per-peer close-counter eviction, Phase 3 advisory) remains open by design and is
unaffected by the repin (probe-verified content at a54f5c4).

---
_Verified: 2026-10-14T20:30:00Z_
_Verifier: the agent (gsd-verifier)_
