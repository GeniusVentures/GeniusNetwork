---
phase: 261008-oda
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - test/src/account/account_management_test.cpp   # SuperGenius submodule root
  - src/account/GeniusNode.hpp                     # SuperGenius submodule root
autonomous: true
requirements: ["SuperGenius#385"]

estimate:
  tokens: 25000
  raw_tokens: 18000
  tasks: 2
  confidence: low

must_haves:
  truths:
    - "git grep for m_tokenPriceCache OR AccountManagementTestAccess across the SuperGenius submodule returns zero matches"
    - "test/src/account/account_management_test.cpp is byte-identical to reference commit aeb2aba6d (git diff aeb2aba6d -- <file> is empty)"
    - "account_management_test.cpp compiles — the CI error 'no member named m_tokenPriceCache in sgns::GeniusNode' is gone (Release Build CI, cmake.yml)"
    - "The fix commit lives on dev_tokenprice inside the SuperGenius submodule and is pushed; SuperGenius/ paths are NOT staged in the outer GeniusNetwork repo"
  artifacts:
    - "test/src/account/account_management_test.cpp (accessor class + call site removed)"
    - "src/account/GeniusNode.hpp (friend declaration removed; all other dev_tokenprice changes untouched)"
  key_links:
    - "PR GeniusVentures/SuperGenius#385 branch dev_tokenprice receives the fix commit -> Release Build CI reruns green"
---

