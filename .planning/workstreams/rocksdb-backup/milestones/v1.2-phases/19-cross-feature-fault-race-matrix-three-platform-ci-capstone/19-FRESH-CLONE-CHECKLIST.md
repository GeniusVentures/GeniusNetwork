# 19-FRESH-CLONE-CHECKLIST — TEST-03 Capstone Evidence (D-15/D-16)

Status: **COMPLETE (2026-11-25)** — closing evidence recorded across dispatches D1–D8
(primary per-platform rows: Windows https://github.com/GeniusVentures/SuperGenius/actions/runs/45257655488,
Linux (same run), OSX https://github.com/GeniusVentures/SuperGenius/actions/runs/45489840538;
confirming run at the final HEAD: https://github.com/GeniusVentures/SuperGenius/actions/runs/45504484532 —
run_tests=true, cold_storage=true, thirdparty_tag=test_coldstorage, branch dev_coldstorage_additions;
see notes/19-cross-feature-fault-race-three-platform-capstone.md §(e) THE CLOSING EVIDENCE TABLE,
the single evidence home).

## Push-state skeleton (completed at the checkpoint; innermost-first)

| Repo | Branch | SHA | Pushed? |
|------|--------|-----|---------|
| SuperGenius | dev_coldstorage_additions | 41776b0c0 (final HEAD; tag `test_coldstorage` on it) | YES — user pushed (verified via ls-remote) |
| thirdparty | dev_db_storage | da17826 (the MoltenVK install fix) | YES — user pushed; iOS/iOS-sim assets regenerated + re-uploaded to `test_coldstorage` (user's rebuild run 45297525343) |
| thirdparty/sgns-blockstore | main | ee0266b (unchanged this phase) | existing |

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
  SHA, both-lanes results. **DONE — see THE CLOSING EVIDENCE TABLE.**
- This checklist's Status line flips to the completed shape with the primary
  run ID + parameters. **DONE (2026-11-25).**

## Recorded checkpoint rulings (final)

- **B1/B2 veto (item 5):** B2 STANDS (ruled 2026-11-20, re-confirmed through
  the closing dispatch) — cmake.yml push filters unchanged; the permanent lane
  is dormant until the v1.2 merge.
- **X11 promotion count (item 6):** ONE green dispatch (ruled 2026-11-20) —
  met on all three platforms at D4; X11 remained green in every subsequent
  dispatch including both closing runs (zero X11 failures D5–D8).
- **Expected outcome vs. actual:** all three platforms green on both lanes —
  **MET** (Windows D3 both-lanes green; Linux D3 both-lanes green; OSX D7
  both-lanes green; D8 confirming: Tier-1 20/20 both OSX configs, every cold
  test green in the full lanes). Every cold-labeled find in the D1–D8 trail
  was fixed forward in scope — no exclusion matching a cold_* name was ever
  added (the D-12 letter held).
