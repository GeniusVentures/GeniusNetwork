# 12-FRESH-CLONE-CHECKLIST — SC4 Fresh-Clone Proof (TEST-02 / D-05)

Status: **COMPLETE 2026-11-10** â€” all three SC4 legs green in SuperGenius Tag
Build run 42905264387 (workflow_dispatch, dev_blockstore @ 9994718ce,
thirdparty tag `test_coldstorage_rtti`, run_tests=true, cold_storage=true,
all 15 jobs success). Evidence tables below.

## D-04 fail-closed validation record (git ls-remote, refreshed 2026-10-28 after the header-install ruling)

| Repo | Branch | Local SHA | Remote SHA | Pushed? |
|------|--------|-----------|------------|---------|
| SuperGenius | dev_blockstore | 6ed70cd99972b04f3796300827eaac3b38e811c8 | 6ed70cd99972b04f3796300827eaac3b38e811c8 | YES (user pushed 2026-10-28; tag `test_coldstorage` also moved onto it) |
| thirdparty | dev_db_storage | 8b00aee78d8ae36e348664d73590bf524b6e1dd3 | 8b00aee78d8ae36e348664d73590bf524b6e1dd3 | YES (user pushed 2026-10-28) |
| thirdparty/sgns-blockstore | main | ee0266b54e7b0a35c5535b9cc3b7c404e94be17e | ee0266b54e7b0a35c5535b9cc3b7c404e94be17e | YES (user pushed 2026-10-28) |

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

**D-03 gate result: SATISFIED 2026-11-10.** User pushed all three repos
(innermost-first) and dispatched the tag build; SuperGenius dev_blockstore
advanced to 9994718ce (two CI commits forcing self-hosted runners â€” cherry-
picked cmake.yml 669cb821b + mirrored build-release-tags.yml; runner
selection only, zero build-content change) before the dispatch.

## D-04 fail-closed validation record (final refresh 2026-11-10)

| Repo | Branch | SHA (run-verified) | Pushed? |
|------|--------|--------------------|---------|
| SuperGenius | dev_blockstore | 9994718ce (run 42905264387 head) | YES |
| thirdparty | dev_db_storage | 4a97e95 (= test_coldstorage_rtti tag target) | YES |
| thirdparty/sgns-blockstore | main | ee0266b | YES |

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

- **FINAL consumed tag: `test_coldstorage_rtti`** (cut 2026-11-02, target 4a97e95 = thirdparty dev_db_storage HEAD; all 14 platform assets; post-dates the fake-header install ee0266b AND adds RocksDB USE_RTTI=ON — the RTTI requirement is what forced the re-cut over `test_coldstorage`). Release URL: https://github.com/GeniusVentures/thirdparty/releases/tag/test_coldstorage_rtti
- Interim tag `test_coldstorage` (superseded; history): first tag to carry the fake-header install. Original record:
- Tag name: **`test_coldstorage`** (assets clobbered by run 40798318449, dispatched 2026-10-29T01:06Z from dev_db_storage @ 8b00aee — carries the fake-header install). The tag REF still points at 1209fb5 and was NOT moved — irrelevant: every consumer downloads the release ASSETS by tag name, never the git tag ref.
- Freshness (asset updated_at): 13/14 assets clobbered 01:15–02:06Z; **Windows-Debug.tar.gz stale** (2026-10-28T04:02 — the failed leg, os error 4551 Application Control block on wallet-core's cargo build-script, environmental; user re-running).
- Payload verified: Windows-Release.tar.gz (fresh, 01:33:58Z) contains `build/Windows/Release/sgns-blockstore/include/sgns-blockstore/InMemoryS3Client.hpp` AND `InMemoryS3AdminClient.hpp` (tar listing, 2 hits) — the header-install change reached the assets the ON lanes consume.
- sgns-blockstore SHA in the build: ee0266b (via thirdparty 8b00aee; validated pushed)
- Release URL: https://github.com/GeniusVentures/thirdparty/releases/tag/test_coldstorage

## Platform results â€” run 42905264387 (all three legs, one dispatch)

Run: https://github.com/GeniusVentures/SuperGenius/actions/runs/42905264387
(dispatch 2026-11-10, head 9994718ce, all 15 matrix jobs success;
`Downloading thirdparty from tag: test_coldstorage_rtti` verified in every leg's log)

### Windows Release (cold storage ON)
- Configure evidence: `-DSGNS_COLD_STORAGE=ON` in the configure command (COLD_STORAGE_ARGS env, log-verified) â—d **153/153, 100% tests passed**
- Run URL: https://github.com/GeniusVentures/SuperGenius/actions/runs/42905264387 (job: build (Windows, Release))

### Linux x86_64 Release (cold storage ON)
- Configure evidence: same â—d **152/152, 100% tests passed** (tier1_static_audit = Test #15, Passed 0.03s)
- Run URL: same run (job: build (Linux, x86_64, Release))

### OSX Release (cold storage ON)
- Configure evidence: same â—d **155/155, 100% tests passed** (consistent with the 2026-11-05 OSX-only rerun 42130985363: same count at b85778ef6)
- Run URL: same run (job: build (OSX, Release))

## Permanent cmake.yml ON-leg baseline (regression net)

- Baseline PENDING by topology, not by defect: dev_blockstore pushes do not
  trigger cmake.yml (its push filters do not watch this branch), so the
  permanent ON legs first run when this branch merges to develop. The tag-
  build legs above prove the identical configure (same COLD_STORAGE_ARGS
  append, same artifact consumption) â€” the D-02a net activates at merge.

## Audit result

- tier1_static_audit: **GREEN IN CI** â€” Linux-x86_64-Release leg of run
  42905264387, Test #15/152 Passed (0.03 sec); included in every leg's 100%
  pass count. (Local pre-check had already exercised the teeth: scratch-
  removing a LABELS line failed the audit; restored, lane green.)
