---
name: architecture-review
description: Review software architecture and implementation plans before GSD phase execution, and review resulting changes before approval. Use when planning or checking a phase, preparing to run gsd-execute-phase, reviewing a PR, or assessing code for unnecessary duplication, workarounds, weak types, bad dependency wiring, misplaced logic, unsafe transactions, inefficient storage, and needless complexity. Inspect actual repository code and build dependencies; return actionable, evidence-based findings and simpler alternatives. Treat material architecture violations as blockers rather than accepting a green test suite as proof of good design.
---

# Architecture review

Prefer the smallest sound design that meets the requirements. Optimize for correctness, simplicity, reuse, maintainability, and measurable performance. Do not confuse following a plan with good engineering.

## Role and scope

- As a GSD planner, apply these rules while designing tasks; explicitly identify the owner of each new business rule and how consumers reuse it. Revise plans that violate the rules.
- As a GSD plan checker, independently inspect the proposed plans against the repository before execution. Return findings in the native checker format; do not edit source or plans. Do not approve a plan with an unresolved material violation.
- As a GSD executor, follow the reviewed design. If actual code exposes an architectural conflict, stop the affected task and report the evidence; do not invent a workaround or silently expand scope. Continue unaffected work only if safe and permitted.
- As a verifier or PR reviewer, inspect the actual diff and integration paths against the approved design. Report regressions and distinguish new defects from inherited debt. Do not treat passing tests as evidence that all architectural concerns are resolved.
- When invoked directly as `/architecture-review <phase>`, independently review that phase before execution. For a PR or diff request, review that change instead. Do not execute the phase or change implementation code as part of review.

## Established architecture and review authority

- Treat the repository's documented architecture, GNUS C++ Coding Standards, protocol contracts, and previously approved engineering decisions as authoritative.
- Apply this skill primarily to proposed changes and new implementations. Do not classify existing code as defective merely because it predates this skill or differs from a general engineering preference.
- Before proposing an architectural change, identify the original design rationale, supported platforms, performance requirements, security model, dependency constraints, and backward compatibility requirements.
- Distinguish intentional architectural complexity from accidental implementation complexity.
- Distinguish replicated execution from duplicated source code, local atomicity from distributed finality, and eventual consistency from invalid state.
- Require a reproducible defect, violated invariant, measured performance problem, security weakness, or demonstrable maintenance cost before recommending substantial refactoring.
- Preserve wire formats, cryptographic commitments, transaction semantics, concurrency guarantees, ABI compatibility, and supported build configurations.
- Refer substantial changes to established architecture to the responsible human architects for approval.
- Do not undertake speculative refactoring solely to satisfy an LLM-generated architectural review.

## Read before judging

1. Resolve the requested phase or diff and record the current revision. Read applicable CLAUDE.md/AGENTS.md, project architecture, roadmap, requirements, phase CONTEXT, RESEARCH, and every relevant PLAN file. Honor locked user decisions. If they require a poor design, flag the conflict and request an explicit decision instead of overriding it.
2. Read the real source, interfaces, callers, tests, generator inputs, CMake targets, dependency definitions, submodule refs, and relevant storage or protocol contracts. Search for equivalent logic and existing reusable components. Verify proposed names and paths exist or are planned. Trace data and control flow across file boundaries, including build/configure order and supported platform variants. Scope searches to the phase and its dependencies; avoid reading unrelated projects.
3. Identify the smallest viable change. Compare it with the proposed design. Prefer reusing or extracting a real existing implementation over creating a new abstraction, wrapper, duplicate, scanner, or framework.
4. Review all applicable checks below. Ground each finding in a plan/task and a source path with line numbers or other specific evidence. Distinguish a verified defect, a plausible failure mode, an inherited issue, and an unknown. Do not invent source behavior, claim tests ran when they did not, or reject a justified design simply because it differs from a preference.

## Engineering checks

### Ownership and reuse
- Require one executable owner per business rule, algorithm, state transition, and domain vocabulary. Consumers call it; tests verify it. Reject copy/paste implementations labeled as mirrors, twins, fallbacks, or drift-checked equivalents when a common implementation is feasible.
- Reuse existing interfaces, libraries, state machines, and generators. For C++ consumers, share platform-neutral source/library targets rather than reproducing the logic in multiple templates. Where another language or runtime genuinely cannot share the implementation, require one shared implementation per unavoidable runtime or generation from a canonical rule source, with cross-runtime contract tests. Document the actual constraint.
- Separate UI, transport, domain logic, and persistence. Keep pure domain code independent of HTTP envelopes, JSON formatting, UI state, storage, and generated transport types when practical. Convert wire data at the boundary. Reuse shared generated schemas rather than adding parallel vocabularies.
- Prefer typed enums, validated IDs, typed results, and exhaustive state handling. Reject unknown values explicitly. Do not encode internal business decisions in magic strings, nullable success IDs, untyped maps, or ambiguous error sentinels. Use ordinary comparisons for small strings; optimize only when justified.

