---
phase: 01-bitswap-timer-correctness
plan: 01
source: 01-REVIEW.md
reviewed: 2026-10-12
triaged: 2026-10-12
counts:
  critical: 0
  major: 0
  minor: 3
  info: 6
  total: 9
---

# Review Disposition — Phase 01 / Plan 01-01

Source: `01-REVIEW.md` (0 critical / 0 major / 3 minor / 6 info). All 7 review-focus
checks PASS; the reviewer independently re-verified the race suite (7/7 ×2), the
regression binary, and the plan's acceptance greps. Nothing blocks. Dispositions
below keep every finding distinguishable from a forgotten one; fixes are deferred
to keep the branch at exactly the four phase-1 commits (plan acceptance criterion:
`git log d2ec18af..HEAD` lists exactly port, harness, Cancel, extended tests).

| ID | Severity | Finding (file:line) | Disposition | Rationale / Owner |
|----|----------|---------------------|-------------|-------------------|
| MIN-01 | minor | `test/CMakeLists.txt:113-141` — race-test target omits `CXX_STANDARD 17 / CXX_STANDARD_REQUIRED ON` the three sibling targets declare | open → Phase 2 harness extension | 2-line hardening; compiles today via transitive flags. Fold into Phase 2's TEST-01 extension commit (it touches this block anyway) rather than adding a 5th commit that breaks the plan's exact-commit-count acceptance |
| MIN-02 | minor | `src/bitswap.cpp:134` — `Cancel()` destroys user callbacks under `mutex_` (under-lock destruction hazard class D-04 prevents on the dispatch path) | open → Phase 2 (BSTP-04/05) | Plan-conformant as written (plan prescribes `clear callbacks_` under the lock); move-out-then-destroy is a one-line change that belongs with Phase 2's reentrancy hardening of the same function family |
| MIN-03 | minor | `test/...race_test.cpp:76-79` — ordering-2 `@when` doc comment still describes the abandoned poll()-batch mechanism, contradicting the accurate `@note` | open → Phase 2 doc pass | Documentation accuracy only; assertions and `@note` are correct. Fix alongside Phase 2's harness extension |
| INF-01 | info | race test file-header SC4 summary stale (says "zero-millisecond / poll()-family"; actual −1 ms / `run_one()`) | open → Phase 2 doc pass | Cosmetic |
| INF-02 | info | `src/bitswap.hpp:130-135` — `@mutex` contract comment omits `Cancel()` as a `mutex_` acquisition site | open → Phase 2 doc pass | T-1-04 audit anchor completeness |
| INF-03 | info | orderings 1 and 3 are byte-equivalent drives under two names; "CancelBeforeExpiry" confusable with consumer `Cancel()` | open → Phase 2 harness extension | Semantic duplication is intentional (tracer + expansion provenance); rename if Phase 2 touches them |
| INF-04 | info | `Cancel()`/timeout leave contexts in `requestContexts_` (lifecycle shape pre-existing) | open → Phase 2 | Pre-existing lifecycle behavior outside Phase 1 scope (D-05) |
| INF-05 | info | flag-drops-late-TIMEOUT covered only via equivalent late-`HandleResponse` paths | accepted (documented platform limitation) | Full resolution recorded in the ordering-2 `@note` and SUMMARY; deterministic equivalent coverage proven |
| INF-06 | info | `AddCallback`-on-completed silently registers a never-invoked callback | open → Phase 2 | Explicit plan deferral (Phase 2 owns AddCallback-on-completed-context handling) |

**Net effect on phase completion:** none — advisory gate, zero critical/major. The
three minors are triaged to Phase 2 with rationale; the plan's prohibitions,
threat-model mitigations (T-1-01..T-1-05), and D-01..D-06 conformance all verified
PASS by the reviewer.
