# Phase 16: Manifest Evolution - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-17
**Phase:** 16-Manifest Evolution
**Areas discussed:** Content-defined chunking scope (ARTF-08), Merkle tree necessity (ARTF-07), Error message capture (ARTF-09)

---

## Content-Defined Chunking Scope (ARTF-08)

| Option | Description | Selected |
|--------|-------------|----------|
| Scoped proof | CDC for one representative processor path only, rest documented as fixed-size | |
| Full migration | Replace `block_len` splitting across all ~11 processor types | |
| Let Claude decide | Researcher/planner determine scope | |

**User's choice:** Free-text — questioned the premise entirely: "I'm not fully certain what is wrong with block_len defining the chunk size to begin with? I think I need more explanation as to what this is solving."

Claude explained the fixed-size-chunking "insertion problem" (a length-changing edit shifts every downstream boundary) and its intended benefit (Phase 08's D-01 dedup/caching goal, incremental re-validation), while noting it was originally deferred without a concrete pain point.

**Follow-up round 1:**

| Option | Description | Selected |
|--------|-------------|----------|
| Scoped proof | Same as above | |
| Full migration anyway | Same as above | |
| Reduce to documentation-only | Don't implement, formally re-defer like XNODE-01c | |

**User's choice:** Free-text — "if the data changes and it no longer fits, the job poster has kinda failed... They decided the parameters of chunking when they submitted the job... This is only applicable if the data source is http or sftp or something though, an ipfs bitswap cid should be as it was posted from the start."

Claude verified this against the codebase: `FileManager` (thirdparty/AsyncIOManager) does register loaders/savers by URL prefix including `https`/`file` alongside the IPFS bitswap path — confirming non-CID sources exist and the user's distinction is architecturally real, not hypothetical.

**Follow-up round 2:**

| Option | Description | Selected |
|--------|-------------|----------|
| Scoped proof on http/file path | CDC only for the mutable-source fetch path | |
| Full migration anyway | Same as above | |
| Reduce to documentation-only | Same as above | |

**User's choice:** Free-text — "Regardless of whether inputs could be changed on http sources, they have defined block length when submitting the job, if it is incorrect it is not up to use to arbitrarily decide on a new one I feel. If it doesn't work, bad job, mark as failure. I don't see why we need to solve for this. I feel like we just do nothing."

**Final decision:** Won't implement — not applicable (see CONTEXT.md D-05..D-08).
**Notes:** Job poster owns the `block_len` contract at submission time; a shape mismatch is a bad-job failure to surface, not a chunking gap to close.

---

## Merkle Tree Necessity (ARTF-07)

Claude proactively raised the same style of question after the CDC discussion, before locking scope: does anyone actually consume a Merkle root without already having the full chunk hash list?

| Option | Description | Selected |
|--------|-------------|----------|
| No real scenario — do nothing | Re-defer with the same rationale as ARTF-08 | |
| Build root-only anyway | Add as defense-in-depth even without a consumer | |
| There is a real need — let me explain | User has a specific scenario in mind | |

**User's choice:** Free-text — "They got a task result over graphsync, they should have as defined by protobuf all the subtasks and their chunks, meaning they have the hashes in there... generally their role is not to have that [raw data]... except in cases of fallback due to chunk hash mismatch, which is another thing altogether."

This confirmed graphsync/protobuf task results already carry the full chunk hash list to every real verifier — no root-only scenario exists in the current architecture.

**Follow-up (confirmation):**

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, re-defer ARTF-07 too | | |
| No, keep as minimal root-only addition | | |

**User's choice:** Free-text — "Deferred implies we're going to revisit it, seems like it should be marked as done, or will not implement, or something, so it doesn't come up again?"

**Final decision:** Won't implement — not applicable, using the status label "Won't implement — not applicable" rather than "deferred" (see CONTEXT.md D-01..D-04).
**Notes:** User specifically rejected "deferred" as a status term since it implies future revisit; this is a closed architectural conclusion.

---

## Error Message Capture (ARTF-09)

**Consumer question:** Claude asked whether there's a specific consumer in mind vs. general good practice.

**User's choice:** Free-text — "Any caller should get an error, probably in outcome form. That's just generally good practice, we can use it where needed."

**Truncation policy:**

| Option | Description | Selected |
|--------|-------------|----------|
| Truncate at 256 bytes | Silent truncation, matches Phase 08 D-06's anticipated cap | ✓ |
| Truncate with a marker | Truncate + explicit indicator | |
| Let Claude/planner decide | | |

**User's choice:** "Truncate at 256 bytes (recommended)"
**Notes:** Matches Phase 08's D-06, which already anticipated this exact cap.

---

## Schema Evolution (ARTF-10)

Not put to a choice — Claude noted this requirement is the forcing mechanism for ARTF-09's new field (current serializer hard-fails on any size mismatch, no version field exists), and the roadmap's SC4 already locks in the required both-directions compat proof. No open user-facing tradeoff surfaced; exact layout left to planning.

---

## Claude's Discretion

- Exact binary layout for ARTF-10's versioning mechanism (magic/version header vs. trailing optional/TLV section).
- Exact field name/type/offset for ARTF-09's error message field.
- How `artifact_serializer_test.cpp`'s hardcoded-offset assertions get extended for the new field(s).
- Exact REQUIREMENTS.md/ROADMAP.md wording for marking ARTF-07/ARTF-08 as "Won't implement — not applicable."

## Deferred Ideas

None — ARTF-07/ARTF-08 are this phase's own scope conclusions (captured in CONTEXT.md), not ideas deferred to a future phase.
