# Phase 1: Audit - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-08
**Phase:** 01-audit
**Areas discussed:** Audit deliverable format, Static analysis tooling strategy, Boundary analysis depth, Findings classification & severity

---

## Audit Deliverable Format

| Option | Description | Selected |
|--------|-------------|----------|
| Markdown document with tables | Standalone CONCURRENCY-MAP.md with tables per data domain | ✓ (Recommended) |
| Annotated source code | Comments/annotations directly in bitswap.hpp/cpp | |
| Both — document + annotations | Both standalone doc and inline annotations | |

**User's choice:** Markdown document with tables
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| Full structured report | Data domains table, lock call-chain analysis, boundary crossing matrix, thread-entry-point inventory, findings summary | ✓ (Recommended) |
| Compact data domain table | Just member→guard→FLAGGED classification | |
| Method-by-method narrative | Narrative per method + locks + threads | |

**User's choice:** Full structured report
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| Every member + every call site | Exhaustive inventory including helper structs | ✓ (Recommended) |
| Mutex-level domain map | Document which methods acquire which locks | |
| Member-level map + summary | Both levels | |

**User's choice:** Every member + every call site
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| Severity in the table | CRITICAL/HIGH/MEDIUM/LOW column in data domains table | ✓ |
| Separate findings section | Neutral inventory, severity in separate section | |
| Severity in table + detail in findings | Both approaches | |

**User's choice:** Severity in the table
**Notes:**

---

## Static Analysis Tooling Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| TSAN only | Compile with -fsanitize=thread | |
| TSAN + Clang annotations | Add -Wthread-safety annotations | |
| TSAN + Helgrind | Valgrind lock ordering | |
| TSAN + annotations + Helgrind | All three | |

**User's choice:** Free-text — "I'm on windows. Also compiling bitswap can be somewhat difficult as part of monolithic thirdparty, much less with TSAN or clang, as this is usually done with msvc. This is a difficult question."
**Notes:** Windows/MSVC build constraint makes TSAN/Clang setup impractical for Phase 1.

| Option | Description | Selected |
|--------|-------------|----------|
| Manual audit now, TSAN in Phase 2 | Code audit on Windows, defer tooling | |
| Isolated Bitswap TSAN build | Separate Clang+TSAN build of just Bitswap | |
| Manual audit only, no TSAN | Pure source review, never set up tooling | ✓ |
| Clang annotations as lightweight check | Header-only annotations, MSVC ignores them | |

**User's choice:** "Lets do a manual audit only, I may set up for other methods with WSL later."
**Notes:** Manual audit only. WSL-based tooling possible in future.

| Option | Description | Selected |
|--------|-------------|----------|
| Unprotected shared state first | Focus on missing locks | |
| Balanced — all categories | Equal weight to all thread-safety categories | ✓ (Recommended) |
| Thread entry-point inventory | Document which thread each method runs on | |

**User's choice:** Balanced — all categories
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| Audit them as shared state | Include BitswapRequestContext/ContentRequestContext in inventory | ✓ (Recommended) |
| Skip — strand-confined by design | Assume io_context confines them | |
| Light review — verify confinement | Brief check, don't fully trace | |

**User's choice:** Audit them as shared state
**Notes:**

---

## Boundary Analysis Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Audit all consumer call sites | All Bitswap usage in SuperGenius/processing and GeniusNode | ✓ (Recommended) |
| Document API contract only | Document thread-safety contract, let consumers self-verify | |
| Audit key integration points only | GeniusNode init + processing layer only | |

**User's choice:** Audit all consumer call sites
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| Trace libp2p dispatch | Read libp2p source for handler/event-bus threading | ✓ (Recommended) |
| Flag as assumption | Note that callbacks arrive on unknown thread | |
| Focus on Bitswap's lock safety | Ignore caller thread, verify locks internally correct | |

**User's choice:** Trace libp2p dispatch
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| Note discrepancy, trace via callbacks | Document that Bitswap has no direct RocksDB dependency, trace through consumer code | ✓ |
| Verify and defer to Phase 3 | Explicitly verify, leave threading implications to Phase 3 | |
| Quick grep, move on | Minimal check, minor boundary | |

**User's choice:** Note discrepancy, trace via callbacks
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| Trace AsyncIOManager threading | Read AsyncIOManager source for io_context thread model | ✓ (Recommended) |
| Document Bitswap assumption | Note what Bitswap assumes (serialized handlers) | |
| Focus on timer/callback safety | io_context strand safety regardless of thread pool | |

**User's choice:** Trace AsyncIOManager threading
**Notes:**

---

## Findings Classification & Severity

| Option | Description | Selected |
|--------|-------------|----------|
| CRITICAL/HIGH/MEDIUM/LOW | Standard security-style impact scale | ✓ |
| BLOCKING/WARNING/INFO | Ship-or-block orientation | |
| P0/P1/P2/P3 | Bug-severity mapping | |

**User's choice:** CRITICAL/HIGH/MEDIUM/LOW
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| Category column too | Missing Lock, Lock Order/Deadlock, Async Safety, etc. | ✓ (Recommended) |
| Severity only — implicit by section | Categories implicit from audit section | |
| Structured finding template | Detailed per-finding template | |

**User's choice:** Category column too
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| CONFIRMED/SUSPECTED flag | Distinguish provable from probabilistic findings | ✓ (Recommended) |
| No confidence flag — all equal | All findings are source-review findings | |
| Confidence in evidence description | Describe why in evidence, no separate flag | |

**User's choice:** CONFIRMED/SUSPECTED flag
**Notes:**

| Option | Description | Selected |
|--------|-------------|----------|
| Master findings table | Single table at end with all columns | ✓ (Recommended) |
| Inline per section | Findings in relevant analysis sections | |
| Both — inline + master summary | Per-section inline AND summary table | |

**User's choice:** Master findings table
**Notes:**

---

## the agent's Discretion

- Exact table column layout and section ordering within CONCURRENCY-MAP.md
- How to categorize edge-case findings spanning multiple categories
- Level of detail in lock call-chain diagrams

## Deferred Ideas

None — discussion stayed within Phase 1 scope.
