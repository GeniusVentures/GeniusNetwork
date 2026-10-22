# Phase 1: BlockStore Contract, Memory Backend & Conformance Kit - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-20
**Phase:** 1-BlockStore Contract, Memory Backend & Conformance Kit
**Areas discussed:** Result-type mechanics, CID type surface, Conformance kit shape, v1 contract breadth

---

## Todo cross-reference

| Option | Description | Selected |
|--------|-------------|----------|
| No — unrelated (recommended) | Vulkan-deadlock todo stays with base SuperGenius project planning | ✓ |
| Yes, fold it in | Pull the fix into Phase 1 scope | |

**User's choice:** No — unrelated
**Notes:** Matched on generic keywords only ("supergenius, cpp", score 0.6). Recorded as Reviewed Todo (not folded) in CONTEXT.md.

## Result-type mechanics

### Q1: Result carrier

| Option | Description | Selected |
|--------|-------------|----------|
| outcome envelope | `outcome::result<T, BlockStatus>` — repo convention; outcome ships with libp2p if C1 lands on p2p_cid | ✓ |
| Dedicated structs | `GetBlockResult`/`PutResult` variant structs — S5 style, handles AlreadyExists-as-success naturally | |
| Hybrid | outcome internally, structs at the public boundary | |

**User's choice:** outcome envelope

### Q2: BlockStatus shape

| Option | Description | Selected |
|--------|-------------|----------|
| Rich status struct | `{ StatusClass code; BlockSource source; std::string message; }` in the failure slot; attribution first-class | ✓ |
| Enum + detail | Bare enum; attribution in a separate bundled StatusDetail | |
| Bare enum | Attribution to logs only — rejected by success criterion 3 | |

**User's choice:** Rich status struct

### Q3: Miss encoding on Get

| Option | Description | Selected |
|--------|-------------|----------|
| NotFound=failure | Miss is a failure value with `code==NotFound`; uniform pattern for all five classes | ✓ |
| optional success | `result<std::optional<Block>, ...>`; miss = success + nullopt | |

**User's choice:** NotFound=failure

### Q4: Put success payload

| Option | Description | Selected |
|--------|-------------|----------|
| PutOutcome struct | `{ DurabilityLevel achieved; bool alreadyPresent; }` — Phase 4's 412 handling needs no re-freeze | ✓ |
| DurabilityLevel only | Re-put indistinguishable from fresh write | |
| void result | Durability via separate query — weakens the unverified-level invariant | |

**User's choice:** PutOutcome struct

## CID type surface

### Q1: Public CID type

| Option | Description | Selected |
|--------|-------------|----------|
| Direct alias | `using Cid = libp2p::multi::ContentIdentifier;` — zero conversion friction for SuperGenius call sites | ✓ |
| Thin wrapper | Library-owned struct wrapping bytes — decouples from libp2p, pays conversion everywhere | |
| Bytes-only API | CID type internal only — loses type safety | |

**User's choice:** Direct alias

### Q2: Spike acceptance bar

| Option | Description | Selected |
|--------|-------------|----------|
| Full 3-part bar | v0+v1 round-trip + CidOf vs known vectors + standalone TU linking only p2p_cid | ✓ |
| Round-trip only | Header/link-footprint check rides normal CI guard | |
| Researcher defines | Leave bar to --research-phase | |

**User's choice:** Full 3-part bar

### Q3: CidOf placement

| Option | Description | Selected |
|--------|-------------|----------|
| Public helper | Installed header; one verified CID constructor for all consumers | ✓ |
| Internal only | API accepts pre-built Cids only | |

**User's choice:** Public helper

### Q4: CID space breadth

| Option | Description | Selected |
|--------|-------------|----------|
| sha-256 only | Any codec; other hash codes rejected at API entry as invalid argument; taxonomy untouched | ✓ |
| Any multihash | Hash-code dispatch; larger test surface and spike scope | |

**User's choice:** sha-256 only

## Conformance kit shape

### Q1: Instantiation mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Header+macro | One macro `SGNS_BLOCKSTORE_CONFORMANCE_TESTS(SuiteName, factory)`; compiles into each backend's test binary | ✓ |
| Param'd suite | GTest value-parameterized over registered factories | |
| Compiled kit lib | Prebuilt library linked per backend — fastest builds, more than one step | |

**User's choice:** Header+macro

### Q2: Fault-injection seam

| Option | Description | Selected |
|--------|-------------|----------|
| Standardize now | Optional FaultController probed at instantiation; fault tests free for implementers; loud skips otherwise | ✓ |
| Ad hoc, defer seam | Phase-1 kit covers happy path; seam designed in Phase 5 | |

**User's choice:** Standardize now

### Q3: Kit assertions

| Option | Description | Selected |
|--------|-------------|----------|
| Own mini-macros | Kit-internal EXPECT_OUTCOME equivalents | |
| Plain GTest | EXPECT_TRUE/manual extraction; zero macro surface | ✓ |
| Callback asserts | Instantiating TU provides assert callbacks | |

**User's choice:** Plain GTest

### Q4: Kit install story

| Option | Description | Selected |
|--------|-------------|----------|
| Build-time only | TESTING=ON, in-repo; revisit on external demand | ✓ |
| Install + export | Consumers instantiate immediately; commits to kit API stability | |

**User's choice:** Build-time only

## v1 contract breadth

### Q1: Freeze width

| Option | Description | Selected |
|--------|-------------|----------|
| Full P1 freeze | Ops + PutMany + options + capabilities + 4-value DurabilityLevel all in v1.0.0 | ✓ |
| Lean core | Core ops + taxonomy only; options deferred — risks the retrofit this phase prevents | |

**User's choice:** Full P1 freeze

### Q2: PutMany semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Per-block outcomes | Result vector; no all-or-nothing guarantee; naive loop conformant | ✓ |
| All-or-nothing | No S3 backend could honor it — paints Phase 4 into a corner | |
| Drop PutMany | Callers loop themselves | |

**User's choice:** Per-block outcomes

### Q3: Options fields

| Option | Description | Selected |
|--------|-------------|----------|
| Deadline + verify | `ReadOptions{deadline; verify=true}`, `WriteOptions{deadline}`; nothing speculative | ✓ |
| Rich options | Retry hints, per-attempt budgets — encodes policy guesses early | |
| Empty placeholders | Struct growth later = ABI break for exported types | |

**User's choice:** Deadline + verify

### Q4: EvictLocal placement

| Option | Description | Selected |
|--------|-------------|----------|
| On backends only | Concrete method on MemoryBlockStore (Phase 2: LocalBlockStore); never on the interface; guard test binds both facts | ✓ |
| Defer entirely | Criterion 5's "EvictLocal is local-only" clause would have nothing to bind to | |

**User's choice:** On backends only

---

## the agent's Discretion

- Enum member naming (`StatusClass`, `BlockSource`), header file layout, guard-test mechanics (compile-time vs CI grep), MemoryBlockStore internals/thread-safety, capabilities field set beyond max-DurabilityLevel, repo bootstrap details within the AsyncIOManager precedent.

## Deferred Ideas

None — discussion stayed within phase scope. (Vulkan-deadlock todo recorded as Reviewed, not folded.)
