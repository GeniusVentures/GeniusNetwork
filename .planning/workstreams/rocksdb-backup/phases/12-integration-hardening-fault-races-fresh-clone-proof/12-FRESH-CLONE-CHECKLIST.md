# 12-FRESH-CLONE-CHECKLIST — SC4 Fresh-Clone Proof (TEST-02 / D-05)

Status: **AWAITING D-03 HUMAN CHECKPOINT** — pre-validation complete (below);
the executor never dispatches workflows and never pushes. Everything in this
checklist after the validation record is filled ONLY from real CI run results
supplied by the user.

## D-04 fail-closed validation record (git ls-remote, 2026-10-28)

| Repo | Branch | Local SHA | Remote SHA | Pushed? |
|------|--------|-----------|------------|---------|
| SuperGenius | dev_blockstore | dc04ef71111ca11756fc17266f2f564ca8b74faa | a49fa72d2f55c08c143ce78ce580ece4780757e4 | **NO — 8 phase-12 commits ahead (e2fb50709..dc04ef711)** |
| thirdparty | dev_db_storage | b612e46097f9512444572fab470bd73f6507b26d | b612e46097f9512444572fab470bd73f6507b26d | YES |
| thirdparty/sgns-blockstore | main | ff6a07beda0fefb30179abfd9d9b74ebb70aa252 | ff6a07beda0fefb30179abfd9d9b74ebb70aa252 | YES |

**D-03 gate result: STOPPED BEFORE DISPATCH.** The SuperGenius phase branch
carries the phase-12 work locally (fault-race matrix, resurrection suite +
the crdt_set fix, soak suites, audit, cache var, CI legs). The only-pushed-
commits clause requires those commits on the remote BEFORE any tag dispatch.
The thirdparty side (the tag the ON lanes consume) is fully pushed and
carries NO phase-12 library change (12-01/12-02 recorded zero sgns-blockstore
library edits — the resurrection fix landed SuperGenius-side in
src/crdt/impl/crdt_set.cpp; no D-14 re-cut pending).

## User actions (the D-03 checkpoint)

1. Push `dev_blockstore` in SuperGenius (8 commits, e2fb50709..dc04ef711) —
   the branch is already remote-tracked; a plain `git push origin dev_blockstore`.
2. Dispatch `thirdparty/.github/workflows/build-targets.yml` with a release
   tag covering Windows/Linux/OSX (sgns-blockstore included). Expected: a
   completed release page listing the new tag with platform tarballs.
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
