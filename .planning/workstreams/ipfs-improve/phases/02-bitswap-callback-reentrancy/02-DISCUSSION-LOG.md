# Phase 2: Bitswap Callback Reentrancy - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-12
**Phase:** 2-Bitswap Callback Reentrancy
**Areas discussed:** Late-registration semantics, Reentrancy test breadth, Fix surface breadth

---

## Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Late-registration semantics | SC3 allows replay or fail-fast for callbacks registered on completed requests | ✓ |
| Reentrancy test breadth | TEST-01 letter (cancel-only) vs BSTP-05 letter (cancel + chain) | ✓ |
| Fix surface breadth | Audit C-7 letter / D-05 carry-forward vs literal "every internal Bitswap mutex" | ✓ |
| None — agent decides details | All remaining areas are locked or HOW-mechanics | |

## Late-registration semantics

### Q1: Policy for AddCallback on a terminal-state request

| Option | Description | Selected |
|--------|-------------|----------|
| Replay terminal result | Completed request remembers its outcome; late callback invoked with stored result; consumers never silently miss | ✓ |
| Fail fast | AddCallback returns failure; callback never invoked; every consumer needs a "missed it" path | |
| Agent decides | Researcher/planner choose based on call-flow feasibility | |

### Q2: Replay timing

| Option | Description | Selected |
|--------|-------------|----------|
| Sync at registration | Callback runs before AddCallback returns, after any held mutex released; matches SC3 "immediately" | ✓ |
| Posted to io_context | Replay on a later cycle; nothing consumer-authored on the registering stack; ordering less predictable | |

### Q3: Replayable outcomes

| Option | Description | Selected |
|--------|-------------|----------|
| Both outcomes | Symmetric: late subscriber to a timed-out request gets stored REQUEST_TIMEOUT | ✓ |
| Success only | Asymmetric contract; errors fail fast; two code paths | |
| Agent decides | Keep contract symmetric if feasible | |

### Q4: Retention of completed entries

| Option | Description | Selected |
|--------|-------------|----------|
| Until replaced | Stay in requestContexts_ marked complete; replaced on next same-CID request; no sweeps | ✓ |
| Bounded retention | Configurable count/duration then swept; new machinery | |
| Agent decides | Minimal mechanism without unbounded growth | |

## Reentrancy test breadth

### Q1: Reentrant behaviors proven by tests

| Option | Description | Selected |
|--------|-------------|----------|
| Cancel + chain | Both BSTP-05 flavors: reentrant cancel-own-request AND chain-new-request completing | ✓ |
| Cancel-only minimum | TEST-01 letter only; chaining half unverified behaviorally | |
| Cancel + chain + nested | Adds depth-2 reentrancy; risks testing the harness | |

### Q2: Expressing "without deadlock"

| Option | Description | Selected |
|--------|-------------|----------|
| Bounded-step assert | Assert io_context drains and handlers ran within bounded steps; red assertion, no wall-clock | ✓ |
| Inline, hang-detected | Deadlock hangs until CI timeout; simpler, not diagnosable | |

### Q3: UAF evidence

| Option | Description | Selected |
|--------|-------------|----------|
| Add ASan run (Windows) | MSVC /fsanitize=address run in Windows build tree | |
| Stepping only | shared_ptr guarantee + drain assertions; no new build config | |
| Other → ASan in WSL | User freeform (see Notes) | ✓ |

**User's choice:** ASan in WSL (freeform)
**Notes:** "I generally find it difficult to get asan to compile on windows, but you could run in WSL in ~/gnus/GeniusNetwork/thirdparty. Don't try to use git on WSL though, SSH passphrase is needed and i've never been able to get that working, you'll have to sync files over."

### Q4: Cross-coverage test

| Option | Description | Selected |
|--------|-------------|----------|
| Include replay test | Live callback reentrantly registers on a completed request; sync replay inside the callback | ✓ |
| Keep separate | Areas isolated; collision point untested | |

## Fix surface breadth

### Q1: How far the fix surface extends

| Option | Description | Selected |
|--------|-------------|----------|
| Block-request only | BitswapRequestContext + outer integration (requestContexts_, messageSent, processReceivedBlocks); honors D-05 | ✓ |
| Sweep all dispatch sites | Inventory every callback invocation in bitswap.cpp incl. ContentRequestContext; amends D-05 | |
| Sweep, fix only C-7-shaped | Inventory + fix same-shape findings; middle path, scope risk | |

### Q2: Inventory of out-of-scope sites

| Option | Description | Selected |
|--------|-------------|----------|
| Inventory for evidence | Read-only dispatch-site inventory; findings as v2 candidates; concrete SC1 scoping evidence | ✓ |
| Declaration only | Record scoping decision; no inventory work | |

### Q3: Branch strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Continue same branch | Commits land on dev_timer_correctness (HEAD e2dc906); single pin chain from d2ec18af | ✓ |
| Fresh branch from HEAD | Cleaner separation; two-branch pin chain for Phase 4 | |

## The agent's Discretion

- shared_from_this() lifetime mechanics during dispatch and reentrant Cancel()
- Lock-scoping shape of request-map erase vs dispatch
- Replay storage shape (retained context entry vs separate completed-record)
- Test naming/placement (extend existing file vs sibling)
- WSL sync mechanics and ASan toolchain choice
- io_context stepping mechanics (no sleeps)

## Deferred Ideas

- Non-block-request dispatch-site fixes (from D-10 inventory) — v2 candidates, own branch
- ContentRequestContext hardening (Phase 1 carry-forward) — v2 candidate