### Build, generation, and dependencies
- CMake targets must declare their real sources, dependencies, outputs, byproducts, and link requirements. Verify configure order, clean and incremental builds, missing generated files, and parallel execution. A consumer must not need to discover the generator's private implementation file.
- Reject conditional target creation, `if(EXISTS ...)`, `if(TARGET ...)`, generated-file flags, or stamp files used to hide a required dependency or silently omit tests. Allow genuinely optional features only with explicit configuration and clear diagnostics. A required tool or dependency must fail clearly when absent.
- Compile shared code once per required platform/configuration; link consumers to it. Avoid unnecessary rebuilds, repeated generation, blanket reconfiguration, duplicate compilation, and dependency cycles. Keep C++ generation independent of unrelated frontend application builds when required by native tests.
- Prefer compiler/type/link boundaries and real tests to identifier blacklists, regex-based policy scanners, duplicate allowlists, or ad hoc scripts. Do not add a guard when a correct dependency graph or interface solves the problem.

### Correctness, state, and failure handling
- Trace happy paths, failures, cancellation, retries, duplicate requests, stale state, process restarts, concurrent operations, and tenant isolation as relevant. Fail closed on invalid or corrupt data. Do not silently drop a failure, fabricate defaults for required fields, or treat malformed data as success.
- Use explicit lifecycle transitions and enforce invariants in the owning service, not in widget render callbacks or scattered booleans. Consider the existing project state-machine framework for nontrivial lifecycles; do not introduce it for simple pure functions.
- Make local financial and other consistency-sensitive writes atomic where supported. For external side effects, plan durable operation identity, real server-side idempotency, retry/recovery/reconciliation, and a distinct unknown outcome. Never claim that an error proves no side effect occurred. Distinguish planned mock behavior from production behavior.
- Use storage keys, indexes, or maintained aggregates to avoid full database scans for single-entity operations. Check lock scope, query complexity, redundant reads, and repeated parsing. Do not silently skip corrupt rows when they affect financial or security invariants. Keep arithmetic bounds, units, and currencies explicit.

### Simplicity and verification
- Ask what can be removed or reused. Avoid unnecessary indirection, one-use abstractions, speculative generalization, duplicate state, code generators for trivial code, and workarounds for broken prerequisites. Keep comments focused on invariants and non-obvious reasoning; leave phase/task bookkeeping to planning artifacts.
- Require tests that exercise actual public behavior and production paths: malformed input, boundary cases, concurrency/recovery when relevant, and clean builds. A corpus is useful; it is not a substitute for shared code. Do not test a shadow implementation as if it were the production path.
- Verify test registration and expected coverage across supported configurations; reject silent skips, zero-test success, and tests disabled merely to get green CI. Keep independent backend tests independent of frontend build flags.
- Avoid unrelated refactors, arbitrary line-count limits, and cosmetic churn. Identify inherited debt separately; block only if it compromises the phase's correctness, architecture, or required guarantees. Propose a follow-up for unrelated debt.
- Do not run CI as a probe. Use static inspection first and focused local checks only as needed. Never blindly rerun failed CI; verify the fix is in the exact ref to be built. Do not trigger remote builds during pre-execution review without approval.

## Findings and decision

Return a concise, prioritized report. For each material finding include severity, plan/task or diff location, source evidence, why it matters, smallest viable correction, and verification needed. Classify as:

- **Blocker:** breaks an invariant, materially duplicates avoidable business logic, introduces unsafe or missing dependency wiring, creates a significant correctness/security/recovery risk, or otherwise violates a required engineering rule. Revise before execution.
- **Warning:** meaningful maintainability or performance issue that should be addressed, but does not itself prevent safe execution. Explain tradeoffs.
- **Info:** optional improvement; omit trivial style nits.

For GSD plan-checker invocation, preserve the orchestrator's required output contract: `## ISSUES FOUND` with the native structured YAML issues (plan, dimension, severity, description, task when known, fix_hint) if findings require revisions, or `## VERIFICATION PASSED` only if the required checks pass. Use `architecture_quality` as a dimension for these checks. Do not replace GSD's other required checks. Require the planner to revise the affected PLAN tasks, then independently recheck the revised plans; never clear a blocker by relabeling it as advisory.

For a direct review, use `APPROVED`, `CHANGES REQUIRED`, or `REVIEW INCOMPLETE`. List blockers first, warnings second, and a short recommended design. State what was inspected and what was not verified. If asked for a durable gate record, save one concise `<phase>-ARCHITECTURE-REVIEW.md` in the phase directory with the decision, reviewed revision, and reviewed plan paths; update the same file on re-review. Missing evidence, unresolved blockers, changed plans, or a relevant change to source/build contracts invalidate approval. Do not mark a phase approved or execute it on the basis of an incomplete review.

Only accept an exception when the user explicitly approves the concrete tradeoff and its consequence. Record the exception in existing phase planning notes; do not use vague permission to bypass unrelated checks.
