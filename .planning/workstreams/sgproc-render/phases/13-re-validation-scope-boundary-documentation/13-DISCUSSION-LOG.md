# Phase 13: Re-Validation & Scope Boundary Documentation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-12
**Phase:** 13-Re-Validation & Scope Boundary Documentation
**Areas discussed:** Machine-count reconciliation, Hash-target wording fix, Re-capture logistics, Scope-boundary doc

---

## Machine-count reconciliation

**Q1: Do you now have access to a genuine 3rd physical machine, or should Phase 13 accept the 2-machine dataset?**

| Option | Description | Selected |
|--------|-------------|----------|
| Accept 2 machines (recommended) | Mirrors Phase 11's D-01/D-03 precedent — no genuine 3rd machine since Phase 11 | ✓ |
| 3rd machine now available | Would let Phase 13 hit the literal ≥3-machine bar | |
| You decide | Default to 2-machine acceptance unless flagged otherwise | |

**User's choice:** Accept 2 machines (recommended)

**Q2: Should the VALD-01/SC1 wording fix ('≥3' → '≥2') be captured now as a locked decision for the planner to apply?**

| Option | Description | Selected |
|--------|-------------|----------|
| Locked decision, planner applies it (recommended) | Same as Phase 11's D-03 pattern | ✓ |
| Leave wording as-is, just document the gap | Less consistent with Phase 11's own precedent | |

**User's choice:** Locked decision, planner applies it (recommended)

---

## Hash-target wording fix

**Q1: What should VALD-01/SC1's 'combined hashes' actually mean and measure?**

| Option | Description | Selected |
|--------|-------------|----------|
| Processor-level result/chunk hash (recommended) | Matches D-01's own framing — the hash ProcessingValidationCore actually compares | ✓ |
| Keep targeting ProcessOutput.combinedHash | Would require excluding executorIdentity/gpuMemoryUsedBytes from ComputeManifestHash — declined in Phase 12 | |

**User's choice:** Processor-level result/chunk hash (recommended)

**Q2: Should REQUIREMENTS.md VALD-01 and ROADMAP.md Phase 13 SC1 be edited to say 'processor-level result/chunk hash' explicitly?**

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, edit both docs (recommended) | Same class of fix as the machine-count wording | ✓ |
| No, only document it in the scope-boundary doc | Leave VALD-01/SC1 text as-is | |

**User's choice:** Yes, edit both docs (recommended)

---

## Re-capture logistics

**Q1: Who runs the fresh capture_harness pass on each machine?**

| Option | Description | Selected |
|--------|-------------|----------|
| You run it by hand on both machines (recommended) | Same hands-on pattern as Phase 11 | ✓ |
| Windows only, Mac capture reused/skipped | Weaker — Mac's Phase 11 capture predates real quantization | |

**User's choice:** You run it by hand on both machines (recommended)

**Q2: Where should Phase 13's fresh capture files and diff results live?**

| Option | Description | Selected |
|--------|-------------|----------|
| New captures/ subdir in Phase 13's own dir (recommended) | Mirrors Phase 11's convention | ✓ |
| Append into Phase 11's existing captures/ dir | Mixes stub-era and real-quantization-era captures | |

**User's choice:** New captures/ subdir in Phase 13's own dir (recommended)

**Q3: What does 're-run SECV-01 at the final precision' mean for this phase?**

| Option | Description | Selected |
|--------|-------------|----------|
| Just re-run the existing CTest and cite the result (recommended) | No new test code — Phase 12's constants are the final precision | ✓ |
| Something else needs to change first | — | |

**User's choice:** Just re-run the existing CTest and cite the result (recommended)

---

## Scope-boundary doc

**Q1: Where should the scope-boundary record (SC3) live?**

| Option | Description | Selected |
|--------|-------------|----------|
| New phase-owned doc, e.g. 13-SCOPE-BOUNDARY.md (recommended) | Mirrors Phase 11's 11-CAPTURE-RESULTS.md convention | ✓ |
| Fold into PROJECT.md's workstream section | Would be the first milestone-scope-boundary style entry there | |

**User's choice:** New phase-owned doc, e.g. 13-SCOPE-BOUNDARY.md (recommended)

**Q2: Should 13-SCOPE-BOUNDARY.md also fold in SC4 constants/derivation and SC1/SC2 re-validation results?**

| Option | Description | Selected |
|--------|-------------|----------|
| One combined doc: scope boundary + re-validation results + constants (recommended) | Phase 13's scope is small enough for one file | ✓ |
| Split: 13-SCOPE-BOUNDARY.md (boundary only) + separate results doc | Mirrors Phase 11's CONTEXT.md/CAPTURE-RESULTS.md split more literally | |

**User's choice:** One combined doc: scope boundary + re-validation results + constants (recommended)

---

## Claude's Discretion

- Exact prose/structure of `13-SCOPE-BOUNDARY.md` (tables vs. prose, section ordering)
- Exact wording of the ROADMAP.md/REQUIREMENTS.md edits, as long as they land on "≥2 machines" and "processor-level result/chunk hash"
- Whether `.cap` filenames follow Phase 11's exact naming convention

## Deferred Ideas

- Excluding `executorIdentity`/`gpuMemoryUsedBytes` from `ComputeManifestHash` so `ProcessOutput.combinedHash` becomes cross-machine-comparable — reaffirmed out of scope (already deferred in Phase 12)
- Adding a genuine 3rd physical machine's captures — not blocking, could be a small follow-up later
