# 12-FRESH-CLONE-CHECKLIST — SC4 Fresh-Clone Proof (TEST-02 / D-05)

Status: **AWAITING D-03 HUMAN CHECKPOINT** — pre-validation complete (below);
the executor never dispatches workflows and never pushes. Everything in this
checklist after the validation record is filled ONLY from real CI run results
supplied by the user.

## D-04 fail-closed validation record (git ls-remote, refreshed 2026-10-28 after the header-install ruling)

| Repo | Branch | Local SHA | Remote SHA | Pushed? |
|------|--------|-----------|------------|---------|
| SuperGenius | dev_blockstore | 6ed70cd99972b04f3796300827eaac3b38e811c8 | dc04ef71111ca11756fc17266f2f564ca8b74faa | **NO — 9 phase-12 commits ahead (e2fb50709..6ed70cd99)** |
| thirdparty | dev_db_storage | 8b00aee78d8ae36e348664d73590bf524b6e1dd3 | b612e46097f9512444572fab470bd73f6507b26d | **NO — 1 commit ahead (8b00aee, the fake-header install bump)** |
| thirdparty/sgns-blockstore | main | ee0266b54e7b0a35c5535b9cc3b7c404e94be17e | ff6a07beda0fefb30179abfd9d9b74ebb70aa252 | **NO — 1 commit ahead (ee0266b, the install rule)** |

**Approach change (user ruling 2026-10-28, superseding the Task-1 cache var +
CI sparse overlay):** the test fakes are now INSTALLED WITH the library —
`install(FILES src/InMemoryS3Client.hpp src/InMemoryS3AdminClient.hpp …)`
(sgns-blockstore ee0266b). The fakes' object code was already compiled into
the static library and their only non-std includes are installed public
headers, so nothing PRIVATE leaks. SuperGenius consumes them as
`<sgns-blockstore/InMemoryS3Client.hpp>` like every other library header;
`SGNS_BLOCKSTORE_TEST_SRC_DIR` and both CI sparse-overlay blocks are deleted.
Proven locally in the stronger form: thirdparty/sgns-blockstore/src HIDDEN,
all 12 cold targets built from the install tree alone, Tier-1 lane 12/12;
library Tier-1 14/14.

**This IS the D-14 library change the plan reserved a re-cut note for** — the
`test_coldstorage` thirdparty release tag must be cut AFTER these three repos
are pushed, so the tarball carries the installed fake headers (a tag cut
earlier would make the ON legs fail at the fakes' include).

**D-03 gate result: STOPPED BEFORE DISPATCH.** Push order for the user:
sgns-blockstore main → thirdparty dev_db_storage → SuperGenius
dev_blockstore (innermost first, as always).

## User actions (the D-03 checkpoint)

1. Push innermost-first: `main` in `thirdparty/sgns-blockstore` (ee0266b),
   then `dev_db_storage` in `thirdparty` (8b00aee), then `dev_blockstore` in
   SuperGenius (9 commits, e2fb50709..6ed70cd99) — plain `git push origin
   <branch>` in each.
2. Dispatch `thirdparty/.github/workflows/build-targets.yml` with a release
   tag covering Windows/Linux/OSX (sgns-blockstore included). The tag MUST
   post-date the pushes so the tarball carries the installed fake headers
   (it supersedes the `test_coldstorage` tag). Expected: a completed release
   page listing the new tag with platform tarballs.
3. Confirm the tag exists on the thirdparty releases page.
4. Dispatch `SuperGenius/.github/workflows/build-release-tags.yml` with
   `thirdparty_tag` = the cut tag, `run_tests=true`, `cold_storage=true`,
   and the `build_Windows_Release` / `build_Linux-x86_64_Release` /
   `build_OSX_Release` toggles enabled. Expected: three green runs, each
   showing `-DSGNS_COLD_STORAGE=ON` in the configure log and the Tier-1
   lane step passing.
5. Reply with the run URLs (plus the thirdparty release URL).

EXPECTED-RED caveat: the permanent cmake.yml ON legs will first run when the
SuperGenius push lands; until the sgns-blockstore-containing thirdparty tag
exists, those ON legs resolve a release WITHOUT the needed layout and fail at
configure — the documented transient window, recorded as such below, not a
defect. First GREEN ON-leg run URLs post-dating the tag cut are the
regression-net baseline.

## Thirdparty tag

- Tag name: _(pending user dispatch)_
- sgns-blockstore SHA in tag: ff6a07beda0fefb30179abfd9d9b74ebb70aa252 (validated above)
- Release URL: _(pending)_

## Platform results (filled from real runs)

### Windows Release (cold storage ON)
- Configure evidence (-DSGNS_COLD_STORAGE=ON visible): _(pending)_
- Tier-1 pass count: _(pending)_
- Run URL: _(pending)_

### Linux x86_64 Release (cold storage ON)
- Configure evidence: _(pending)_
- Tier-1 pass count: _(pending)_
- Run URL: _(pending)_

### OSX Release (cold storage ON)
- Configure evidence: _(pending)_
- Tier-1 pass count: _(pending)_
- Run URL: _(pending)_

## Permanent cmake.yml ON-leg baseline (regression net)

- Expected-red window runs (pre-tag): _(record URLs if the push preceded the tag cut)_
- First GREEN Windows-Release-ON run: _(pending)_
- First GREEN Linux-ON run: _(pending)_
- First GREEN OSX-ON run: _(pending)_

## Audit result

- tier1_static_audit: green in the local Tier-1 lane (12/12 including the
  audit; teeth spot-checked by scratch-removing a LABELS line — audit failed,
  reverted, lane green again). First CI-lane audit run: _(pending)_
