# Phase 7: SuperGenius Build Wiring & Config Gate - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-23
**Phase:** 7-SuperGenius Build Wiring & Config Gate
**Areas discussed:** Config section naming, Blank-vs-malformed edge, Env override surface, M3 backup posture

---

## Config section naming

| Option | Description | Selected |
|--------|-------------|----------|
| Nested `blockstore` | INTG-02's own wording; backend-agnostic capability name; retention/backpressure knobs nest cleanly; departs from flat style | ✓ |
| Flat `blockstore_*` | Matches existing flat `backup_*` style; ~10 top-level keys by Phase 11; per-key blank-semantics awkward | |
| `s3d.*` keys | ARCH-doc shorthand; names the backend implementation; lies if s3d is ever swapped | |

**User's choice:** Nested `blockstore`
**Notes:** — 

| Option | Description | Selected |
|--------|-------------|----------|
| Fields directly | One backend in v1.1; simplest parse and wallet-asset parity | ✓ |
| `s3` sub-object | Mirrors env-var hierarchy; leaves room for a second tier; nothing needs it yet | |

**User's choice:** Fields directly
**Notes:** —

## Blank-vs-malformed edge

| Option | Description | Selected |
|--------|-------------|----------|
| Loud (partial ⇒ fail) | Half-filled section signals intent to enable; silent disable is the forbidden failure; error names the missing field | ✓ |
| Disabled + warn | Engage only when all required fields non-blank; lenient but a typo'd empty bucket silently runs without cold storage | |

**User's choice:** Loud (recommended)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Reject loud (unknown keys) | Catches `acess_key` typos at startup instead of auth failures at first drain (Phase 8+) | ✓ |
| Ignore silently | Forward-compat with newer node versions; typo'd credential keys fall through to env/no-auth paths | |

**User's choice:** Reject loud (rec.)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Legacy lenient (file parse) | Warn+defaults for backup keys; blockstore treated absent ⇒ disabled; byte-identical bar holds for existing deployments | ✓ |
| Loud for whole file | Stronger operator signal; changes existing behavior for backup keys beyond the blockstore contract | |

**User's choice:** Legacy lenient (rec.)
**Notes:** —

## Env override surface

| Option | Description | Selected |
|--------|-------------|----------|
| Credentials only | Just SGNS_BLOCKSTORE_S3_ACCESS_KEY/_SECRET_KEY (INTG-02 letter); config file sole source for endpoint/bucket/tls/prefix; smallest test matrix | ✓ |
| Full surface | SGNS_BLOCKSTORE_S3_ENDPOINT/_BUCKET/_PREFIX/... too; env-only deployments; bigger precedence×tri-state matrix | |

**User's choice:** Credentials only (rec.)
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Env never activates | Config section is the only switch; blank/absent stays disabled regardless of environment; SC2 byte-identical bar airtight | ✓ |
| Env-only activation | Container-friendly; stray exported env var silently changes node behavior; byte-identical claim needs environment caveat | |

**User's choice:** Env never activates (rec.)
**Notes:** —

## M3 backup posture

| Option | Description | Selected |
|--------|-------------|----------|
| Journal rebuildable | Re-drain pending; CID-verified rebuild-from-remote-listing closes gaps; tooling Phase 11; createOnly idempotency + S3 as system of record; zero backup-engine surface | ✓ |
| Co-schedule backup | New separate loop mirrors cold dir on the backup schedule (new config keys); more moving parts; still no cross-DB atomicity — divergence window shrinks, never closes | |

**User's choice:** Journal rebuildable (rec.)
**Notes:** Dangerous direction identified: journal older than restored GlobalDB ⇒ blocks never marked for upload ⇒ silent cold-store gap. Rebuildable posture covers exactly this via the remote-listing diff.

| Option | Description | Selected |
|--------|-------------|----------|
| Architecture doc | M3 decision + rebuild semantics in supergenius-sharded-ipld-cache-architecture.md ops/runbook section, cited from 07-CONTEXT.md; no Phase 7 code | ✓ |
| CONTEXT only for now | Record in 07-CONTEXT.md; write operator-facing runbook when tooling lands in Phase 11 | |

**User's choice:** Architecture doc (rec.)
**Notes:** —

## The Agent's Discretion

- CMake mechanics inside the consumption block (hint names, ordering details) — AsyncIOManager precedent
- How SGNS_COLD_STORAGE gates compilation (conditional sources vs preprocessor guards)
- Where the loud failure surfaces (GeniusNode init vs GlobalDB::New propagation)
- ColdStorageOptions struct shape and GlobalDB::New threading mechanics
- Tier-1 test registration mechanics (target location, addtest(), label/audit wiring)
- Error-message wording (constraint: name the missing field / unknown key)
- Wallet-asset parity shape (omit section vs ship `"blockstore": {}`)
- Optional-field defaults (path_style/tls)

## Deferred Ideas

- M3 rebuild tooling → Phase 11
- Mobile superbuild legs → Future requirement (option OFF on mobile until verified)
- Full env surface / env-only activation → rejected (D-07/D-08), not deferred
- Vulkan capability-probe todo — matched by keywords only; ruled unrelated in Phase 6; stays backlog
