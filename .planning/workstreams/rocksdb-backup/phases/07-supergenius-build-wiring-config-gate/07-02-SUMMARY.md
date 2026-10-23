---
phase: 07-supergenius-build-wiring-config-gate
plan: 02
subsystem: crdt
tags: [config, cold-storage, tri-state, env-override, globaldb, geniusnode]

requires:
  - phase: 07-supergenius-build-wiring-config-gate
    provides: SGNS_COLD_STORAGE build wiring (plan 01)
provides:
  - crdt::GlobalDB::ColdStorageOptions (D-02 locked field set) threaded through GlobalDB::New as a trailing defaulted parameter
  - ParseColdStorageConfig strict tri-state parser (D-03..D-06) with injectable env resolution (D-07/D-08)
  - DefaultColdStorageEnvLookup (exactly two getenv sites) + LogSummary (credential-free summary)
  - GeniusNode::LoadCrdtConfig loud throw path before InitDatabase + enabled-only info line
affects: [07-03 config-gate test matrix, Phase 8 spill, Phase 9 fallback, Phase 11 GC]

actuals:
  tokens: 21000
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Strict nested-section parser inside a lenient-at-file-level loader (D-06 boundary)"
    - "Injectable env-lookup struct (resolved values, not a process-env-coupled callable)"

key-files:
  created: []
  modified:
    - SuperGenius/src/crdt/globaldb/globaldb.hpp
    - SuperGenius/src/crdt/globaldb/globaldb.cpp
    - SuperGenius/src/account/GeniusNode.hpp
    - SuperGenius/src/account/GeniusNode.cpp

key-decisions:
  - "ParseColdStorageConfig delivered as an overload pair (production env-resolved single-arg + injectable two-arg) instead of the plan's literal '= {}' default - an empty default would have made the production path skip env entirely (D-07 violation)"
  - "ColdStorageEnvLookup is a resolved-values struct (access_key/secret_key members) built by DefaultColdStorageEnvLookup - keeps getenv to exactly two sites, both named, and makes test injection process-env-free"
  - "Parse errors carry dynamic std::string messages via outcome::result<ColdStorageOptions, std::string> - the existing GlobalDB::Error enum cannot name offending keys"

patterns-established:
  - "Tri-state strict parse order: (a) file-lenient -> (b) absent -> (c) not-an-object -> (d) key/type pass -> (e) file-intent gate BEFORE (f) env-then-required-check -> (g) populate"

requirements-completed: [INTG-02]

coverage:
  - id: D1
    description: "ColdStorageOptions + trailing-defaulted GlobalDB::New threading with zero behavioral change when disabled"
    requirement: INTG-02
    verification:
      - kind: unit
        ref: "tests: crdt_test green post-change (Windows/MSVC Debug)"
        status: pass
      - kind: other
        ref: "command: build crdt_globaldb + genius_node + crdt_test + globaldb_integration_test - all compiled"
        status: pass
    human_judgment: false
  - id: D2
    description: "Strict tri-state parser implementing (a)-(g) with key/field-naming errors and never-credential messages"
    requirement: INTG-02
    verification:
      - kind: other
        ref: "structural gates V1-V5 (env-name count=2, exactly two getenv sites, credential-log negative gate CLEAN, member assignment, GeniusNode wiring)"
        status: pass
      - kind: unit
        ref: "tests: behavioral matrix deferred to 07-03 cold_storage_config_gate_test by ROADMAP wave design (recorded, not silently dropped)"
        status: unknown
    human_judgment: false
  - id: D3
    description: "GeniusNode loud-failure surface: throw std::runtime_error from LoadCrdtConfig before InitDatabase; enabled-only LogSummary info line"
    requirement: INTG-02
    verification:
      - kind: other
        ref: "command: grep cold_storage_config_ in GeniusNode.cpp/:hpp - member + default init + parse/store/log/pass-through present"
        status: pass
    human_judgment: false

duration: 55 min
completed: 2026-10-23
status: complete
---

# Phase 7 Plan 02: Config Gate Core Summary

**Strict tri-state `blockstore` parser (absent/blank=disabled byte-identical, malformed=loud naming the offender, env=credential-value-override-only) threaded through `GlobalDB::New` as a trailing defaulted parameter — credentials never logged.**

## Performance

