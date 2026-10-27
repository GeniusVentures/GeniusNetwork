---
phase: 10-flush-gated-durability-advancement
review: 10-REVIEW.md
date: 2026-10-27
reviewer: gsd-code-reviewer
total: 12
fixed: 6
open: 6
---

# Phase 10 Review Disposition

Source: `10-REVIEW.md` (0 critical · 1 major · 3 warnings · 4 minor · 4 info).
Fix commits: sgns-blockstore `73c4d4d` (MA-01, MI-03, MI-04), SuperGenius `f3ea082fd` (WR-01, WR-02, WR-03). Both Tier-1 lanes re-run green post-fix (library 14/14, SuperGenius 6/6).

| ID | Severity | Finding (abridged) | Disposition | Rationale / commit |
|----|----------|--------------------|-------------|--------------------|
| MA-01 | major | `std::stoi` port parse throws out_of_range / accepts junk, escaping the outcome contract to an uncaught startup exception | fixed | Digits-only range-checked manual parse returning a construction failure; sgns-blockstore 73c4d4d |
| WR-01 | warning | Stop() final flush used the admin client without `admin_mutex_` (latent concurrent httplib use vs RefreshStagingStats) | fixed | Both final-flush admin calls moved under `admin_mutex_`; SuperGenius f3ea082fd |
| WR-02 | warning | Tick-path `UpdateStagingHealth` ran outside `admin_mutex_`, so the shared failedUploads baseline could interleave with a concurrent refresh | fixed | Success-path health evaluation moved INSIDE the lock scope (failure paths already were); f3ea082fd |
| WR-03 | warning | Enumeration-failure path never advanced `last_flush_attempt_` - sustained scan failures retried every drain tick | fixed | The failure branch now advances the flush clock before engaging backoff; f3ea082fd |
| MI-01 | minor | `marked = snapshot.size()` on the void batched result inflates `durable_count_` when records vanish mid-cycle (skip-and-continue) | open (accepted) | Advisory status only; the journal is the truth, counts re-seed exactly at restart, and the plan-pinned library signature returns `result<void>`. Carry to Phase-11 planner if GC consumes the counter (prefer journal-derived counts there) |
| MI-02 | minor | `GetColdUploadState` maps transient RocksDB errors to `NoRecord`, conflating absent with unreadable | open (deferred) | Real concern for the Phase-11 GC inhibitor (eviction must not key off "NoRecord" that is really an IO error). Carry to Phase-11 planner as an entrance decision (distinguish Unreadable from NoRecord at the bridge) |
| MI-03 | minor | Unguarded `.value()` in wire-test construction helpers (terminate-policy kills the binary on failure) | fixed | ADD_FAILURE guard in MakeClient + the budget test's construction assert; 73c4d4d |
| MI-04 | minor | Windows-only BlackholeListener registered unconditionally; close-then-join edge | fixed | `#ifdef _WIN32` + `GTEST_SKIP` elsewhere; the accept-unblocks-on-close path is documented in the listener; 73c4d4d |
| IN-01 | info | `admin_reachable_last_tick_` written but never read | open (accepted) | Dead-state observation; kept as the natural extension point for a future heartbeat line. Non-blocking |
| IN-02 | info | connect + read each get the full budget (2x worst-case call time) | open (accepted) | Conservative direction (longer bound, never shorter); the shutdown test's margin covers it. Documented here |
| IN-03 | info | PollUntil deadline == flush floor in the two shutdown-final-flush tests (timing coupling) | open (accepted) | The tests poll to a STATE (accepted count), not to the floor; the deadline is a bound, not a precondition. No flake observed across repeated runs |
| IN-04 | info | userinfo embedded in `admin_endpoint` would echo into LogSummary | open (accepted) | Misuse hardening; the endpoint is operator-controlled local config (same trust as `endpoint`). Note for the ops doc if s3d deployments ever allow userinfo |

**Blocked findings: 0.** MI-01/MI-02 are carried to the Phase-11 planner (both touch the GC-inhibition contract); the remaining opens are accepted with rationale.
