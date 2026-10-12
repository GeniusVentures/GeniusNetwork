# Phase 1: Bitswap Timer Correctness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-12
**Phase:** 1-bitswap-timer-correctness
**Areas discussed:** Timer injection seam, Race-test home, P1↔P2 boundary, Content-ctx scope

---

## Timer injection seam

| Option | Description | Selected |
|--------|-------------|----------|
| Ctor default param | `BitswapRequestContext(io_context, time_duration = seconds(5))` — one-line change; production call sites untouched; tests construct the context directly with millisecond-class durations; matches ContentRequestContext's member-based duration | ✓ |
| Bitswap-level knob | Thread a timeout through Bitswap's constructor/setter so tests drive the public `RequestBlock()` path — black-box, but the four orderings can't be driven deterministically without real peers/streams | |
| Test-only setter | Keep the ctor; add `SetResponseTimeoutForTest()` — smallest public change but a test-only hook baked into production code | |

**User's choice:** Ctor default param
**Notes:** Follow-up on depth: duration-only injection chosen — the real `deadline_timer` stays, determinism from tiny durations + single-threaded `io_context` stepping; no timer abstraction/mock enters the production header.

---

## Race-test home

| Option | Description | Selected |
|--------|-------------|----------|
| ipfs-bitswap-cpp only | New test file in the fork's own suite — ships with the fix, serves as a Phase-4 content-probe marker, self-contained; risk: Windows buildability of that suite must be proven during research (AsyncIOManager as documented fallback) | ✓ |
| AsyncIOManager only | Proven Windows binary path (`thirdparty/AsyncIOManager/build/Windows/Debug/test_bin/Debug/`) — but divorced from the fix repo; a Phase-4 repin wouldn't carry the tests | |
| Both | Canonical tests in ipfs-bitswap-cpp plus a mirrored smoke test in AsyncIOManager — two files to keep in sync | |

**User's choice:** ipfs-bitswap-cpp only
**Notes:** Windows runnability of the ipfs-bitswap-cpp suite is an explicit research task, not an assumption.

---

## P1↔P2 boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Restructure once | Phase 1 ports the full in-file pattern (flag + explicit cancel + callback move-outside-lock in one pass); Phase 2 owns reentrancy guarantees and TEST-01, still verifies BSTP-04; avoids two sequential fork branches rewriting the same ten lines | ✓ |
| Strict minimal P1 | Phase 1 lands flag + cancel + ec-check only; callbacks stay under `mutex_` as today; cleanest phase traceability but Phase 2 rewrites the lines Phase 1 just restructured | |

**User's choice:** Restructure once
**Notes:** The porting template is `ContentRequestContext` at bitswap.cpp:575-600, twenty lines from the broken code.

---

## Content-ctx scope

| Option | Description | Selected |
|--------|-------------|----------|
| Block requests only | Phase 1 touches only `BitswapRequestContext` — exactly what BSTP-01..03 and the audit P0 name; ContentRequestContext's residual unsynchronized `timedOut` read recorded as deferred backlog | ✓ |
| Harden both | Also fix the content context's unlocked `timedOut` read + single-terminal guarantee while in the file — grows the Phase-4 probe surface beyond locked requirements | |

**User's choice:** Block requests only
**Notes:** Deferred item captured in CONTEXT.md Deferred Ideas, not silently dropped.

---

## Todo cross-reference

| Option | Description | Selected |
|--------|-------------|----------|
| Review only | Vulkan capability-probe deadlock todo matched Phase 1 only on keyword "path" (score 0.2) — spurious; logged as reviewed-not-folded | ✓ |
| Fold into Phase 1 | Pull the Vulkan deadlock todo into Phase 1 scope | |

**User's choice:** Review only

---

## the agent's Discretion

- Fork-branch naming for the ipfs-bitswap-cpp branch cut from `d2ec18af`
- Race-test file and GTest case naming
- `io_context` stepping mechanics (`poll()` vs `run_one()`) — any sleep-free approach acceptable

## Deferred Ideas

- ContentRequestContext hardening (unsynchronized `timedOut` read in `checkContentRequestComplete`) — v2 candidate
- TEST-01 full suite extension (reentrant cancel-own-request, callback-move-out verification) — Phase 2 per the D-04 split
