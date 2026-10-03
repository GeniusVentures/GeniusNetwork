# Phase 5: CI Integration - Context

**Gathered:** 2026-10-02
**Status:** Ready for planning

<domain>
## Phase Boundary

CI integration for the completed PriceCoordinator implementation: add a lightweight, path-filtered `worker-tests` job to `SuperGenius/.github/workflows/cmake.yml`, then remove only the `AccountManagement.SetPayoutAddress` exclusion from the Linux aarch64-Debug gtest filter. Keep the remaining MNN/Vulkan-related test exclusions and run the C++ tests through the existing `ctest` invocation.

Requirements in scope: TEST-06 and the CI-exclusion-removal clause of TEST-04.

**Not in this phase:** new C++ build-matrix entries or a separate C++ test job, Worker deployment, changes to the existing workflow trigger policy, or removal of the remaining aarch64-Debug MNN/Vulkan exclusions.
</domain>

<decisions>
## Implementation Decisions

- **D-01:** Keep the existing `paths-ignore: .github/**` behavior. Workflow-only edits will continue not to trigger this workflow; do not broaden workflow triggers as part of Phase 5.
- **D-02:** The Worker job is gated on changes under the Worker directory and must not set up Node for C++-only changes. The C++ build matrix remains governed by the existing workflow triggers.
- **D-03:** Run the Worker checks on `ubuntu-latest` with Node 22 from `SuperGenius/pricecoordinator`: `npm ci`, `npm run typecheck`, and `npm run test` (`vitest run`). Do not add network-dependent tests or deployment steps.
- **D-04:** Remove only `AccountManagement.SetPayoutAddress` from the Linux aarch64-Debug `GTEST_FILTER`. Preserve `ProcessingNodesTest.PostProcessing`, `ProcessingNodesModuleTest.SinglePostProcessing`, and the existing CTest exclusions that isolate MNN/Vulkan failures.
- **D-05:** Keep C++ price tests in the existing CTest run; do not add matrix legs or another C++ CI job.

### Claude's Discretion

- The exact GitHub Actions mechanism for detecting Worker-directory changes, provided C++-only changes do not initialize Node and the Worker checks run for matching changes.
- The `setup-node` cache configuration and action-step names, following the repository's existing conventions.
- How to validate path-filter behavior without relying on live CoinGecko access.

### Known Consequence

Because the workflow's existing `paths-ignore` excludes `.github/**`, a change limited to `cmake.yml` will not trigger this workflow. This behavior is intentional for this phase per D-01.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `SuperGenius/pricecoordinator/package.json` defines `typecheck` and `test`; `test` runs `vitest run`.
- `SuperGenius/pricecoordinator/package-lock.json` supports deterministic `npm ci`.
- Worker tests use the Cloudflare Vitest plugin and local workerd runtime; the suite includes hermeticity coverage and mocked upstream requests.
- `SuperGenius/.github/workflows/cmake.yml` already runs hermetic C++ tests through CTest and has the aarch64-Debug filter containing the now-obsolete payout-test exclusion alongside unrelated MNN/Vulkan exclusions.

### Integration Points

- Add `worker-tests` as a separate non-matrix job in `SuperGenius/.github/workflows/cmake.yml`, scoped to Worker-directory changes.
- The job's Node setup and npm commands should execute from `SuperGenius/pricecoordinator`.
- The aarch64-Debug adjustment is limited to the `GTEST_FILTER` entry for `AccountManagement.SetPayoutAddress`; retain the processing test exclusions and CTest exclusions.
</code_context>

<specifics>
## Specific Ideas

- The Worker path filter must avoid Node setup on C++-only pull requests.
- Keep the Worker CI job cheap and hermetic: no CoinGecko egress, no `wrangler deploy`, and no changes to the C++ matrix.
- Preserve the current trigger policy even though it means a workflow-only edit does not trigger this workflow.
</specifics>

<deferred>
## Deferred Ideas

- Revisiting whether `.github/**` changes should trigger the workflow; explicitly out of scope per D-01.
- Removing the aarch64-Debug MNN/Vulkan exclusions; those are unrelated to the hermetic price-test conversion.
- Worker deployment and deployment automation; deferred by the v1.0 requirements.
</deferred>

---

*Phase: 5 CI Integration*
*Context gathered: 2026-10-02*
