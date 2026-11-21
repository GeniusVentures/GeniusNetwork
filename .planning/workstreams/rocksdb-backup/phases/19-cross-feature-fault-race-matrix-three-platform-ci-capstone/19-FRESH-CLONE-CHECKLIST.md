# 19-FRESH-CLONE-CHECKLIST — TEST-03 Capstone Evidence (D-15/D-16)

Status: **PENDING** — completed at the Task-3 checkpoint with the run ID + parameters
(see notes/19-cross-feature-fault-race-three-platform-capstone.md §(e), the single
evidence home).

## Push-state skeleton (fill at the checkpoint; innermost-first)

| Repo | Branch | SHA | Pushed? |
|------|--------|-----|---------|
| SuperGenius | dev_coldstorage_additions | 3b5885d2f (local HEAD after 19-05 Task 1) | NO — the dispatch requires the user push |
| thirdparty | (recorded tag branch) | `test_coldstorage_rtti` resolves (4a97e95) | unchanged this phase — no new tag needed |
| thirdparty/sgns-blockstore | main | ee0266b (unchanged this phase) | existing |

**thirdparty tag check:** use the recorded cold-build tag (`test_coldstorage_rtti`,
consumed by v1.1 run 42905264387) or any newer tag post-dating the installed fake
headers. No library change this phase — a new tag is NOT required (verify the tag
still resolves on the thirdparty releases page before dispatch).

## User actions (the D-15/D-16 checkpoint — one dispatch, one veto, one confirmation)

1. **Push** `dev_coldstorage_additions` in SuperGenius (innermost-first if any
   submodule moved — none did this phase; SuperGenius alone). Plain
   `git push origin dev_coldstorage_additions`.
2. **Dispatch** `SuperGenius/.github/workflows/build-release-tags.yml`:
   branch `dev_coldstorage_additions`, `thirdparty_tag` = the recorded tag,
   `run_tests=true`, `cold_storage=true`. Wait for the three desktop platform
   jobs (Windows-Release, Linux-x86_64-Release, OSX-Release).
3. **Per platform, BOTH lanes must be green** (the D-11 both-lanes reading):
   the full-suite `Run tests` step AND the new **Tier-1 fail-closed lane**
   step — whose listing must include `cold_cross_feature_fault_race_test`
   (the membership check is read from the dispatch evidence, not the local
   lane). Also verify the configure log shows `-DSGNS_COLD_STORAGE=ON`.
4. **Report the run URL(s) back** to the executing session. Expected: all
   three platforms green on both lanes. EXPECTED-RED caveats: none — the
   capstone lanes are expected green; any cold-labeled red is fix-forward
   (never an exclusion, D-12 — quarantine table: notes/19-* §(b)); an X11
   flake specifically goes to the promotion contract (§(d)), never a silent
   skip.
5. **B1/B2 veto:** **RULED at the checkpoint (2026-11-20): B2 stands** —
   cmake.yml push filters unchanged; the permanent lane stays dormant until
   the v1.2 merge. B1 remains one line if re-ruled later.
6. **X11 promotion count:** **RULED at the checkpoint (2026-11-20): ONE
   green dispatch** — the permanent lane is the recurrence guard (the
   dispatch itself is both the capstone evidence and X11's promotion).

## Outcome recording (executor side, on resume with links)

- notes/19-* §(e) evidence table: per-platform run link, toggles, tag, branch
  SHA, both-lanes results.
- This checklist's Status line flips to the completed shape with the primary
  run ID + parameters.
