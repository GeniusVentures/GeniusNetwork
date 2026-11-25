---
phase: "17"
slug: "seal-growth-measurement-decision"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-11-24"
---

# Phase 17 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

> Input state B (no prior SECURITY.md; created retroactively from PLAN registers + SUMMARY evidence + the 2026-11-24 refreshed verification).
> L1 short-circuit applied: threats_open 0 · register authored at plan time · asvs_level 1 (no auditor spawn required).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| env knobs → harness behavior | integer env vars select scale/repeats/seed; hostile values could distort measurements | env integers |
| harness → measured hot store | the probe writes seal rows into the store it measures; unsanctioned writes corrupt the evidence chain | seal rows |
| evidence output → downstream citations | JSON/MD numbers become the decision record's capacity math | committed evidence |
| walk fixture → production walk machinery | the fidelity leg drives the real walk surface; a fixture defect could be misread as a walk defect | walk states |
| dev-gated big legs → committed evidence | posture drift between legs corrupts the curve | options fingerprints |
| recorded verdict → production constant | the D-12 verdict is the sole authorizer of the phase's single production edit | verdict record |
| decision doc → future milestones | Phase 18's policy record and any redesign milestone consume this doc as ground truth | decision numbers |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-17-01 | Tampering | probe corrupting the measured store | medium | mitigate | Read/count/time-only posture, source-gated. Evidence: verifier 2026-11-24 — harness unmodified since phase 17's commit, posture intact, zero seal spill/compaction/sidecar machinery in the src delta | closed |
| T-17-02 | Tampering | hand-constructed seal keys making seeded rows non-representative | medium | mitigate | Suffix-append pattern gate; fidelity leg proves byte-identity with walk-produced rows | closed |
| T-17-03 | Repudiation | evidence numbers drifting/fabricated after commit | medium | mitigate | Flat JSON with dataset + options fingerprints; decision doc cites committed JSON keys only. Evidence: verifier re-cross-checked every decision-record number exact (52.0 B/row both scales, 6,250,308.401 rows/s, 5.2×10^9) | closed |
| T-17-04 | Denial of Service | env-var injection steering fixture paths | low | mitigate | Integer-only EnvOr parsing; fixed relative fixture roots; bounded floor leg | closed |
| T-17-05 | Tampering | Tier-1 floor leg flaking or passing vacuously | low | mitigate | Floors at measured/10 + bytes band; exact-count assertion; --no-tests=error. Evidence: cold_seal_growth_test PASSED fresh (verifier 8.09s; lane run 8.65s) | closed |
| T-17-06 | Tampering | fidelity leg proving identity vacuously | medium | mitigate | Structurally distinct twin-store; visited > 0 asserted; exact-key-bytes set comparison | closed |
| T-17-07 | Tampering | density legs reading a wrong denominator | medium | mitigate | Generator's emitted-ancestry denominator; density == fraction asserted | closed |
| T-17-08 | Repudiation | big-leg curve contaminated by posture drift | medium | mitigate | Options fingerprint per leg; one growing dataset; differing-fingerprint legs never compared silently | closed |
| T-17-09 | Tampering | third /prune/* key builder in the harness | medium | mitigate | All writes/reads through the sanctioned helpers; concatenated-/prune/* source gate (count zero) | closed |
| T-17-10 | Information Disclosure | env values or machine-sensitive data in captures | low | mitigate | NAMES-only runbook rule; redaction grep zero matches; JSON carries fingerprints never secrets | closed |
| T-17-11 | Tampering | the one production touch smuggling behavior change beyond the sanctioned constant | high | mitigate | Verdict committed before the edit (git chronology); total src diff gated to the constant + comment; append-only derivation comment; Tier-1 green after any touch. Evidence: verifier confirmed kForcedWalkPeerFailoverPerCid = 8 untouched at HEAD (the one header shift is phase-19's production-null test seam, not a re-tune); empty src diff for the in-band verdict | closed |
| T-17-12 | Repudiation | band loosened / verdict rewritten post-hoc | medium | mitigate | Band→verdict→amendment as separate commits; every figure cites committed JSON keys; comparison inputs recorded beside the verdict | closed |
| T-17-13 | Repudiation | decision doc citing non-resolving sources | medium | mitigate | Scripted four-source citation list; verify-gate greps for ruled-out phrasing + JSON-key citations; extrapolated figures labeled | closed |
| T-17-14 | Tampering | STATE.md edit exceeding the one sanctioned bullet | low | mitigate | Task text forbids Current Position edits; verify gate checks bullet existence + no rode-along SuperGenius changes | closed |
| T-17-SC | Tampering | package installs (npm/pip/cargo) | high | accept | Zero package-manager installs across all three plans (zero new dependencies per the v1.2 ruling); unplanned install halts the run | closed (accepted) |

*Status: open · closed · open — below high threshold (non-blocking)*
*Only open threats at or above workflow.security_block_on (high) count toward threats_open*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-17-01 | T-17-SC | Zero package-install surface in all three plans; unplanned-install halt covers residual risk | Plans 17-01..17-03 (owner-approved) | 2026-11-19 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-11-24 | 15 | 15 | 0 | gsd-secure-phase (L1 short-circuit: plan-authored register, asvs_level 1, threats_open 0; cross-checked against the refreshed 17-VERIFICATION.md — 8/8 must-haves at HEAD, decision numbers re-cross-checked exact, D-12 constant untouched) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-11-24
