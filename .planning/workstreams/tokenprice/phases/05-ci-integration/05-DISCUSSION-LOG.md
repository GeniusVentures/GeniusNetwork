# Phase 5: CI Integration - Discussion Log

> **Audit trail only.** Decisions are captured in `05-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-10-02
**Phase:** 5-CI Integration
**Areas discussed:** Workflow trigger policy

---

## Workflow trigger policy

### Q1: Should changes to `cmake.yml` trigger CI despite the existing `.github/**` ignore rule?

| Option | Description | Selected |
|--------|-------------|----------|
| Allow workflow edits to trigger CI | Change the existing trigger behavior so edits to the workflow can validate themselves | |
| Preserve the existing ignore rule | Keep `.github/**` ignored, including workflow-only edits | ✓ |

**User's choice:** No — preserve the existing ignore rule
**Notes:** Phase 5 must not broaden the workflow's trigger policy. The `worker-tests` job remains path-gated to the Worker directory, while C++-only changes must not initialize Node.

---

## Decisions carried from the roadmap

- Add a lightweight Node 22 `worker-tests` job running `npm ci`, `npm run typecheck`, and `npm run test` in `SuperGenius/pricecoordinator`.
- Remove only `AccountManagement.SetPayoutAddress` from the Linux aarch64-Debug `GTEST_FILTER`; retain the MNN/Vulkan processing-test exclusions.
- Keep hermetic C++ price tests in the existing CTest invocation; do not add a new C++ CI job or matrix entry.
- Do not add Worker deployment steps.

---

*Phase: 5 CI Integration*
*Discussion captured: 2026-10-02*
