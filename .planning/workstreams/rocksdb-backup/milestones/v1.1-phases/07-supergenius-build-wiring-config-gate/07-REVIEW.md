---
phase: 07-supergenius-build-wiring-config-gate
reviewed: 2026-10-23T00:00:00Z
depth: deep
files_reviewed: 13
files_reviewed_list:
  - SuperGenius/build/CommonBuildParameters.cmake
  - SuperGenius/src/crdt/globaldb/globaldb.hpp
  - SuperGenius/src/crdt/globaldb/globaldb.cpp
  - SuperGenius/src/account/GeniusNode.hpp
  - SuperGenius/src/account/GeniusNode.cpp
  - SuperGenius/test/src/crdt/cold_storage_link_proof_test.cpp
  - SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp
  - SuperGenius/test/src/crdt/CMakeLists.txt
  - SuperGenius/.github/workflows/cmake.yml
  - GeniusSDK/cmake/CommonBuildParameters.cmake
  - GeniusWallet/lib/settings/settings_screen.dart
  - GeniusWallet/assets/crdt_config.json
  - supergenius-sharded-ipld-cache-architecture.md
commits:
  supergenius: "9f20ad184..12c39bc94 (07-01); 5c97e220e, d6fe9cce8 (07-02); 2703a75fe, f4e9ee31c (07-03)"
  geniussdk: "1a4e322"
  geniuswallet: "6b5c475b"
findings:
  critical: 2
  warning: 2
  info: 2
  total: 6
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-10-23
**Depth:** deep (per-file + cross-file: ctor ordering/unwinding, Dart load→edit→save round-trip, CI step graph)
**Files Reviewed:** 13
**Status:** issues_found

## Summary

The core contract work is largely sound: the tri-state parser implements D-03..D-06 in the correct order with errors that name offenders and never format credential values; the env surface is exactly two `getenv` sites with value-override-only semantics and a file-intent gate that precedes env resolution; both CMake blocks are correctly gated, version-free, and placed outside the `PREFER_CONFIG` window (SDK block strictly before `find_package(SuperGenius CONFIG REQUIRED)` at `GeniusSDK/cmake/CommonBuildParameters.cmake:506`); the test matrix has outcome guards and message-content assertions; the M3 runbook matches D-09/D-10.

Two Critical defects were found, both at the *seams* the phase summary claims as verified:

1. The loud-failure throw in `LoadCrdtConfig` is the **first throw ever reachable after the ctor spawns the 4 io threads** — the unwind destroys joinable `std::thread`s and calls `std::terminate()`, losing the naming-the-offender message on Windows and bypassing `GeniusNode::New`'s nullptr contract.
2. The Dart whitelist filter protects the nested `blockstore` object but **silently disconnects all CRDT edits from the map that gets saved** — every edit (including blockstore-unrelated backup keys) is discarded while the UI reports "Saved ✅". Verified as a regression against the pre-phase code (`config: _crdtConfig` at HEAD~1).

## Critical Issues

### CR-01: Malformed `blockstore` config aborts the process via `std::terminate` — loud-failure contract defeated

**File:** `SuperGenius/src/account/GeniusNode.cpp:619` (throw), ctor wiring `:369-376`
**Issue:** The constructor spawns the io thread pool immediately before parsing config:

```cpp
// GeniusNode.cpp:369-376
// Initializes the thread pool for IO context
io_threads_.reserve( io_thread_count_ );
for ( unsigned i = 0; i < io_thread_count_; ++i )
{
    io_threads_.emplace_back( [ctx = io_] { ctx->run(); } );
}

LoadCrdtConfig();
```

`io_thread_count_` is never overridden and defaults to `DEFAULT_IO_THREADS = 4` (`GeniusNode.hpp:1597-1598`; only two references in the .cpp, both in the spawn loop). The new `throw std::runtime_error( cold_storage_result.error() )` at `GeniusNode.cpp:619` (confirmed new in commit `d6fe9cce8`) is therefore the **first throw reachable after the pool exists** — the pre-existing ctor throws (`:323` loggers, `:359` account, `:365` network) all fire *before* the loop.

