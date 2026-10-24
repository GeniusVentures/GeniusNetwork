---
phase: 08-spill-on-write-background-drainer
review: 08-REVIEW.md
recorded: 2026-10-24
counts:
  critical: 1
  major: 3
  minor: 3
  advisory: 6
---

# Phase 8 Review Disposition

Per-finding triage of `08-REVIEW.md`. Default state is `open`; `fixed` rows
carry the fixing commit. Code review is advisory in GSD - nothing here
blocks phase completion, but CR-01 and MA-02 were fixed immediately as
Rule-1/Rule-2 deviations (real defects).

| ID | Severity | Title | Disposition | Note |
|----|----------|-------|-------------|------|
| CR-01 | critical | ODR: stub + real TU both compiled on ON builds | fixed | `fix(08)` SuperGenius `6ad3aa481` - exclusive `if/else` source lists; verified ON vcxproj compiles only the real TUs, OFF only the stub, full battery green both ways |
| MA-01 | major | Config `prefix` parsed/validated but S3 key prefix hardcoded | open | Plan-locked: 08-01 Task 1 step 2 mandates keyPrefix `v1/blocks`; `options.prefix` is a Phase-7-declared optional knob awaiting its consumer. Candidate follow-up before Phase 9 or with the first real deployment config |
| MA-02 | major | Unguarded throwing library Opens in the factory | fixed | `fix(08)` SuperGenius `6ad3aa481` - factory body wrapped in try/catch(std::invalid_argument) mapping to the loud outcome failure |
| MA-03 | major | DrainOnce phase (i) buffers whole pending set under the mutex | open | Design-level: bounded batch size would cap mutex hold + memory; D-01's letter is still proven (SC1 p99 ~2 ms at 200 pending). Revisit with deep-journal evidence (Phase 11 GC naturally shrinks pending) |
| MI-01 | minor | notify without holding wait_mutex_ (lost-wakeup window) | open | At worst delays pickup/Stop-join by one backoff interval; grace+join correctness unaffected. Cheap follow-up |
| MI-02 | minor | Rate-limiter state touched in catch path without cold_store_mutex_ | open | Publisher path is serialized under dagMutex_ in production (single writer), so no race today; latent only if multiple writers ever share a decorator |
| MI-03 | minor | Persistent drain failure with sub-warn backlog is log-invisible | open | Watermark alarm covers the growth signal; per-cycle failure logging is a noisy-hot-path tradeoff - defer to the metrics surface (milestone-Future) |
| AD-01 | advisory | Backpressure defaults duplicated in parser + factory | open | Deliberate defense-in-depth (parser normalizes file configs; factory defends programmatic ones); acceptable duplication |
| AD-02 | advisory | Status triple cannot distinguish disabled/starting/unhealthy | open | D-08 defines the three fields as the minimum; extending is additive |
| AD-03 | advisory | SC1 benchmark flake surface (absolute p99 on loaded machines) | open | 2 ms vs 100 ms budget = ~50x headroom; acceptable |
| AD-04 | advisory | backoff_cap_ms < drain_interval_ms accepted silently | open | Parser could loud-fail the inverted pair; additive validation |
| AD-05 | advisory | Stale comments at the seams | open | Cosmetic |
| AD-06 | advisory | Asset/doc nits | open | Cosmetic |

**Net:** 2 fixed (1 critical, 1 major), 11 open (0 blocking). The open
majors (MA-01 prefix wiring, MA-03 bounded snapshot) are recorded here and
in STATE for the phase-9+ planner to weigh.
