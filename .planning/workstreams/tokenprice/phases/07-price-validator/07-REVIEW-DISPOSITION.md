---
phase: 07
review: 07-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: open
    title: "Non-finite stats.min/stats.max silently disables the band check (fail-open)"
  - id: WR-02
    severity: warning
    disposition: open
    title: "Env-seconds overflow guard is off by one — 2^63 literal reaches an out-of-range double→int64 cast (UB)"
  - id: IN-01
    severity: info
    disposition: open
    title: "libcoinprices ships PriceValidator.o with an undefined external; the linking constraint exists only in a test-comment"
  - id: IN-02
    severity: info
    disposition: open
    title: "Non-default tolerance never flows through ValidatePrice; window diagnostics never asserted"
  - id: IN-03
    severity: info
    disposition: open
    title: "Unused <cmath> include in the test"
  - id: IN-04
    severity: info
    disposition: open
    title: "Configure-time absolute source path baked into the binary (pre-existing, in-scope file)"
open: 6
total: 6
recorded: 2026-10-06T20:45:00.000Z
---

# Phase 07: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| WR-01 | warning | open | - |
| WR-02 | warning | open | - |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| IN-04 | info | open | - |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.

Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.

Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.