When the throw propagates, `GeniusNode`'s destructor does not run; member destructors run in reverse declaration order. `io_threads_` (`std::vector<std::thread>`, `GeniusNode.hpp:1599`) is destroyed while `io_work_guard_` (`GeniusNode.hpp:1046`, declared earlier → destroyed later) still holds work, so all 4 threads are still blocked inside `io_context::run()` — destroying joinable `std::thread`s calls `std::terminate()` **deterministically**.

Consequences:
- The abort happens *during unwinding*, before the `catch` clauses in `GeniusNode::New` (`GeniusNode.cpp:161-183`) run — the "GeniusNode initialization failed: <message>" line naming the missing field/unknown key is **never printed on Windows/MSVC** (glibc's default terminate handler would print `what()` before aborting). This violates D-04/D-05's "loud startup failure naming the missing field" and the 07-02 summary's own claim that the error "surfaces through the ctor throw path".
- SDK embedders (GeniusSDK consumers) get a hard process kill on a config typo instead of the documented nullptr-on-failure contract (INTF-01/D-04 at `GeniusNode.cpp:161`).

**Fix:** Move `LoadCrdtConfig()` before the thread-pool spawn — it depends only on `write_base_path_` and `node_logger_`, both initialized by that point:

```cpp
        node_logger_->debug( "Account Address {}", account_->GetAddress() );

        // Parse CRDT/cold-storage config BEFORE spawning the io pool: the
        // strict blockstore gate throws (D-04/D-05), and a throw after the
        // pool exists destroys joinable std::threads => std::terminate.
        LoadCrdtConfig();

        // Initializes the thread pool for IO context
        io_threads_.reserve( io_thread_count_ );
        for ( unsigned i = 0; i < io_thread_count_; ++i )
        {
            io_threads_.emplace_back( [ctx = io_] { ctx->run(); } );
        }
```

(Alternatively, catch inside `LoadCrdtConfig`, stop/join the pool, and rethrow — but reordering is the minimal, race-free fix.)

### CR-02: CRDT settings editor silently discards every user edit (whitelist copy disconnects the save path)

**File:** `GeniusWallet/lib/settings/settings_screen.dart:305-309` (filter), `:415`, `:431-434` (mutations), `:157` (save)
**Issue:** `_buildCrdtSection` passes a per-build **copy** to the table:

```dart
// settings_screen.dart:305-309
child: _configFieldsTable(
  config: Map.fromEntries(
    _crdtConfig.entries.where((e) => crdtKeyLabels.containsKey(e.key)),
  ),
  ...
```

`_configFieldsTable` writes edits into whatever map it received (`config[entry.key] = v` at `:415`; `= parsed` at `:431`; `= v` at `:434`), but `_saveCrdtConfig` persists `_crdtConfig` (`settings_screen.dart:157`), which is never mutated. Net effect:

- Toggling `Backup Enabled` flips back on the next frame (each `build()` re-derives the copy from the untouched `_crdtConfig`).
- Typed interval/keep-count values never persist.
- The UI still shows "Saved ✅ — Restart required for changes" — silent loss of user input with a false success signal.

This is a **regression introduced by this phase**: `git show HEAD~1:lib/settings/settings_screen.dart` shows the pre-commit code passed `config: _crdtConfig` directly (the Network section still does, at `:267`, which is why Network editing still works). The summary's stated goal — "the FULL config (incl. nested blockstore) still round-trips through save untouched" — is met for `blockstore`, but the section's actual purpose (editing the four backup keys) is broken.

**Fix:** Filter *rendering*, not the mutated map. Add a `renderKeys` parameter to `_configFieldsTable` so the row builder iterates only whitelisted keys while edits write through to `_crdtConfig`:

```dart
child: _configFieldsTable(
  config: _crdtConfig,            // direct reference: edits persist
  renderKeys: crdtKeyLabels.keys.toSet(),
  keyLabels: crdtKeyLabels,
  ...
),

// inside _configFieldsTable:
children: config.entries
    .where((e) => renderKeys.contains(e.key))   // blockstore never rendered/stringified
    .map((entry) { ... }).toList(),
```

(Do **not** fix by filtering at load time as the Network section does — `_loadNetworkConfig` pattern at `:130-136` — because `_saveCrdtConfig` writes the whole state map to the overrides file; load-time filtering would strip `blockstore` from the saved override and silently disable cold storage for configured deployments.)

## Warnings

### WR-01: Flagship D-07 scenario untested — credentials ONLY from env with file endpoint/bucket

**File:** `SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp:145-191` (env case block)
**Issue:** The three env cases cover override-wins (`EnvCredentialsSatisfyWhenIntentExists`, `:145`), never-activates (`EnvNeverActivates`, `:161`), and empty-is-unset (`EnvEmptyStringIsUnset`, `:175`). The deployment shape the new runbook explicitly recommends (`supergenius-sharded-ipld-cache-architecture.md:571-575`: source credentials from env rather than the file) — file has `endpoint`+`bucket`, `access_key`/`secret_key` blank or absent, env supplies both — has **no case**. The 07-CONTEXT "Specific Ideas" flags exactly this composition as "not independently user-confirmed; follows necessarily from the locked letters" — the matrix was the place to pin it. It traces correctly through the parser today (`any_required_in_file` is true via endpoint at `globaldb.cpp:198-203`; resolved credentials come from env at `:208-209`), so this is a coverage gap, not a behavior bug — but a future regression (e.g., someone requiring file credentials) would pass all 15 current cases.

**Fix:**
```cpp
TEST( ColdStorageConfigGate, EnvCredentialsSoleSourceWithFileEndpointBucket )
{
    // Runbook shape: secrets live ONLY in env; file carries endpoint+bucket.
    ColdStorageEnvLookup env;
    env.access_key = "env-access";
    env.secret_key = "env-secret";
    auto result = Parse( R"({"blockstore": {"endpoint": "10.0.0.1", "bucket": "b1"}})", env );
    ASSERT_FALSE( result.has_error() );
    EXPECT_TRUE( result.value().enabled );
    EXPECT_EQ( result.value().accessKey, std::string( "env-access" ) );
    EXPECT_EQ( result.value().secretKey, std::string( "env-secret" ) );
}
```

### WR-02: Tier-1 CI lane can never run while the full-suite step fails — fail-closed lane is masked

**File:** `SuperGenius/.github/workflows/cmake.yml:608-614`, `:692-698`
**Issue:** Both "Tier-1 fail-closed lane" steps run immediately after the full-suite "Run tests" steps in the same job with default step gating (no `if: always()`). GitHub Actions skips subsequent steps when a prior step fails, so any full-suite failure prevents the Tier-1 lane from executing at all. This is not hypothetical: 07-02 documents `globaldb_integration_test` failing deterministically (9/12 cases, pre-existing libp2p/pubsub connection failures, stash-baseline-proven). With that on CI, the job fails at "Run tests" and the Tier-1 lane — including its `--no-tests=error` vacuous-pass protection, the very Pitfall-6/Pitfall-12 guarantee TEST-01 was anchored on — is dead code until the full suite goes green. The lane was added to be independent of the fail-open lane; step ordering re-couples them.

**Fix:** Make both Tier-1 steps run unconditionally after the suite starts:

```yaml
      - name: Tier-1 fail-closed lane
        if: ${{ always() && env.RUN_TESTS == 'true' && matrix.target != 'Linux' }}
        ...
      - name: Tier-1 fail-closed lane (Linux)
        if: ${{ always() && env.RUN_TESTS == 'true' && matrix.target == 'Linux' }}
        ...
```

## Info

### IN-01: Dead tracking variables in the parser

**File:** `SuperGenius/src/crdt/globaldb/globaldb.cpp:139-140`, `:183`, `:188`, `:192-193`
**Issue:** `has_path_style`/`has_tls` are assigned inside the member loop and then only `(void)`-cast — the explicit-vs-defaulted tracking was evidently planned and dropped. Dead stores that suggest semantics ("explicit" detection) which don't exist; a future maintainer may build on them.
**Fix:** Delete both variables, their assignments, and the two `(void)` casts; the `path_style`/`tls` locals plus their defaults already carry the behavior.

### IN-02: Case (c) — present-but-not-an-object — has no test

**File:** `SuperGenius/test/src/crdt/cold_storage_config_gate_test.cpp` (matrix gap)
**Issue:** The `"'blockstore' section must be an object"` error path (`globaldb.cpp:127-130`) — e.g. `"blockstore": null`, `"blockstore": "x"`, `"blockstore": []` — is the one tri-state branch with no covering case. One test asserting the message content (per the matrix's own content-assertion convention) completes the D-03..D-06 coverage.
**Fix:** `TEST(ColdStorageConfigGate, NonObjectSectionFailsLoud)` with `R"({"blockstore": null})"` asserting `has_error()` and `error().find("must be an object")`.

## Verified Clean (review-focus items with no finding)

- **Tri-state D-03..D-06:** parser order is (a) file-lenient → (b) absent → (c) not-an-object → (d) key/type pass → (e) file-intent gate **before** (f) env-then-required → (g) populate; empty object and optional-only sections disable (`globaldb.cpp:106-204`); whole-file corruption returns disabled, not an error (`:107-112`); partial fill names missing fields post-env (`:211-238`); unknown/wrong-typed keys name the key (`:152-160`). GeniusNode's file-missing and parse-error early returns remain verbatim and lenient (`GeniusNode.cpp:560-580`), and the throw precedes `InitDatabase()` (ctor `:376` vs `:756`).
- **Env D-07/D-08:** exactly two `getenv` sites (`globaldb.cpp:77-78`), both named `SGNS_BLOCKSTORE_S3_*`; env overrides values only; the file-intent gate (`:198-203`) guarantees env never activates; the required-field check runs after env resolution.
- **Credential redaction:** every `outcome::failure` string names keys/fields, never values; `LogSummary()` (`:90-95`) formats endpoint/bucket/prefix/path_style/tls only; the only new log line (`GeniusNode.cpp:625-629`) carries `LogSummary()` and fires only when enabled; the test matrix asserts credential absence in the summary (`cold_storage_config_gate_test.cpp:194-211`).
- **CMake gating:** all finds in the cold-storage chain sit inside `if(SGNS_COLD_STORAGE)` in both files; the option defaults OFF with mobile FORCE-off (`SuperGenius/build/CommonBuildParameters.cmake:415-417`, `GeniusSDK/cmake/CommonBuildParameters.cmake:336-338`); blocks sit after the `PREFER_CONFIG` window restore (`:404` / `:311`); no find carries a version argument (dual-RocksDB posture); SDK block precedes `find_package(SuperGenius CONFIG REQUIRED)` (`:506`).
- **Wallet asset:** `"blockstore": {}` parses as blank ⇒ disabled per D-03; the four backup keys are intact.
- **M3 runbook:** matches D-09/D-10 (rebuildable-not-backed-up, re-drain→CID-verified rebuild→re-journal order, Phase-11 tooling, env-credential guidance).
- **Test quality:** both test files guard outcomes before `.value()`/`.error()` and assert message content by name; link-proof test documents the field-subset mapping honestly (no invented `prefix` field).

---

_Reviewed: 2026-10-23_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: deep_
