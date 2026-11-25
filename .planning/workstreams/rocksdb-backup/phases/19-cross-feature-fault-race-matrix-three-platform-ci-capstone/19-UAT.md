---
status: complete
phase: 19-cross-feature-fault-race-matrix-three-platform-ci-capstone
source: [19-VERIFICATION.md, notes/19-cross-feature-fault-race-three-platform-capstone.md, 19-05-SUMMARY.md, 19-FRESH-CLONE-CHECKLIST.md]
started: 2026-11-25T20:24:00Z
updated: 2026-11-25T20:24:00Z
---

## Current Test

[testing complete]

> RETROACTIVE RECORD (close-out reconciliation, 2026-11-25): this UAT was
> NOT an interactive session. Phase 19's human-judgment items were ruled
> live at the 19-05 Task-3 evidence checkpoint (2026-11-20) and during the
> D1-D8 dispatch close-out (2026-11-23..25), and every ruling is recorded
> in the committed rulings docs. This file canonicalizes those committed
> rulings as tests-with-rulings -- the same retroactive treatment phases
> 13/15/16/17 received on 2026-11-24. No new user input was solicited.

## Tests

### 1. D8 non-cold transverse load-class ruling (closing dispatch)

expected: the closing dispatch D8 (run 45504484532, 2026-11-24, @ 41776b0c0
-- the final HEAD) shows Tier-1 20/20 GREEN on BOTH OSX configs with zero
cold-suite failures; the only full-lane failures are the two NON-cold
transverse load-class suites (multi_account_test SEGFAULT on OSX-Release;
transaction_sync_test ~50 s internal deadline expiries on OSX-Debug), both
ruled non-blocking load-class: multi_account passed D3/D5/D6/D7 on this
branch and on develop's OSX-Debug Nov-19 (478 s); transaction_sync was green
D5/D6/D7 on this branch and green on develop Nov-19 at 124.6 s. Under the
D-12 contract (cold-labeled failures are NEVER quarantined; non-cold entries
are load-class documentation), these do not block the capstone and receive
NO exclusion added by phase 19.
result: pass (ruled -- load-class, non-blocking)
verified_by: notes/19-cross-feature-fault-race-three-platform-capstone.md
Dispatch 8 table + THE CLOSING EVIDENCE TABLE (section e); 19-05-SUMMARY.md "The
Dispatch Trail" item 8; 19-FRESH-CLONE-CHECKLIST.md "Recorded checkpoint
rulings (final)" Expected-outcome-vs-actual MET paragraph.

### 2. X11 one-green promotion re-ruling (2026-11-20, met at D4)

expected: the X11 promotion bar was re-ruled at the Task-3 checkpoint
(2026-11-20) from two-consecutive-greens to ONE green dispatch of
build-release-tags.yml (run_tests=true, cold_storage=true) with all three
desktop platforms green on X11 specifically -- the permanent Tier-1 lane is
the recurrence guard and the dispatch doubles as the D-16 evidence run.
MET: Windows green D3+D4, Linux green D3+D4, OSX D4 full-lane 171/171 with
X11 GREEN and resurrection_test GREEN; zero X11 failures in every subsequent
dispatch (D5-D8), including both closing runs. No silent demotion, no
quarantine entry; the demotion contract (SGNS_CROSS_RACE_FULLWIRE_ENABLE
opt-in, recorded ruling with run IDs) was never triggered.
result: pass (ruled -- one-green bar met on all three platforms)
verified_by: notes/19-* section (d) THE X11 PROMOTION RECORD (D-06) and the
Dispatch 4 table; 19-05-SUMMARY.md "Deviations from Plan" Rule-1 paragraph;
19-FRESH-CLONE-CHECKLIST.md "Recorded checkpoint rulings (final)" item 6
(X11 promotion count: ONE green dispatch, ruled 2026-11-20, met on all three
platforms at D4).

### 3. B1/B2 push-topology ruling (B2 stands -- cmake.yml zero-diff)

expected: B2 CONFIRMED at the Task-3 checkpoint (2026-11-20) and held
through the closing dispatch -- cmake.yml's on.push.branches stays
develop/main (the permanent Tier-1 ON legs are dormant-in-topology for
dev_coldstorage_additions until the v1.2 merge, the v1.1 posture); the B1
alternative (adding the branch to the push filters) DECLINED on runner load
(the full ~28-job matrix per push vs the SG-WIN11 thermal cap and the
gv-OSX-Large tart VM's standing load); B1 remains one line if re-ruled.
Posture re-checked at HEAD 41776b0c0 by the retroactive verifier: no
phase-19 commit touched cmake.yml (last touch predates the phase; push
filters develop/main only) and the Tier-1 lane steps landed only in
build-release-tags.yml (31 additive lines, commit 3b5885d2f).
result: pass (ruled -- B2 posture held, tag-push evidence lane)
verified_by: notes/19-* section (c) "The B1/B2 push-topology ruling" and section (e)
closing status line; 19-05-SUMMARY.md "Key Changes / CI" (cmake.yml
zero-diff, B2 held -- verified at close-out); 19-FRESH-CLONE-CHECKLIST.md
"Recorded checkpoint rulings (final)" item 5 (B2 STANDS, ruled 2026-11-20,
re-confirmed through the closing dispatch).

### 4. CloudflareWARP local-environment ruling (2026-11-24, environmental)

expected: the dev box's local Tier-1 rerun (2026-11-24 evening, post-fix)
failed exactly the two two-node/two-GlobalDB wire-delivery gates --
Resurrect_FullWire (180 s deadline) and X11's prologue gate (60 s, B
durable=0 pending=0, zero gossip connections) -- while Cloudflare WARP's
tunnel adapter was Up. Both cases were GREEN locally earlier the same day
(Tier-1 20/20, pre-WARP) and X11 was green on CI at the same HEAD ~3 h
prior (D8). Ruled ENVIRONMENTAL (WARP breaks local libp2p loopback dials),
NOT code: no fix was made to either case; CI remains the verifier; the
runbook's CloudflareWARP entry (check Get-NetAdapter for CloudflareWARP
first) is the documented home for recurrence.
result: pass (ruled -- environmental, local-only; no code action)
verified_by: notes/19-* Dispatch 7 "Local-environment note (2026-11-24
evening, post-fix)" and section (c) runbook item 1 (CloudflareWARP adapter is
ENVIRONMENTAL on the Windows runner); 19-05-SUMMARY.md "Deviations from
Plan" Local-environment-finding paragraph (recorded, not a deviation).

## Summary

total: 4
passed: 4
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

None. All four rulings trace to committed evidence homes (the notes doc's
dispatch tables, 19-05-SUMMARY, 19-FRESH-CLONE-CHECKLIST) and were
re-checked against the SuperGenius tree at HEAD 41776b0c0 by the
retroactive verifier (see 19-VERIFICATION.md). The two load-class suites
from ruling 1 remain SuperGenius-side debt outside phase-19 scope (the
D-12 quarantine contract documents them; multi_node smoke Q7 stays flagged
[ASSUMED] pending promotion-time verification -- no exclusion was ever
built on it).
