# Phase 10: Capture Harness & Diff Tool (Quantization Stub) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-08
**Phase:** 10-Capture Harness & Diff Tool (Quantization Stub)
**Areas discussed:** Capture file format & naming, Machine-identity tag content, Same-node stability check (CAPT-03) workflow, Diff tool output format

---

## Capture File Format & Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Binary (reuse Phase 08) | Reuses artifact_serializer.hpp/.cpp's existing SerializeArtifact/SerializeManifest convention directly | |
| JSON/text | Easier to manually inspect by eye, but a new ad-hoc format | |
| You decide | Claude picks based on Phase 08's precedent and the diff tool's needs | ✓ |

**User's choice:** You decide → Claude selected binary (reuse Phase 08's `artifact_serializer` convention), per research's explicit recommendation.

| Option | Description | Selected |
|--------|-------------|----------|
| fixture_machine_timestamp | Sortable by time, shows fixture + machine at a glance | ✓ |
| fixture_machine only | Simpler, but re-running overwrites the previous capture | |
| You decide | Claude picks a convention consistent with existing patterns | |

**User's choice:** fixture_machine_timestamp
**Notes:** Motivated by moving capture files between the user's own Mac/PC/third machine in Phase 11 without collisions.

---

## Machine-Identity Tag Content

| Option | Description | Selected |
|--------|-------------|----------|
| Hostname + OS + GPU vendor/driver | Richest diagnostic info, but requires querying GPU/driver info | |
| Hostname + OS only | Simpler to gather, still uniquely identifies the machine | ✓ |
| User-supplied label | Simplest to implement, relies on user remembering to set it | |

**User's choice:** Hostname + OS only

---

## Same-Node Stability Check (CAPT-03) Workflow

| Option | Description | Selected |
|--------|-------------|----------|
| Built-in --repeat N flag | Runs N times internally, self-checks, one command | ✓ |
| Manual: run twice, diff yourself | Reuses capture_diff instead of adding new logic | |
| You decide | Claude picks based on simplicity | |

**User's choice:** Built-in --repeat N flag

| Option | Description | Selected |
|--------|-------------|----------|
| Abort, write nothing | Refuses to produce a capture file if unstable | ✓ |
| Write anyway, flag as unstable | Still writes the file but marks it as failed-stability-check | |

**User's choice:** Abort, write nothing

---

## Diff Tool Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| Console only (Phase 10) | Human-readable summary, JSON deferred | |
| Console + JSON now | Both human-readable and machine-readable output this phase | ✓ |

**User's choice:** Console + JSON now
**Notes:** Anticipates scripting comparisons across multiple machine pairs in Phase 11.

| Option | Description | Selected |
|--------|-------------|----------|
| CLI flag, e.g. --threshold | Adjustable per-run | |
| Fixed default | Simplest, hardcoded | ✓ |

**User's choice:** Fixed default
**Notes:** Exact epsilon value left to Claude's discretion — quantization is a no-op stub this phase, so the threshold exists to exercise the reporting mechanism, not to make a precision claim.

---

## Claude's Discretion

- Exact fixed default threshold value for DIFF-02's percentage-of-elements-exceeding-threshold
- Exact `--repeat` default N (roadmap requires N≥2)
- Exact JSON schema/field names for capture_diff's machine-readable report
- Exact CLI flag names and argument parsing approach
- Internal structure of the shared quantization stub (already specified at file:line level by research)
- Versioning/magic-number scheme for the new raw-bytes section appended to the binary capture format

## Deferred Ideas

- Real quantization/normalization logic — belongs to Phase 12
- CLI-configurable DIFF-02 threshold — fixed default chosen for Phase 10; could become configurable later
- GPU vendor/driver detail in the machine-identity tag — hostname + OS chosen for Phase 10; could be added later if needed for diagnosis
