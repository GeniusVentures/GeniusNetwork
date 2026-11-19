---
phase: 17-seal-growth-measurement-decision
reviewed: 2026-11-19T00:00:00Z
depth: deep
files_reviewed: 3
files_reviewed_list:
  - SuperGenius/test/src/crdt/cold_seal_growth_test.cpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp
diff_base: 741980f5d (SuperGenius, branch dev_coldstorage_additions)
findings:
  critical: 0
  major: 2
  minor: 7
  info: 5
  total: 14
status: issues_found
---

# Phase 17: Code Review Report

**Reviewed:** 2026-11-19
**Depth:** deep (full-file + cross-file against vendored/production surfaces)
**Scope:** SuperGenius submodule, anchor `741980f5d` → HEAD (`84d87d462`), commits `0284d75c7`, `4f0ff1731`, `a93305eac`, `f6c9535f2`, `84d87d462`, `f758356fe`
**Files:** 3 (+1605 / −8)
**Status:** issues_found

## Summary

The seal-growth probe harness is well-constructed: the GATE-03/D-C1 discipline holds under grep-level and read-level verification, the vendored surfaces it relies on (`RocksdbDatastore::seal` — `<cid>+"sealed"` empty-value key, overwrite-idempotent; `PruneEligibility::WritePrunedBlockEntryForTest`/`LookupPrunedBlockEntry`) match the call shapes exactly, and the CMake registration is byte-for-byte idiom parity with the sibling `cold_compose_matrix_test` block. The `cold_compose_matrix_test.cpp` stability fix is **verified correct against production code**: `ColdStorageManager.cpp:1095` shows the GC's mark-time durability gate reads `local_block_store_->GetUploadState()` directly, bypassing the `GlobalDB::GetColdUploadState` hook — so the removed R3(a) assertions were genuinely timing-shaped, and the re-scoped half (erase defers `COLD_NOT_DURABLE` via the hooked guard at `globaldb.cpp:1679`; value row survives) is mechanically guaranteed.

Two Major findings concern the harness's own reliability as a measurement instrument: the dev-gated big leg bricks itself after any completed or interrupted run (hard equality assert vs. a by-design persistent root), and no enumeration pass ever checks the RocksDB iterator status, leaving a silent-evidence-corruption path in the variance stats.

**Production code:** `SuperGenius/src` has ZERO diff vs. the anchor (verified via `git diff --stat`) — the phase's production-touch prohibition holds.

## Phase-Invariant Verification (harness source, read-level)

| # | Invariant | Verdict | Evidence |
|---|-----------|---------|----------|
| a | Seal-suffix literal only in enumeration suffix comparison; no `+= "sealed"` key construction | **HOLDS** | `"sealed"` appears at exactly lines 449 and 541, both inside `k.compare(k.size()-6, 6, "sealed")` suffix checks; all other occurrences are prose comments. Seeding goes exclusively through vendored `RocksdbDatastore::seal()` (the only place the suffix is appended — `thirdparty/ipfs-lite-cpp/ipfs_lite/ipfs/impl/datastore_rocksdb.cpp:48`). |
| b | No deletion/compaction calls | **HOLDS** | Zero matches for `DeleteRange\|CompactRange\|removeSeal\|->Delete`. Only `std::filesystem::remove_all` on fixture roots (setup posture). |
| c | `/prune/blk` I/O only via PruneEligibility helpers | **HOLDS** | `/prune` appears only in comments (lines 1118, 1122, 1259); code paths are `WritePrunedBlockEntryForTest` (line 1216) / `LookupPrunedBlockEntry` (line 1241), signatures verified at `src/transaction/PruneEligibility.hpp:530,573`. |
| d | Floor root wiped per run; grow root NEVER wiped by code | **HOLDS** | `BuildMinimalStack(kFloorRoot, /*wipe=*/true)` (line 728); grow root: `create_directories` only (line 723), `BuildMinimalStack(kGrowRoot, /*wipe=*/false)` (lines 1329, 1514), plus before/after listing comparison (lines 723–731 vs 875–882). Fidelity/density/twin/keypair roots wiped per run as documented. |
| e | Env knobs integer-only | **HOLDS*** | All value knobs parse through `EnvOr` → `strtoull` → `uint64_t` (line 123). `SGNS_SEAL_BIG_ENABLE` is a documented presence-gate (`EnvSet`, line 140), consistent with the header's "Boolean env-gate companion" — but see MIN-01 on parse robustness. |

