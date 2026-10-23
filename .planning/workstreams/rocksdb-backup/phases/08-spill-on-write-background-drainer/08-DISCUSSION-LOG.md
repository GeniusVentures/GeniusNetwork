# Phase 8: Spill-on-Write & Background Drainer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-23
**Phase:** 8-Spill-on-Write & Background Drainer
**Areas discussed:** Backpressure policy, Config knobs, Alarm surface, Drainer ownership

---

## Backpressure policy

### Journal growth policy

| Option | Description | Selected |
|--------|-------------|----------|
| Unbounded + alarm | Journal grows without bound during outage; dual watermarks fire alarm; writes never blocked, spill never skipped; disk is the pressure valve | ✓ |
| Bounded-degrade | Hard cap; at cap new blocks stop journaling (hot-only) with critical alarm; cold store falls behind until D-09-style rebuild | |
| Hybrid (opt-in cap) | Unbounded+alarm default; explicitly-configured hard cap opts disk-constrained operators into bounded-degrade | |

**User's choice:** Unbounded + alarm
**Notes:** SC1's "every Put journals" and SC4's "publishes never fail" both honored to the letter; bounded shapes rejected because cold-store gaps would lean correctness on Phase 10's durability gate.

### Watermark measurement

| Option | Description | Selected |
|--------|-------------|----------|
| Pending count (dual) | Warn + critical thresholds on pending-upload record count — the unit GetPendingUploads yields; byte accounting deferred to Future metrics | ✓ |
| Journal bytes | Thresholds on journal size in bytes; library doesn't expose byte accounting yet | |
| Count + bytes | Both; most honest, most surface | |

**User's choice:** Pending count (dual)

### Drainer retry cadence

| Option | Description | Selected |
|--------|-------------|----------|
| Exp backoff, capped | Consecutive-failure backoff (e.g. 1s → … → 60s cap), reset on first success | ✓ |
| Fixed cadence | Retry every N seconds regardless; hammers a down s3d continuously | |

**User's choice:** Exp backoff, capped

### Local journal-write failure

| Option | Description | Selected |
|--------|-------------|----------|
| Fail the publish | Hot-write + journal are one mandatory pair when cold storage is enabled; local disk failure is a node-down event; SC4 scoped to remote s3d state | ✓ |
| Best-effort + alarm | Publish succeeds; journal failure raises critical alarm; block enters needs-rebuild set (D-09 rebuild closes gap in Phase 11) | |

**User's choice:** Fail the publish
**Notes:** SC4's "never fail due to cold-store state" clarified as scoped to REMOTE s3d state; no silent cold gaps.

---

## Config knobs

### Knob scope

| Option | Description | Selected |
|--------|-------------|----------|
| No new knobs | All behavior compile-time constants; schema stays Phase 7's exactly | |
| Minimal ops set | Drain poll interval, backoff cap, warn/critical watermarks only; everything else constant until metrics evidence | ✓ |
| Full tunable set | Cadence, batch size, backoff floor/cap, watermarks, retry limits all configurable | |

**User's choice:** Minimal ops set

### Nesting shape

| Option | Description | Selected |
|--------|-------------|----------|
| Nested object | `blockstore.backpressure` sub-object; Phase 11 retention gets a sibling sub-object | ✓ |
| Flat under blockstore | Knobs directly beside S3 fields; matches D-02 flat-S3 precedent but grows unwieldy | |

**User's choice:** Nested object
**Notes:** Phase 7 D-01 anticipated backpressure knobs nesting under `blockstore`.

### Absent-knob semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Always-on defaults | Knobs optional; absent = documented built-in defaults; watermark alarm always active | ✓ |
| Opt-in alarm | No watermark config = no alarm | |

**User's choice:** Always-on defaults

---

## Alarm surface

### v1.1 manifestation

| Option | Description | Selected |
|--------|-------------|----------|
| Log-only | Rate-limited warn/critical via existing logger; zero new API; nothing programmatic | |
| Log + status getter | Logs plus queryable status getter (journal depth, watermark state, drainer health); Tier-1 assertable; GeniusSDK-consumable; Phase 10/11 GC-inhibitor consult point | ✓ |
| Log + status + summary | Status getter plus periodic info-level journal-depth line while unhealthy | |

**User's choice:** Log + status getter
**Notes:** Aligns with ROADMAP Phase 10 SC4's "monitored and exposed" posture; deliberately not a metrics framework (metrics are milestone-Future).

### Logging discipline

| Option | Description | Selected |
|--------|-------------|----------|
| Transition + heartbeat | Log each crossing (recovery included) plus rate-limited heartbeat while held | ✓ |
| Transition-only | Least noise; last alarm line goes stale in long outages | |

**User's choice:** Transition + heartbeat

---

## Drainer ownership

### Owner

| Option | Description | Selected |
|--------|-------------|----------|
| GlobalDB member | Mirrors backup loop; lifecycle tied to GlobalDB::New/Shutdown; teardown in one place; status getter rides active-accessor pattern; no factory global state | ✓ |
| CComponentFactory | SuperGenius norm; cross-component visibility; but global-state/init-order coupling against GlobalDB shutdown | |
| GeniusNode-owned | Constructed next to LoadCrdtConfig; but GlobalDB still needs a handle for the seam decorator — split lifecycle | |

**User's choice:** GlobalDB member

### Clean-shutdown semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Bounded wait, resume | Bounded grace window for in-flight work; leftovers resume at next startup via standard reconciliation; one resume code path | ✓ |
| Full blocking drain | Block until journal empty; unbounded shutdown latency during s3d outage | |

**User's choice:** Bounded wait, resume

### Crash-restart reconciliation timing

| Option | Description | Selected |
|--------|-------------|----------|
| Async, first poll | Drainer's first poll enumerates GetPendingUploads and re-drains as normal operation; no startup gate | ✓ |
| Sync enumerate gate | Startup blocks until enumeration (not drain) completes before ready | |

**User's choice:** Async, first poll

---

## the Agent's Discretion

- Built-in default values (drain interval, backoff floor/cap, watermarks, grace window, heartbeat period)
- Exact knob names inside `blockstore.backpressure`
- Status-getter signature shape and field set beyond the three minimums
- Decorator mechanics: atomic batch composition with the inner IpfsRocksDb write; journal-vs-inner ordering (subject to D-04 fail-loud)
- SC1 benchmark construction on the InMemoryS3Client fake
- Drainer thread-function placement; grace-window implementation
- Library hosting split: shipped UploadDrainer vs SuperGenius-side loop (researcher confirms)
- Tier-1 registration mechanics; ops-triggered drain enqueue surface (enqueue-never-inline constraint)
- Log wording (transition + heartbeat discipline)
- IpfsRocksDb block-key layout enumeration (phase-local research)

## Deferred Ideas

- Byte-based journal watermarks — milestone-Future metrics surface
- M3 needs-rebuild reconciliation tooling — Phase 11
- Metrics framework beyond the status getter — milestone-Future
- Bounded-degrade / opt-in hard cap — rejected in D-01, not deferred
- Vulkan-probe-deadlock todo — keyword-only match; standing unrelated ruling from Phases 6/7 carried forward
