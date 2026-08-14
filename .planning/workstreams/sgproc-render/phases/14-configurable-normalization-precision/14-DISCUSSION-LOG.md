# Phase 14: Configurable Normalization Precision - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-13
**Phase:** 14-Configurable Normalization Precision
**Areas discussed:** Schema declaration mechanism, Value semantics & bad input, Byte-path technique, tex3d's value & security coverage

---

## Schema declaration mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse generic 'parameters' array | No schema/quicktype changes; mirrors `ParseLayout`'s find-by-name convention | ✓ |
| New formal schema field | Dedicated typed field in `gnus-processing-schema.json`, requires quicktype regen | |

**User's choice:** Reuse generic 'parameters' array (recommended)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| quantScale / byteQuantMode | Distinct, type-specific names mirroring `volumeLayout`'s pattern | ✓ |
| Single shared name | One key, processor infers meaning from its own data type | |
| Let Claude decide exact strings | Lock only that float/byte are separately nameable | |

**User's choice:** quantScale / byteQuantMode (recommended)
**Notes:** —

**More questions or next area:** Next area (schema mechanism and naming locked)

---

## Value semantics & bad input

| Option | Description | Selected |
|--------|-------------|----------|
| Raw scale S, must be power-of-two | Job declares S directly, same round(x*S)/S formula | ✓ |
| Grid-step / epsilon value | Job declares tolerance, code derives S = 1/epsilon | |

**User's choice:** Raw scale S, must be power-of-two (recommended)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Silently fall back to v2.1's S=2^15 | Invalid value treated same as no declaration | ✓ |
| Log a warning, then fall back | Same fallback, but warns the job author | |
| Hard error — reject the job | Invalid value fails job validation outright | |

**User's choice:** Silently fall back to v2.1's S=2^15 (recommended)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Enforced in code | Config path validates positive power-of-two before use | ✓ |
| Documented guidance only | Any positive finite number accepted as declared | |

**User's choice:** Enforced in code (recommended)
**Notes:** —

**More questions or next area:** Next area (value semantics locked)

---

## Byte-path technique

| Option | Description | Selected |
|--------|-------------|----------|
| Bit-masking low N bits | value &= ~((1<<N)-1), cheap and directly analogous to grid coarsening | ✓ |
| Scale-round-cast analogous to float path | Mirrors float technique exactly, adds conversion overhead | |
| Let Claude decide the technique | Lock only additive/schema-declarable requirement | |

**User's choice:** Bit-masking low N bits (recommended)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Number of low bits to mask, N | byteQuantMode = 2 means mask low 2 bits; N=0/absent = today's no-op | ✓ |
| Explicit bitmask value | Declares the literal AND-mask byte directly | |

**User's choice:** Number of low bits to mask, N (recommended)
**Notes:** —

**More questions or next area:** Next area (byte technique locked; invalid values fall back to N=0 per the same silent-fallback pattern, confirmed in the transition prompt's framing)

---

## tex3d's value & security coverage

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add a tex3d SECV counter-test this phase | Mirrors v2.1's discipline of pairing every empirical constant with a corruption counter-test | ✓ |
| Defer to Phase 15's SECV-02 | SECV-02 could be written to cover tex3d instead |  |
| Not required — existing SECV-01 is sufficient | Smallest scope, leaves tex3d's grid unverified | |

**User's choice:** Yes, add a tex3d SECV counter-test this phase (recommended)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Binary search against the new counter-test | Same methodology as Phase 13's S=2^15 derivation | ✓ |
| Fixed margin over the measured delta, no search | Faster, no iterative confirmation |  |
| Let Claude decide within the estimated 2^7-2^8 range | Lock only the final-value requirements | |

**User's choice:** Binary search against the new counter-test (recommended)
**Notes:** —

**More questions or done:** I'm ready for context

---

## Claude's Discretion

- Exact mechanism for threading the resolved S/N value into `QuantizeFloatBuffer`/`QuantizeByteBuffer` (new parameter, overload, or per-site resolver) — left to research/planning.
- Exact file/test names for the new tex3d SECV counter-test — follow `secv01_counter_test.cpp`'s existing convention.

## Deferred Ideas

- Relative/ULP-based (mantissa-bit-masking) quantization technique for the float path — Phase 12's deferred item stands unchanged.
- Scale-round-cast analog for the byte path — considered, not chosen (bit-masking picked instead).
- New formal schema field / quicktype schema changes for precision declaration — considered, not chosen.
- Modifying `ComputeManifestHash`/`ExecutionManifest` for cross-machine-comparable manifest hash — reaffirmed out of scope again.
- Actual cross-node consensus/redundant-execution plumbing (XNODE-01c) — explicitly out of scope per REQUIREMENTS.md.
