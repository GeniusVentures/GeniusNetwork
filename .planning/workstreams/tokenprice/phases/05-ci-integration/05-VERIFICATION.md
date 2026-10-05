---
phase: 05
status: human_needed
score: 3/3 (1 verified, 1 verified by override, 1 verified statically with live proof pending)
confidence: medium-high
verified: 2026-10-05
overrides_applied: 1
overrides:
  - must_have: "The Linux aarch64-Debug GTEST_FILTER exclusion of AccountManagement.SetPayoutAddress is removed from cmake.yml and the full suite passes there"
    reason: "Hermetic conversion proven (price path stub-served, '1 fresh', run 37082942495); exclusion deliberately reinstated as Vulkan-only (MNN VulkanInstance.cpp:89 assert, no ICD on ARM runner), not network. Rationale rewritten in the workflow comment."
    accepted_by: "user (ratified direction, recorded in 05-02-SUMMARY Rule-4 deviation)"
    accepted_at: "2026-10-03"
---

# Phase 5 Verification: CI Integration

## Summary

The `worker-tests` job exists and is correctly shaped. The aarch64-Debug filter still contains the `SetPayoutAddress` exclusion, so roadmap SC-2 as literally written is not met. The exclusion was reinstated on purpose, with user approval, and is now documented as Vulkan-only. I accept that deviation through the override above. The remaining unproven items are live-CI observations, and they are listed under Human Verification. The status is therefore `human_needed`, not `passed`. No code gaps were found.

## Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `worker-tests` job (Node 22, `npm ci` → typecheck → `vitest run`, path-filtered) runs green on ubuntu-latest without CoinGecko access | VERIFIED statically; live green after the final fix is not directly evidenced | `SuperGenius/.github/workflows/cmake.yml:790` defines `worker-tests` with `runs-on: ubuntu-latest`, working-directory `pricecoordinator`, and `actions/setup-node@v4` with `node-version: 22` and an npm cache keyed on `pricecoordinator/package-lock.json` (present). It then runs `npm ci`, `npm run typecheck` and `npm run test`. `package.json` scripts: `test` = `vitest run`; `typecheck` = `tsc --noEmit` against both tsconfigs. Local run per 05-01-SUMMARY: 10 files / 63 tests pass. The hermetic coalescing flake that failed on ubuntu-latest was fixed with the test-only `BATCH_WINDOW_MS_OVERRIDE` (present in `coordinator.ts` and `index.ts`). The tests are miniflare-based, so there is no live egress. |
| 2 | aarch64-Debug `GTEST_FILTER` exclusion of `AccountManagement.SetPayoutAddress` removed and the full suite passes | PASSED (override) | `cmake.yml:660` still has `*-AccountManagement.SetPayoutAddress:ProcessingNodesTest.PostProcessing:ProcessingNodesModuleTest.SinglePostProcessing`. The comment at ~633-655 states the exclusion is Vulkan-only, not network. Hermeticity is established by run 37082942495 (123/124 pass, price path "1 fresh", sole failure the MNN Vulkan assert) and by the Phase 4 stub. The aarch64-Debug run 37085939859 is green with the exclusion in place. The filter uses the correct single-dash grammar. The same block is mirrored in `build-release-tags.yml:762`. The full suite does not run SetPayoutAddress on this leg. |
| 3 | C++-only PRs do not trigger Node toolchain setup (path filter verified) | VERIFIED statically; live proof pending | Every Node step (`setup-node`, `npm ci`, typecheck, test) is gated on `workflow_dispatch || steps.changes.outputs.worker == 'true'`. The filter is `dorny/paths-filter@v3` with `worker: pricecoordinator/**`. Pushes use `base: github.event.before`. Pull requests use the changed-files API (`pull-requests: read` is granted). The 05-01-SUMMARY itself records that positive and negative event runs were deferred. |

**Score:** 3/3 resolved. Truth 2 is accepted by override, and truths 1 and 3 await live confirmation.

## Requirement Traceability

| Req | Status | Evidence |
|-----|--------|----------|
| TEST-06 | SATISFIED (static) | Separate non-matrix `worker-tests` job. C++ tests are unchanged inside the existing ctest invocation, with no new matrix entries. |
| TEST-04 (CI-exclusion clause) | PARTIAL, accepted by override | The hermetic clause was delivered in Phase 4 and proven in CI. The exclusion is retained for the unrelated MNN/Vulkan assert. REQUIREMENTS.md marks TEST-04 `[x]`, which overstates the CI clause. The doc should note that the clause is "Vulkan-blocked, pending the thirdparty MNN rider". |

No orphaned requirements.

## Artifacts and Key Links

| Artifact | Status |
|----------|--------|
| `cmake.yml` `worker-tests` job | Exists, substantive, standalone with no `needs`. Wired by the `on:` triggers. |
| `cmake.yml` GTEST_FILTER block (aarch64 Debug) | Present. It is exported as `GTEST_FILTER` and unset afterwards. |
| `build-release-tags.yml` `run_tests` stage | Present, with the same filter, platform gating and LFS checkout. |
| `HttpStubServer.cpp` lifetime fixes (`89da3ea18`, `f57138569`) | Present in the branch history. They unblocked all Linux price and account suites. |

Anti-patterns: no TBD/FIXME/XXX in the workflow files.

## Observations (non-blocking)

- **Path-filter interaction:** the workflow-level `paths-ignore: .github/**` means workflow-only edits never trigger a run. This is by design (D-01). Live proof of the gate therefore needs a real PR or push that touches `pricecoordinator/**`, and another that touches C++ only.
- **Develop thirdparty lane:** `cmake.yml`'s develop thirdparty release predates `HTTPTypes.hpp` and `HTTPClient.hpp`. The price suites compile only in tag builds with `thirdparty_tag`, until a develop thirdparty refresh lands. This is a standing rider.
- **Unrelated x86_64 EL8 failures:** pre-existing failures outside this phase are documented in 05-02-SUMMARY.
- **Bookkeeping:** this phase's own claims are verified. REQUIREMENTS.md TEST-04 wording is slightly optimistic (see above).

## Human Verification Required

1. **Worker-path event runs `worker-tests` end-to-end.** Open a PR or push that touches `pricecoordinator/**`. Expected: `changes.outputs.worker == 'true'`, Node 22 setup, `npm ci`, typecheck and vitest all green on ubuntu-latest, including the coalescing tests after the `BATCH_WINDOW_MS_OVERRIDE` fix. Why human: it needs a live GitHub event, which was deferred in 05-01.
2. **C++-only event skips the Node steps.** Open a PR or push that changes only C++ files. Expected: the `worker-tests` job passes with the setup-node, `npm ci`, typecheck and test steps all skipped. Why human: path-gate proof needs a live event. This is the "live path-gate proof pending" item.
3. **Optional, acknowledging the override:** once the thirdparty MNN VulkanInstance graceful-degradation rebuild lands, remove the `SetPayoutAddress` exclusion and confirm aarch64-Debug is green. Why human: it depends on an external rebuild, and it is tracked as a rider rather than a Phase 5 gate.

## Gaps Summary

There are no blocking gaps. The `SetPayoutAddress` exclusion difference is covered by a user-ratified override. Live path-gate behaviour is the only outstanding evidence.

---
_Verified: 2026-10-05_
_Verifier: the agent (gsd-verifier)_
