---
phase: 261008-oda
plan: 01
subsystem: tokenprice
tags: [tokenprice, supergenius, ci-fix, test-cleanup]
requires:
  - "SuperGenius dev_tokenprice merge a2d80796c (broke CI)"
provides:
  - "Release Build CI on PR GeniusVentures/SuperGenius#385 compiles past m_tokenPriceCache error"
affects:
  - "SuperGenius test/src/account/account_management_test.cpp"
  - "SuperGenius src/account/GeniusNode.hpp"
tech-stack:
  added: []
  patterns:
    - "Restore reference state aeb2aba6d instead of adding compensation code (hermetic HttpStubServer fixture already covers price provisioning)"
key-files:
  created: []
  modified:
    - SuperGenius/test/src/account/account_management_test.cpp
    - SuperGenius/src/account/GeniusNode.hpp
decisions:
  - "Pure deletion to reference state aeb2aba6d; no replacement code — the fixture's stub price (0.19) is safe because no test asserts absolute cost values"
  - "Local Windows link failure (stale outer-repo thirdparty gnus_upnp header) treated as unrelated env issue per plan; Release Build CI is the authoritative gate"
metrics:
  duration: 10m
  completed: 2026-10-08
  tasks: 2
actuals:
  tokens: 2100
  tasks: 2
  commits: 1
plan_head_before: cdd104297
plan_head_after: 3c41ab311
status: complete
---

# Phase 261008-oda Plan 01: Remove resurrected AccountManagementTestAccess Summary

One-liner: Deleted the merge-resurrected `AccountManagementTestAccess` friend-accessor poking the removed `m_tokenPriceCache` member, restoring test/src/account/account_management_test.cpp byte-identical to reference commit aeb2aba6d — fixes the `no member named 'm_tokenPriceCache' in 'sgns::GeniusNode'` error that failed all 13 Release Build CI matrix jobs on PR GeniusVentures/SuperGenius#385.

## What Was Changed

All work inside the SuperGenius submodule at `W:/gnus/GeniusNetwork/SuperGenius` (branch `dev_tokenprice`), commit `3c41ab311` (`3c41ab3115c385574684aeceb0b233a7336764a5`):

1. **test/src/account/account_management_test.cpp** — deleted the entire `sgns::AccountManagementTestAccess` class block (former lines ~28–49, including the `node->m_tokenPriceCache["genius-ai"] = { price, ... }` body) and its call site in `AccountManagement.SetPayoutAddress` (the `SetGNUSPrice( node_requester, 1.0 )` line plus its 3-line comment). File is now byte-identical to `aeb2aba6d` (`git diff aeb2aba6d -- <file>` is empty; blob `f18562709`).
2. **src/account/GeniusNode.hpp** — deleted only line 986 `friend class AccountManagementTestAccess;`. All ~125 other changed lines of legitimate dev_tokenprice work in this header are untouched.

No replacement/compensation code added: the test fixture constructor already starts the hermetic `HttpStubServer` (loopback, `{"genius-ai":{"usd":0.19}}`, `SGNS_COINGECKO_URL`/`SGNS_PRICE_FALLBACK_URL` env redirects) before node construction, and no test asserts absolute `cost` values.

Commit message: `fix(tokenprice): remove resurrected AccountManagementTestAccess from merge a2d80796c (restore aeb2aba6d state)` with `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` trailer. 2 files changed, 27 deletions(-), 0 insertions.

## Verification Results

| Check | Result |
|---|---|
| `git grep -n -E "m_tokenPriceCache\|AccountManagementTestAccess"` in submodule | ✅ zero matches (exit 1) — comments included |
| `git diff aeb2aba6d -- test/src/account/account_management_test.cpp` | ✅ empty (byte-identical to reference) |
| `git diff aeb2aba6d -- src/account/GeniusNode.hpp` | ✅ only legitimate dev_tokenprice changes remain; friend line gone |
| Compile of CI-failing TU (`account_management_test.cpp`) | ✅ compiled with **zero errors** — only pre-existing C4834 `[[nodiscard]]` warnings. The original CI error `no member named 'm_tokenPriceCache'` is gone. |
| Full local build (`cmake --build build/Windows/Release --target account_management_test --config Release`) | ⚠️ FAILED on **unrelated environment/deps issues** (see Local Build Caveat) — plan permits this; CI is authoritative |
| Submodule commit on `dev_tokenprice` | ✅ `3c41ab311`, file list exactly the two files |
| Push | ✅ `git push origin dev_tokenprice` → `cdd104297..3c41ab311 dev_tokenprice -> dev_tokenprice`; local HEAD `3c41ab3115c385574684aeceb0b233a7336764a5` == `git ls-remote origin refs/heads/dev_tokenprice` |
| Outer GeniusNetwork repo untouched by executor | ✅ `git diff --cached --name-only` empty; nothing staged; the ` M SuperGenius` pointer update left unstaged for the orchestrator |
| SGProcessingManager untracked noise | ✅ never staged (explicit-path staging only) |

### Local Build Caveat (recorded, not fixed — out of scope)

`cmake --build` on the full target chain fails in `GeniusNode.cpp` (`error C2039: 'OpenPort'/'GetIGD': is not a member of 'sgns::GeniusNode'`, `'New': is not a member of 'sgns::upnp::UPNP'`) and at link (`LNK2019/LNK1120`) for `account_management_test.exe`. Root cause is the local build tree resolving a **stale `upnp.hpp` from the outer repo's `thirdparty/build/Windows/Release/gnus_upnp/`** which does not match the SuperGenius submodule's current headers — a pre-existing environment/thirdparty drift, present before this change (`OpenPort` appears in neither the current nor the `aeb2aba6d` header). To still compile the exact TU that failed CI, `account_management_test.vcxproj` was built with `/p:BuildProjectReferences=false`: **`account_management_test.cpp` compiled cleanly** (warnings only), proving the fix; the link step then fails on the same stale-thirdparty staleness, not on anything in this change.

## CI Rerun

Fix push triggered Release Build CI (cmake.yml) run on PR #385: **https://github.com/GeniusVentures/SuperGenius/actions/runs/37848757691** — status `queued` at time of writing (supersedes failed run 37841328980). CI runtime exceeds this plan's window; the run URL is recorded here for follow-up.

## Deviations from Plan

None — plan executed exactly as written. (Two process notes, not plan deviations: the local compile gate was satisfied via direct MSBuild of the failing TU with project references disabled after the full-target build hit the documented unrelated-env failure path; one commit-message retry was needed for PowerShell quoting, resulting in the final single commit `3c41ab311`.)

## Auth Gates

None.

## Known Stubs

None — pure deletion, no stubs introduced.

## Self-Check: PASSED

- Commit `3c41ab311` exists on submodule `dev_tokenprice` and on origin (verified via ls-remote). ✅
- `test/src/account/account_management_test.cpp` modified and byte-identical to `aeb2aba6d`. ✅
- `src/account/GeniusNode.hpp` modified (friend line only). ✅
- grep truth: zero matches for `m_tokenPriceCache|AccountManagementTestAccess`. ✅
- Outer repo: no staged changes from this task. ✅