## Narrative Findings (AI reviewer)

## Critical Issues

None. No security vulnerabilities, no production-code changes, no data-loss paths in the reviewed scope.

## Major Issues

### MAJ-01: Big leg self-bricks after any completed or interrupted run — hard equality assert vs. by-design persistent root

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:1391`
**Issue:** The grow root is persistent and never wiped by code (invariant d — correct), but the 10^6 scale point asserts `ASSERT_EQ(pass.seals, scale)`. On any re-run of the gated leg after (i) a completed 10^7 run or (ii) an interrupted phase-2 (Ctrl-C at, say, 4×10^6 seals), `base_seals > scale`, phase 1 is skipped, and the assert fails immediately with the opaque message `"grow root 10^6 point count"`. The interrupted-resume posture the design implies ("persistent growing root", "the soak's resume posture") is contradicted by this assert: the leg is one-shot per root lifetime and gives the operator no diagnosis or recovery guidance (manual deletion of the root the code is forbidden to wipe). There is a non-obvious knob workaround (`SGNS_SEAL_SCALE=SGNS_SEAL_BIG_SCALE=10^7`) nothing documents.
**Fix:** Detect the state up front and handle it explicitly:

```cpp
if ( base_seals > scale )
{
    GTEST_SKIP() << "grow root already holds " << base_seals
                 << " seals (> SGNS_SEAL_SCALE=" << scale
                 << ") from a prior/interrupted big run; set SGNS_SEAL_SCALE="
                 << base_seals << " (and SGNS_SEAL_BIG_SCALE above it) to resume, "
                 "or manually remove " << kGrowRoot << " to restart growth";
}
```
(or equivalently, only assert equality when this run performed the phase-1 seeding, and record the actual count otherwise).

### MAJ-02: RocksDB iterator status never checked — silent evidence corruption path in the measurement instrument

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:445` (`ScanSealKeys`), `:536` (`RunEnumerationPass`)
**Issue:** Both enumeration loops exit on `!it->Valid()` without ever checking `it->status().ok()`. A mid-scan I/O error terminates iteration indistinguishably from end-of-data. The exact-count asserts catch *total* truncation in the floor/counting passes, but the warm/cold repeat passes whose rates feed `VarianceOver` and the evidence JSON (`leg.volume_10e6.enum_warm_*`, `leg.volume_10e7.*`) are never count-checked — a transient truncation inflates/deflates a recorded rate silently, which is precisely the failure mode a measurement harness must be immune to. `ScanSealKeys` has the same hole feeding the byte-identity comparison.
**Fix:**

```cpp
for ( it->SeekToFirst(); it->Valid(); it->Next() ) { /* ... */ }
ASSERT_TRUE( it->status().ok() ) << "enumeration I/O error: " << it->status().ToString();
```
(and the equivalent check in `ScanSealKeys`; for the helper called outside a TEST body, return a `std::optional<EnumPass>`/flag the callers assert on).

## Minor Issues

### MIN-01: `EnvOr` accepts negative and garbage input — hostile/mistyped knob can hang the ungated Tier-1 lane

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:123-128`
**Issue:** `std::strtoull(raw, nullptr, 10)` with no `endptr`/`errno` validation: `SGNS_SEAL_SCALE=-1` wraps to `18446744073709551615` and passes `ASSERT_GT(scale, 0)`, sending the **ungated** floor leg into a ~1.8×10^19-iteration seeding loop (lane hang / disk fill). `"10abc"` silently parses as `10`. The knobs are dev-facing, but the floor leg is a first-class Tier-1 citizen (D-07); the fail-closed posture should extend to knob parsing.
**Fix:** Validate full-string consumption and reject sign characters:

```cpp
uint64_t EnvOr( const char *name, uint64_t fallback )
{
    const char *raw = std::getenv( name );
    if ( raw == nullptr || *raw == '\0' ) return fallback;
    char *end    = nullptr;
    errno         = 0;
    unsigned long long v = std::strtoull( raw, &end, 10 );
    if ( errno != 0 || end == raw || *end != '\0' )
        return fallback; // or ADD_FAILURE() - a mistyped knob should be loud
    return static_cast<uint64_t>( v );
}
```

### MIN-02: Teardown-on-failure gap in Fidelity/Density legs — early ASSERT return leaks a live pubsub host + GlobalDB threads

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:1066`, `:1278` (also `BuildGlobalDbStack` early-returns at `:305-320`)
**Issue:** `TeardownGlobalDbStack(stack)` is the last statement of both TESTs and runs only on the success path. Any `ASSERT_*` failure between `BuildGlobalDbStack` and the end (Put failure, DAG-job timeout, walk timeout, marker write failure, ofstream failure) returns early, leaving the GossipPubSub host running and the GlobalDB un-shut-down for the remainder of the binary — a cascade-flake vector of exactly the class the phase-16 M3/R3 fix just diagnosed in this workstream. The explicit teardown ordering exists precisely because destructor-order teardown is unsafe here.
**Fix:** Wrap teardown in a scope guard so it runs on all exits:

