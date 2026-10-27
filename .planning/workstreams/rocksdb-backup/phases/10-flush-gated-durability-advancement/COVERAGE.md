# API Coverage — s3d admin API (pinned v0.2.1)

> Full coverage by default. Opt-outs are explicit, reasoned decisions.
> Surface source: pinned-tag `openapi.yml` re-fetched live 2026-10-26 (10-RESEARCH §1);
> committed characterization `thirdparty/sgns-blockstore/docs/s3d-durability.md`.

Phase 10 integrates the s3d admin HTTP API — a separate always-enabled listener
(default `127.0.0.1:8001`) authenticated by HTTP Basic with a configured admin
password (username ignored), NOT the S3 SigV4 credentials (10-RESEARCH §1.1, D-06
verdict: separate). Integration seam: the `S3AdminClient` facade inside
sgns-blockstore (D-05), consumed by the Phase-8 drainer's flush cadence (D-02).

| capability | decision | reason |
|---|---|---|
| `POST /objects/flush` (`flushObjects`) | INTEGRATE | |
| `GET /stats/uploads` (`getUploadStats`) | INTEGRATE | |
| `GET /prometheus` | OPT-OUT | not needed — the JSON stats endpoint is the seam; no metrics surface ships in v1.1 (metrics surface is a Future requirement in REQUIREMENTS.md) |
| host/state endpoints (any other documented admin route at the pin) | OPT-OUT | explicitly out of scope — durability evidence needs only flush + upload stats; no Sia host telemetry is consumed by cold storage in v1.1 |

Binding factual notes carried into the plans:

- `POST /objects/flush` takes **no bucket parameter** — it is process-global at the
  pin ("Uploads all pending objects to Sia immediately … Blocks until done"). The
  ROADMAP SC1 "bucket-scoped" wording is an imprecision; 10-01 Task 2 corrects
  `docs/s3d-durability.md` §3. The acknowledged flush cost therefore covers every
  bucket's pending objects, and the `pendingObjects==0` evidence is process-wide.
- Per-object durability-signal polling remains milestone-wide out of scope
  (REQUIREMENTS.md Out of Scope; s3d v0.2.1 has no per-object signal) — fast-follow.
- Only 200 / 500 are documented for flush; every non-200, transport, timeout, and
  parse failure classifies `TemporarilyUnavailable`, never `NotFound` (D-07 posture).