- **Duration:** ~55 min
- **Started/Completed:** 2026-10-23
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- `ColdStorageOptions` struct (D-02 locked fields, credential members documented never-logged) + `cold_storage_options_` member + trailing defaulted `New()` parameter — all 8 existing call sites compile unchanged
- `ParseColdStorageConfig` implements the exact (a)-(g) order: file-level leniency (D-06), absent/blank/optional-only disable (D-03), unknown-key/wrong-type errors naming the key (D-05), partial-fill errors naming missing fields AFTER env resolution (D-04 + derived composition)
- Env surface = exactly two getenv sites (`SGNS_BLOCKSTORE_S3_ACCESS_KEY`/`_SECRET_KEY`); env overrides values, never activates (D-07/D-08)
- `LogSummary()` formats endpoint/bucket/prefix/path_style/tls only; negative gate proves no log/throw string embeds credential fields
- `LoadCrdtConfig`: existing file-missing/parse-error early returns verbatim; blockstore parse appended with `std::runtime_error` throw (surfaces through the ctor throw path before any RocksDB work); one info line ONLY when enabled (Pitfall 9)

## Task Commits

1. **Task 1: struct + threading + disabled-default (tracer)** — SuperGenius `5c97e220e`, root `8509800` (feat/chore)
2. **Task 2: strict parser + env + loud failure** — SuperGenius `d6fe9cce8`, root `aef6551` (feat/chore)

**Plan metadata:** this commit (docs)

## Files Created/Modified
- `globaldb.hpp` — ColdStorageOptions (+LogSummary decl), ColdStorageEnvLookup, DefaultColdStorageEnvLookup, ParseColdStorageConfig overloads, ColdStorageParseResult alias, New() param
- `globaldb.cpp` — env lookup (2 getenv sites), parser (a)-(g), LogSummary, member assignment
- `GeniusNode.hpp` — cold_storage_config_ member
- `GeniusNode.cpp` — default init, strict parse + throw + enabled-only log, InitDatabase pass-through

## Decisions Made
- Overload pair instead of `= {}` default (see key-decisions)
- Resolved-values env struct (see key-decisions)
- `outcome::result<ColdStorageOptions, std::string>` for dynamic naming messages

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Pre-existing, out of scope] globaldb_integration_test connection failure**
- **Found during:** Task 1 test gate
- **Issue:** 9/12 cases fail with "GlobalDB test nodes did not connect" (GossipPubSub "Failed to get addresses from peer repository: not found")
- **Fix:** none (scope boundary) — proven PRE-EXISTING via stash baseline: with 07-02 edits stashed, rebuilt, the same case fails identically. crdt_test (same CRDT code, no cross-node dialing) is green with the change. Root cause is pubsub/libp2p connection establishment, untouched by this diff
- **Verification:** baseline run recorded in session; failure deterministic (single-case re-run fails identically)

**2. [Rule 3 - Blocking] Plan's literal `env_lookup = {}` default would skip env in production**
- **Found during:** Task 2 (signature design)
- **Issue:** a default-constructed empty lookup as the default argument means the single-arg production call never reads SGNS_BLOCKSTORE_S3_* (D-07 dead letter)
- **Fix:** overload pair — `ParseColdStorageConfig(text)` calls `DefaultColdStorageEnvLookup()`; injectable overload for tests
- **Verification:** getenv sites present and exercised by the single-arg path; 07-03 injects via the two-arg overload

**Total deviations:** 2 (1 pre-existing/environmental documented, 1 auto-fixed). **Impact:** none on the locked contract.

## Issues Encountered
- globaldb_integration_test pre-existing connection failure (see Deviation 1) — needs its own investigation (likely the libp2p loopback-dial/peer-repo issue also visible in the "Failed to get addresses" warnings); NOT caused by and NOT blocking this plan, but 07-03's Tier-1 lane (config-gate test) is unaffected by it by construction (no cross-node dialing).

## Self-Check: PASSED

- Task 1 acceptance: struct fields exact, trailing-default rule (only GeniusNode call-site edit), member+init+pass-through greps, no new node_logger_ call in Task-1 diff ✓
- Task 2 acceptance: (a)-(g) order incl. e-before-f; unknown-key/wrong-type name the key; partial-fill names fields post-env; top-level corruption returns disabled; exactly two getenv sites; LogSummary credential-free; throw wired before InitDatabase; early returns verbatim ✓
- Both test gates run: crdt_test green; globaldb_integration_test fails only in its pre-existing connection layer (stash-baseline evidence)