```cpp
auto teardown = gsl::finally( [&stack] { TeardownGlobalDbStack( stack ); } );
```
(or convert to a gtest fixture with `TearDown()`).

### MIN-03: Evidence JSON written inside the live RocksDB DB directory — including the never-wiped grow root

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:862`, `:1060`, `:1272`, `:1536`
**Issue:** All four evidence files are written INTO the RocksDB database directories (`<kFloorRoot>/evidence-floor.json`, etc.). For the wiped-per-run roots this is merely unconventional; for `kGrowRoot` (line 1536) the stray `evidence-big.json` persists inside the measured store's directory across runs. RocksDB currently ignores unknown file extensions on open, but this couples evidence emission to DB-internal directory expectations and means the big leg *does* write a file into the root the floor leg's untouched-assertion treats as sacrosanct (different legs, so no assert fires — but the design claim "grow root NEVER touched by code" holds only for the floor leg as literally scoped).
**Fix:** Write evidence beside, not inside, the DB root — e.g. `std::filesystem::path(kGrowRoot) + "-evidence/evidence-big.json"`, or a CWD-relative evidence directory.

### MIN-04: `scale == 1` leaves `last_cid` empty in the floor fingerprint

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:753-757`
**Issue:** `if (i == 0) ... else if (i == scale - 1) ...` — when `SGNS_SEAL_SCALE=1` the single index takes the first branch and `last_cid` stays empty, producing `meta.dataset_fingerprint = "...;first=<cid>;last="` in the evidence.
**Fix:** Use two independent `if`s (the Big leg's phase-1 already uses this shape):

```cpp
if ( i == 0 )          { first_cid = cid.toString().value(); }
if ( i == scale - 1 )  { last_cid  = cid.toString().value(); }
```

### MIN-05: Density leg skips the knob validation the Fidelity leg enforces

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:1128-1132` vs `:905-909`
**Issue:** Fidelity asserts `ASSERT_GE(depth,2)`, `ASSERT_GE(fanout,1)`, `ASSERT_LE(mix_pct,100)`; Density reads the same knobs with no validation, so out-of-range values (e.g. `SGNS_SEAL_MIX=200` → mixed `chain_len = depth*2`) silently produce degenerate fixtures whose density numbers land in the evidence with no marker that knobs were out of design range.
**Fix:** Mirror the three asserts at the top of `Density.PruneBlockBackReferenceSpectrum`.

### MIN-06: Grow-root listing snapshot swallows `directory_iterator` error codes — untouched assert can pass vacuously

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:724-731`, `:875-882`
**Issue:** Both listing loops pass an `std::error_code` (`lec`) that is never checked. If the directory enumeration fails (permissions, transient FS error), both `grow_before` and `grow_after` come back empty and `ASSERT_EQ(grow_after, grow_before)` passes without having verified anything — a vacuous invariant check.
**Fix:** `ASSERT_FALSE(lec)` after each enumeration loop (or use the throwing overload inside the already-fatal test body).

### MIN-07: `BuildMinimalStack` re-implements `PrepareDir` inline

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:475-482` vs `:213-222`
**Issue:** The wipe/create preamble (`remove_all` + `create_directories` with error codes) duplicates the `PrepareDir` helper the same file defines for exactly this purpose. Divergence risk if the setup posture ever changes (e.g. error handling).
**Fix:** Call `PrepareDir(dir, wipe);` at the top of `BuildMinimalStack`.

## Info

### INFO-01: Unused include `<boost/filesystem.hpp>`

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:74`
**Issue:** Zero `boost::filesystem` usages — the file uses `std::filesystem` throughout. (Sibling suites carry the same include as transitive-include insurance, but in this TU it is dead.)
**Fix:** Drop the include, or keep with a comment if deliberate transitive insurance.

### INFO-02: Magic suffix length `6` duplicated at both scan sites

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:449`, `:541`
**Issue:** `k.size() > 6 && k.compare(k.size() - 6, 6, "sealed")` repeats the literal length twice per site, four times total. A mismatched edit would silently mis-scan.
**Fix:** `constexpr size_t kSealSuffixLen = 6;` beside the comparison (or `constexpr char kSealSuffix[] = "sealed";` + `sizeof - 1`).

### INFO-03: Stale `[[maybe_unused]]` on `EnvSet`

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:140`
**Issue:** The attribute was for the 17-01 interim state; `EnvSet` is now used by the Big leg, so the attribute is dead weight that invites confusion.
**Fix:** Remove `[[maybe_unused]]`.

### INFO-04: Big-leg evidence records the knob, not the measurement, under `leg.volume_10e6.seal_rows`

**File:** `SuperGenius/test/src/crdt/cold_seal_growth_test.cpp:1495` (approx. — `json.Add("leg.volume_10e6.seal_rows", static_cast<uint64_t>(scale))`)
**Issue:** The floor leg's evidence file records the measured `passes.front().seals` under the same key; the big leg records the `scale` knob. Cross-file consumers comparing the two JSONs get subtly different semantics for the identical key.
**Fix:** Record the measured count at the 10^6 point (the value already asserted) instead of the knob.

### INFO-05: R3(a) variant header comment still asserts the disproven "visible to BOTH readers" premise

**File:** `SuperGenius/test/src/crdt/cold_compose_matrix_test.cpp:2493-2495`
**Issue:** The in-body PRAGMATIC RE-SCOPE comment (verified accurate against `ColdStorageManager.cpp:1095`) correctly states the flip is NOT mechanically visible to the GC's mark-time read; but the variant's header comment above still reads "the flip is VISIBLE TO BOTH readers (before GC's gate read) - nothing destructive happens at all." A future reader gets two contradictory claims about the same leg.
**Fix:** Update the variant header to: "Variant (a): the flip is visible to the ERASE's guard read (the hooked GetColdUploadState); the GC's mark-time gate reads the journal directly and is unaffected — see the in-body PRAGMATIC RE-SCOPE note."

## Verified-Sound (no finding)

- **M3 fire budget 4→32** (`cold_compose_matrix_test.cpp:2020-2040`): fires are per-eviction; terminal detection via `IsColdDisposed` while parked is sound (the marker is written in half 1). Even the theoretical race — the overlap's eviction slipping a re-arm gap and a *later* eviction parking — still satisfies the asserted end state (journal already deleted → erase still defers `COLD_NOT_DURABLE`; disposed-not-erased holds). Correct de-flaking with no loss of mechanical guarantee.
- **R3(a) re-scope assertions**: guard 5 reads through the hooked `GetColdUploadState` (`globaldb.cpp:1679`) → `COLD_NOT_DURABLE` defer is hook-deterministic; the value row survives because the deferred erase stages nothing. Mechanically guaranteed.
- **Vendored `seal()` semantics** match every harness assumption: `<cid>+"sealed"` key, empty value, `put()` (overwrite-idempotent — safe for Big-leg re-seeding of identical content).
- **CMake registration**: inside `if(SGNS_COLD_STORAGE)`, `addtest()` + link set + whole-archive triad + `LABELS "Tier1"` are byte-for-byte parity with the `cold_compose_matrix_test` block in the same file.
- **Exact-count floor contract** (`seals == N, others == 0`) is sound on the freshly-wiped floor root; the suffix-scan false-positive class (non-seal keys ending in "sealed") is correctly confined to legs where it's asserted away by exact counts.
- **Derived floors** (rows/sec ≥ 480,000 = measured-mean/10 rounded down; per-row band [46, 60] = 52 ± 8 clamped to the A1 envelope) match the documented derivation math.

---

_Reviewed: 2026-11-19_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: deep_
