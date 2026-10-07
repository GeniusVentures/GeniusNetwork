---
phase: 08
review: 08-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: fixed
    title: "Unchecked `.front()` on empty payout vector — undefined behavior in the regime-2 release builder"
  - id: WR-02
    severity: warning
    disposition: fixed
    title: "`priceManager_` mutex added for the consensus thread but not applied to both `reset()` sites — remaining data race"
  - id: WR-03
    severity: warning
    disposition: fixed
    title: "Regime-2 refund is single-shot — transient release-construction failure permanently strands the poster's escrow"
  - id: WR-04
    severity: warning
    disposition: fixed
    title: "Backstop rejection leaks the claim lock — rejected task remains network-visible as locked, and only the 10s expiry cleans it up"
  - id: IN-01
    severity: info
    disposition: open
    title: "Slot-key handler fallback can slot a malformed rejection subject under the proposer's account id"
  - id: IN-02
    severity: info
    disposition: open
    title: "Hardcoded `\"escrow-hold\"` type literal duplicated at the new check site"
  - id: IN-03
    severity: info
    disposition: open
    title: "First-rejector trigger is best-effort with no fallback re-proposal"
  - id: IN-04
    severity: info
    disposition: open
    title: "Misleading test variable name `era_10`"
open: 4
total: 8
recorded: 2026-10-07T20:24:36.455Z
---

# Phase 08: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| WR-01 | warning | fixed | 08-REVIEW-FIX.md |
| WR-02 | warning | fixed | 08-REVIEW-FIX.md |
| WR-03 | warning | fixed | 08-REVIEW-FIX.md |
| WR-04 | warning | fixed | 08-REVIEW-FIX.md |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| IN-04 | info | open | - |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.
