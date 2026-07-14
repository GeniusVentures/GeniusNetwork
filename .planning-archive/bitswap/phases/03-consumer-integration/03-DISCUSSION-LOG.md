# Phase 3: Consumer Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-09
**Phase:** 3-consumer-integration
**Areas discussed:** Publish callback migration, Verification depth, Documentation format, Multi-platform build scope

---

## Publish Callback Migration

| Option | Description | Selected |
|--------|-------------|----------|
| Keep on io_context | Temp file cleanup is a fast filesystem op — fine on io_context. No code changes needed. | ✓ |
| Post cleanup to worker thread | If temp file cleanup could block, post to background thread. Adds complexity. | |

**User's choice:** Keep on io_context (Recommended) — no consumer code changes needed in IPFSSaver.

| Option | Description | Selected |
|--------|-------------|----------|
| Document in header | Add Doxygen @note comments above PublishFile/PublishDirectory in bitswap.hpp stating callbacks fire on io_context. | ✓ |
| Keep implicit | No documentation — it's an internal detail. Phase 2 code is self-documenting. | |

**User's choice:** Document in header (Recommended).

| Option | Description | Selected |
|--------|-------------|----------|
| Run IPFSSaver tests | Integration-level verification catches callback lifetime issues Bitswap-only tests might miss. | |
| Bitswap tests sufficient | Phase 2's concurrency_publish_test.cpp already verifies io_context dispatch. | ✓ |

**User's choice:** Bitswap tests sufficient.

**Notes:** PublishFile/PublishDirectory are the primary threading contract change from Phase 2. IPFSSaver callbacks do temp file removal (std::remove) — confirmed safe on io_context.

---

## Verification Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Build success + existing tests pass | Both SuperGenius and AsyncIOManager must compile, link, and pass existing test suites. | |
| Build success only | Verify compilation and linking succeeds. Skip running tests. | |
| Build + tests + code review | Full verification: build, existing tests, plus manual review of each integration call site. | |

**User's choice:** User confirmed builds and tests already pass on primary dev platform.

| Option | Description | Selected |
|--------|-------------|----------|
| Code review only | Review each integration call site for thread-context correctness. No new tests. | ✓ |
| Add CRDT integration test | New test exercising Bitswap→CRDT data flow end-to-end. | |
| Nothing further | Build+tests passing is sufficient. | |

**User's choice:** Code review only (Recommended).

| Option | Description | Selected |
|--------|-------------|----------|
| Thread context correctness | Verify calling thread compatible with Bitswap's post-Phase-2 threading contract at each call site. | ✓ |
| All API changes | Broader review covering thread context + API surface + callback lifetime. | |
| Surface-level | Quick pass: verify headers, compilation, no obvious misuse. | |

**User's choice:** Thread context correctness (Recommended).

**Notes:** Verification bar is low because builds and tests already confirmed passing. Code review catches the remaining thread-context nuances without building new test infrastructure.

---

## Documentation Format (DOCS-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Extend CONCURRENCY-MAP.md | Add "Phase 3: Consumer Contract" section with method→thread guarantee table. | ✓ |
| Inline Doxygen only | Just add @note comments on each method in bitswap.hpp. | |
| Separate CONSUMER-CONTRACT.md | Standalone document listing every method's thread contract. | |

**User's choice:** Extend CONCURRENCY-MAP.md (Recommended). Supplement with inline Doxygen.

| Option | Description | Selected |
|--------|-------------|----------|
| Method-by-method contract table | Table: Method, Caller Thread Requirement, Callback Thread, Mutex/Atomic Guarantee, Phase 2 Change Summary. | ✓ |
| Narrative summary only | Prose describing overall concurrency model. | |

**User's choice:** Method-by-method contract table (Recommended).

**Notes:** CONCURRENCY-MAP.md is already the canonical thread-safety reference from Phase 1. Extending it keeps all thread-safety documentation in one place. Inline Doxygen in bitswap.hpp serves as discoverable pointers to the full contract.

---

## Multi-Platform Build Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Windows + CI platforms | Verify Windows (already done) + let CI handle Linux and other platforms. | ✓ |
| Windows only | If it builds on Windows MSVC, it's standard enough to build everywhere. | |
| All 5 platforms | Per PROJECT.md constraint — verify on every supported platform. | |

**User's choice:** Windows + CI platforms (Recommended).

| Option | Description | Selected |
|--------|-------------|----------|
| Non-blocking | Phase 3 completes when Windows is verified + code review is done. CI failures become bugs. | ✓ |
| Blocking | Phase 3 not complete until CI passes on all platforms. | |

**User's choice:** Non-blocking (Recommended).

**Notes:** Phase 2 changes are standard C++ (mutex, atomic, io_context::post) — no platform-specific code. Multi-platform build issues would be build system problems, not thread-safety issues.

---

## the agent's Discretion

- Exact table column layout in CONCURRENCY-MAP.md consumer contract section
- Which specific methods get inline Doxygen annotations in bitswap.hpp (minimum: PublishFile, PublishDirectory, getCacheDir, setCacheDir)
- Code review checklist format
- Whether consumer contract table includes unchanged methods for completeness

## Deferred Ideas

None — all discussion stayed within Phase 3 scope.
