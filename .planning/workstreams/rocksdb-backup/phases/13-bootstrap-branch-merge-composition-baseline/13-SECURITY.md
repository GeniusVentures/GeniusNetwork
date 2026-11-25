---
phase: "13"
slug: "bootstrap-branch-merge-composition-baseline"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-11-24"
---

# Phase 13 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

> Input state B (no prior SECURITY.md; created retroactively from PLAN registers + SUMMARY evidence).
> L1 short-circuit applied: threats_open 0 · register authored at plan time · asvs_level 1 (no auditor spawn required).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| local git object DB → branch refs | the pinned tips (7961ec264 / d556f86de / base 8ff74636b) are the merge's inputs; silent drift changes what gets merged | git commit SHAs (integrity-critical) |
| working tree → baseline evidence | pre-merge numbers are a valid denominator only if produced on exactly the pinned tip in a clean tree | test logs / ctest counts |
| auto-merge snapshot → committed merge | the only sanctioned divergence is the single GeniusNode.cpp hunk; anything else is a hand-edit or pointer rollback | merged tree blobs / gitlinks |
| test execution → evidence record | checklist SC3 rows claim suites green and greps empty; a mis-run lane or false-positive grep would forge evidence | verbatim gate outputs |
| local merge commit → origin (GitHub) | the push publishes the canonical v1.2 remote line — wrong refspec or premature push is one-way remote state | git refs on origin |
| evidence docs → future phases | Phase 14–19 planning trusts the committed SC4 record; transcribed gate outputs could mask drift | planning artifacts |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-13-01 | Tampering | branch tips / topology re-verification (13-01 pre-merge) | high | mitigate | SHA-pin all inputs; re-verify rev-parse + merge-base before merge; deviation halts for D-14 escalation. Evidence: D-02 live re-verification + `reset-clean-ok` + topology table committed (`4eb9836`) | closed |
| T-13-02 | Tampering | merge resolution in src/account/GeniusNode.cpp | high | mitigate | D-14 pre-authored compose rule + D-15a tree-diff + D-15b byte-identity, pre- AND post-commit. Evidence: D-15a-1 exit 0 both passes; composed region re-verified in-editor during 13-UAT (Test 4) | closed |
| T-13-03 | Tampering | submodule pointers (SGProcessingManager / docs) — D-02 disposition | high | mitigate | Ancestor-check proof of stale merge-base checkouts; user picked reset; `git submodule update`; pointer equality verified. Evidence: 13-01 Deviations 1 & 3 | closed |
| T-13-04 | Tampering | GATE-03 / verification evidence | medium | mitigate | Quote-safe piped grep (Pitfall 1); fail-closed ctest lanes (`--no-tests=error`); verbatim outputs with counts. Evidence: grep-matches=0, term-count=16 (13-03 verify blocks 5–6) | closed |
| T-13-05 | Repudiation | merge/evidence provenance | low | accept | git history immutable; merge message cites checklist; as-run evidence + user-attested push committed (D-16) | closed (accepted) |
| T-13-06 | Tampering | remote push (origin/dev_coldstorage_additions creation) | high | mitigate | D-04 blocking human checkpoint — executor never pushes; pre-stated exact refspec; post-push ls-remote equality. Evidence: `remote-equals-merge-sha` (13-04); zero executor pushes | closed |
| T-13-07 | Tampering | branch tips / topology re-verification (13-02 merge execution) | high | mitigate | Six-ref rev-parse against pinned SHAs + merge-base before merging; fresh merge-tree OID regenerated (`08bffc1e8`, deviation from research OID expected and explained). Evidence: parents pinned `4ae8a9a4e`+`d556f86de` (13-02) | closed |
| T-13-08 | Tampering | execution tree identity (still on merge commit) | high | mitigate | Each leg confirms `git rev-parse HEAD` == 13-02 merge SHA before running. Evidence: SC2 post-leg run at `2af184fa1` (13-03 table); merge-is-ancestor-of-HEAD re-verified during 13-UAT (Test 1) | closed |
| T-13-09 | Tampering | submodule gitlinks in the merge | high | mitigate | D-15a assertion 1 empty — zero pointers moved by the merge. Evidence: `gitlink-diff-empty=True`; empty diff re-verified during 13-UAT (Test 2) | closed |
| T-13-10 | Tampering | finalized evidence (stale gate outputs) | medium | mitigate | Read-only D-15 gates RE-RUN at final HEAD with fresh outputs, not transcriptions. Evidence: `d15b-final-exit=0`, `gate03-final-matches=0`, parents pinned at final HEAD (13-04) | closed |
| T-13-SC | Tampering | package installs (npm/pip/cargo) | high | accept | All four plans install no packages (git/ctest/cmake/grep only); any unplanned install halts the run. Accepted at plan time in 13-01..13-04 | closed (accepted) |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on (high) count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-13-01 | T-13-05 | Git history immutability + committed as-run evidence + user-attested push form a sufficient audit trail without further provenance machinery | Plan 13-04 (owner-approved) | 2026-11-16 |
| AR-13-02 | T-13-SC | Zero package-manager surface in all four plans (git/ctest/cmake/grep only); unplanned-install halt covers residual risk | Plans 13-01..13-04 (owner-approved) | 2026-11-16 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-11-24 | 11 | 11 | 0 | gsd-secure-phase (L1 short-circuit: plan-authored register, asvs_level 1, threats_open 0) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-11-24