<objective>
Remove the merge-resurrected AccountManagementTestAccess price-cache accessor that breaks Release Build CI on the SuperGenius dev_tokenprice branch (PR GeniusVentures/SuperGenius#385, failed run 37841328980).

Purpose: All 13 matrix jobs of the Release Build CI fail at "Build SuperGenius" with `test/src/account/account_management_test.cpp:45:19: error: no member named 'm_tokenPriceCache' in 'sgns::GeniusNode'`. Root cause: merge commit a2d80796c ("Merge branch 'develop' into dev_tokenprice") resurrected develop's stale side of two hunks that commit 79a2f6e1c (develop) had already deleted — the friend-class test accessor poking the node's (now-deleted) m_tokenPriceCache.

Output: Two files edited in the SuperGenius submodule to match the reference clean state aeb2aba6d, committed on dev_tokenprice, pushed. The hermetic HttpStubServer + env-redirect fixture (already in the test's constructor) fully replaces the deleted accessor — no compensation code needed.
</objective>

<execution_context>
@~/.copilot/gsd-core/workflows/execute-plan.md
@~/.copilot/gsd-core/templates/summary.md
</execution_context>

<context>
@W:/gnus/GeniusNetwork/.planning/workstreams/tokenprice/STATE.md

Submodule boundary (CRITICAL): All code work happens inside the SuperGenius git submodule at `W:/gnus/GeniusNetwork/SuperGenius` (branch `dev_tokenprice`, HEAD `cdd104297` "Bump procmgr pointer"). All file paths below are relative to that submodule root; every command starts by cd-ing there. The commit goes to the submodule repo — do NOT stage `SuperGenius/` paths in the outer GeniusNetwork repo (outer-repo docs commit is handled by the orchestrator). Untracked `? SGProcessingManager` nested-submodule noise in `git status` is pre-existing — never `git add` it; stage files by explicit path only.
</context>

<tasks>

<task type="auto">
  <name>Task 1: Delete the three resurrection sites (restore aeb2aba6d state)</name>
  <files>test/src/account/account_management_test.cpp, src/account/GeniusNode.hpp</files>
  <precondition>Submodule W:/gnus/GeniusNetwork/SuperGenius is on branch dev_tokenprice with a clean working tree (untracked SGProcessingManager nested submodule is expected noise); reference commit aeb2aba6d is present in the local object store (verify: `git cat-file -t aeb2aba6d`).</precondition>
  <reversibility rating="reversible">Pure deletion of test-only accessor code; trivially revertible via git.</reversibility>
  <action>
    cd W:/gnus/GeniusNetwork/SuperGenius. Run `git --no-pager diff aeb2aba6d -- test/src/account/account_management_test.cpp` — it shows EXACTLY the two hunks to delete; the goal is to make this diff empty.

    1. In test/src/account/account_management_test.cpp: delete the entire `AccountManagementTestAccess` class block (starts at line ~35 `class AccountManagementTestAccess`, spans through ~line 48; contains the `node->m_tokenPriceCache["genius-ai"] = { price, std::chrono::system_clock::now() };` line at ~45).
    2. In the same file: delete the call site at ~line 386 `sgns::AccountManagementTestAccess::SetGNUSPrice( node_requester, 1.0 );` TOGETHER WITH the 3-line comment directly above it (both hunks come from the diff above).
    3. In src/account/GeniusNode.hpp: delete ONLY line ~986 `friend class AccountManagementTestAccess;`. WARNING: `git diff aeb2aba6d -- src/account/GeniusNode.hpp` shows ~125 other changed lines that are LEGITIMATE dev_tokenprice work — do NOT revert them; the friend line is the only resurrection.

    Do not add any replacement code: the fixture constructor already sets up the hermetic stub (HttpStubServer on loopback serving `{"genius-ai":{"usd":0.19}}` with SGNS_COINGECKO_URL/SGNS_PRICE_FALLBACK_URL env redirects) BEFORE node construction, and no test asserts an absolute `cost` value (balance checks are relative), so stub price 0.19 vs old hardcoded 1.0 is safe.
  </action>
  <verify>
    <automated>cd W:/gnus/GeniusNetwork/SuperGenius; git diff --stat aeb2aba6d -- test/src/account/account_management_test.cpp; git grep -n -E "m_tokenPriceCache|AccountManagementTestAccess"</automated>
  </verify>
  <done>First command prints NOTHING (file byte-identical to aeb2aba6d). Second command prints NOTHING (grep exits 1 = zero matches anywhere in the submodule, comments included). Working tree shows only these two files modified.</done>
</task>

<task type="auto">
  <name>Task 2: Compile-check the test target, commit and push on dev_tokenprice</name>
  <files>test/src/account/account_management_test.cpp, src/account/GeniusNode.hpp</files>
  <action>
    cd W:/gnus/GeniusNetwork/SuperGenius. Compile the exact translation unit that failed CI using the already-configured VS2022 tree: `cmake --build build/Windows/Release --target account_management_test --config Release` (target defined via addtest() at test/src/account/CMakeLists.txt:35). Success criterion: account_management_test.cpp compiles with no 'm_tokenPriceCache' / 'AccountManagementTestAccess' errors. If the build fails on UNRELATED environment/deps (missing thirdparty artifacts, link-time env issues — not the deleted accessor), note it in the SUMMARY and proceed; the CI rerun is the authoritative compile gate.

    Commit inside the submodule, staging the two files by explicit path only (never `git add -A` — keeps the untracked SGProcessingManager nested submodule out): `git add test/src/account/account_management_test.cpp src/account/GeniusNode.hpp` then commit with message `fix(tokenprice): remove resurrected AccountManagementTestAccess from merge a2d80796c (restore aeb2aba6d state)`. Push: `git push origin dev_tokenprice` (updates PR GeniusVentures/SuperGenius#385). Do NOT stage or commit anything in the outer GeniusNetwork repo.
  </action>
  <verify>
    <automated>cd W:/gnus/GeniusNetwork/SuperGenius; git log -1 --name-only --format="%h %s"; git status --porcelain -- test/src/account/account_management_test.cpp src/account/GeniusNode.hpp; git rev-parse HEAD; git ls-remote origin refs/heads/dev_tokenprice</automated>
  </verify>
  <done>HEAD commit message matches the fix scope and its file list is exactly the two files; both path-scoped status lines are empty (committed); local HEAD SHA equals the remote dev_tokenprice SHA from ls-remote (pushed). Release Build CI on PR 385 re-runs and the previously failing 13 matrix jobs compile past this error (monitor via `gh run list --workflow=cmake.yml --branch dev_tokenprice --limit 1` in the SuperGenius repo — CI runtime may exceed this plan's window; record the run URL in the SUMMARY if still in progress).</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| (none) | Pure deletion of dead test-accessor code inside the submodule; no new inputs, outputs, or privilege paths |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-oda-01 | Tampering | account_management_test.cpp fixture | low | accept | Change removes a direct private-member poke and keeps the already-reviewed hermetic stub path (aeb2aba6d state); strictly reduces test-to-production coupling |

No package installs in this plan — package legitimacy gate not applicable.
</threat_model>

<verification>
1. `git grep -n -E "m_tokenPriceCache|AccountManagementTestAccess"` in the SuperGenius submodule returns zero matches.
2. `git diff aeb2aba6d -- test/src/account/account_management_test.cpp` is empty; GeniusNode.hpp retains all legitimate dev_tokenprice changes except the friend line.
3. `cmake --build build/Windows/Release --target account_management_test --config Release` compiles the TU (or unrelated-env failure is recorded and CI is authoritative).
4. Submodule dev_tokenprice HEAD pushed to origin; PR GeniusVentures/SuperGenius#385 Release Build CI rerun is green (or run URL recorded).
5. Outer repo has no staged SuperGenius/ changes from this task.
</verification>

<success_criteria>
- Release Build CI (cmake.yml) on PR 385 no longer fails with `no member named 'm_tokenPriceCache'` — the compile error that broke all 13 matrix jobs is eliminated.
- Test file byte-identical to aeb2aba6d; header differs from aeb2aba6d only by legitimate dev_tokenprice work (friend line gone).
- One scoped commit on submodule branch dev_tokenprice, pushed; nothing committed to the outer repo by the executor.
</success_criteria>

<output>
Create `.planning/workstreams/tokenprice/quick/261008-oda-remove-resurrected-accountmanagementtest/261008-oda-SUMMARY.md` when done (outer repo — orchestrator handles the docs commit)
</output>
