# Phase 16: Manifest Evolution - Pattern Map

**Mapped:** 2026-08-17
**Files analyzed:** 5 (code) + 2 (docs, no pattern mapping needed — pure text edits)
**Analogs found:** 5 / 5 (all are self-analogs — this phase extends existing files, no new files created)

## Scope Note

Per CONTEXT.md/RESEARCH.md, this phase's actual code changes are all **modifications to existing files**, not new files. There are no "role/data-flow classification vs. separate analog" pairs in the usual sense — each file to be modified *is* its own closest analog: the existing code in the same file establishes the convention the new code must follow. Two additional files (`REQUIREMENTS.md`, `ROADMAP.md`) require documentation-only edits (ARTF-07/ARTF-08 "won't implement" wording) — not pattern-mapped since they're prose, not code.

## File Classification

| File to Modify | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SuperGenius/SGProcessingManager/include/artifacts/execution_manifest.hpp` | model (struct definition) | transform (in-memory data contract) | itself — existing field declarations in same struct | exact (self-analog) |
| `SuperGenius/SGProcessingManager/include/artifacts/artifact_serializer.hpp` | serializer/model (constants + signatures) | transform | itself — existing `MANIFEST_SERIALIZED_SIZE`/`ARTIFACT_SERIALIZED_SIZE` constants | exact (self-analog) |
| `SuperGenius/SGProcessingManager/src/artifacts/artifact_serializer.cpp` | service (serialize/deserialize) | transform (binary encode/decode) | itself — `SerializeArtifact`/`DeserializeArtifact` (same file, same pattern, one type over) | exact (self-analog) |
| `SuperGenius/SGProcessingManager/include/processingbase/ProcessingManager.hpp` | controller/orchestrator (class interface) | request-response | itself — existing `GetProgress()` accessor (lines 155-162) | exact (self-analog) |
| `SuperGenius/SGProcessingManager/src/processingbase/ProcessingManager.cpp` | controller/orchestrator (`ProcessInternal()`) | request-response / CRUD-like (build-and-store manifest) | itself — existing success-path manifest assembly block (lines 1442-1499) | exact (self-analog) |
| `SuperGenius/SGProcessingManager/test/artifacts/artifact_serializer_test.cpp` | test | request-response (round-trip assertions) | itself — `ManifestSerializeRoundTrip`/`ManifestDeterminism`/`ManifestZeroIdentityHashes` (lines 216-273) | exact (self-analog) |
| `.planning/workstreams/sgproc-render/REQUIREMENTS.md` | docs | — | Phase 13's own in-plan scope-correction precedent (per STATE.md) | role-match (process precedent, not code) |
| `.planning/workstreams/sgproc-render/ROADMAP.md` | docs | — | same Phase 13 precedent | role-match (process precedent, not code) |

## Pattern Assignments

### `execution_manifest.hpp` (model, transform) — add `errorMessage` field

**Analog:** itself (existing field block, lines 34-83)

**Struct field declaration pattern** (lines 38-42, 82):
```cpp
struct ExecutionManifest
{
    char executionId[MAX_IDENTIFIER];   ///< Execution-scoped ID
    ...
    // ── Manifest self-hash ─────────────────────────────────────────
    uint8_t manifestHash[SHA256_HASH_SIZE];
};
```
New field goes last in the struct (append-only, matches D-13/append-not-prepend decision):
```cpp
char errorMessage[MAX_IDENTIFIER];  ///< ARTF-09: ProcessingError::message, empty on Success; truncated silently if > MAX_IDENTIFIER-1 bytes (D-10)
```
Reuse existing `MAX_IDENTIFIER = 256` constant (line 22) — do not invent a new size constant (per RESEARCH.md's explicit recommendation).

---

### `artifact_serializer.hpp` (constants + signatures) — add v2 size constant

**Analog:** itself, `MANIFEST_SERIALIZED_SIZE` declaration (lines 30-35)

**Existing size-constant + doc-comment pattern:**
```cpp
/// Fixed total size of a serialized ExecutionManifest in bytes.
///   5 * MAX_IDENTIFIER[256] + 6 * SHA256_HASH_SIZE[32] + inputArtifactCount[4]
/// + inputArtifactHashes[64*32] + outputArtifactCount[4] + outputArtifactHashes[64*32]
/// + startTimeUsec[8] + endTimeUsec[8] + terminalState[1] + gpuMemoryUsedBytes[8]
/// + outputBytesProduced[8] + wallClockUsec[8] + manifestHash[32]
static constexpr size_t MANIFEST_SERIALIZED_SIZE = 5649;
```
Add alongside (do not replace — old constant stays the "base region" size for offset arithmetic):
```cpp
/// Trailer added by ARTF-10 (schema evolution): schemaVersion[4] + errorMessage[256]
static constexpr size_t MANIFEST_V2_SERIALIZED_SIZE = MANIFEST_SERIALIZED_SIZE + sizeof(uint32_t) + MAX_IDENTIFIER; // 5909
```
Doc-comment convention for `DeserializeManifest`'s `@return` must be updated from "false if input size != MANIFEST_SERIALIZED_SIZE" to reflect the relaxed `>=` check (line 54).

---

### `artifact_serializer.cpp` (`SerializeManifest`/`DeserializeManifest`) — append trailer, relax size check

**Analog:** itself — same file's existing offset-table + `copyStr` lambda convention (lines 144-231 for serialize, 233+ for deserialize)

**Offset-table pattern to extend** (lines 147-168, all UNCHANGED — append new offsets after `OFF_manifestHash`):
```cpp
static constexpr size_t OFF_manifestHash         = 5617;  // existing, UNCHANGED
// NEW, appended (ARTF-10):
static constexpr size_t OFF_schemaVersion  = MANIFEST_SERIALIZED_SIZE;       // 5649
static constexpr size_t OFF_errorMessage   = MANIFEST_SERIALIZED_SIZE + 4;   // 5653
```

**Pre-allocate-buffer pattern to extend** (line 171) — must grow to the new v2 total so the trailer region is zero-filled by allocation, same convention as the base region:
```cpp
std::vector<uint8_t> out( MANIFEST_SERIALIZED_SIZE, 0 );  // TODAY
std::vector<uint8_t> out( MANIFEST_V2_SERIALIZED_SIZE, 0 );  // ARTF-10: allocate at new total from the start
```

**String-copy pattern to reuse verbatim** (lines 180-184) — do not write a new helper:
```cpp
auto copyStr = [&]( size_t offset, const char *src, size_t maxLen )
{
    size_t len = std::min( std::strlen( src ), maxLen - 1 );
    std::memcpy( out.data() + offset, src, len );
    // Rest is already zero from pre-allocation
};
// New call, same call-site convention as existing 5 identifier-string copyStr calls (lines 187-191):
copyStr( OFF_errorMessage, manifest.errorMessage, MAX_IDENTIFIER );
```
Also write `schemaVersion` (new field, no existing analog — plain `memcpy` like other scalar fields, e.g. line 208's `outputArtifactCount` pattern):
```cpp
uint32_t schemaVersion = 2;
std::memcpy( out.data() + OFF_schemaVersion, &schemaVersion, sizeof( uint32_t ) );
```

**manifestHash zero/restore pattern — MUST be preserved unchanged** (lines 173-178, 227-228): the const_cast-zero-before / restore-after dance stays exactly as-is; the new trailer bytes are written between those two points (same as every other field), so they participate in `ComputeManifestHash`'s hash the same way all pre-existing fields do.

**Deserialize size-check relaxation** (line 235, exact statement to change):
```cpp
// TODAY:
if ( bytes.size() != MANIFEST_SERIALIZED_SIZE ) { return false; }
// ARTF-10:
if ( bytes.size() < MANIFEST_SERIALIZED_SIZE ) { return false; }  // still reject too-short/corrupt blobs
```

**Trailer read — new code, no direct existing analog in this file (closest precedent is the clamp-then-memcpy pattern used for `chunkHashCount` at lines 125-135 in `DeserializeArtifact`, which also defensively bounds a count/size before reading variable data):**
```cpp
out.errorMessage[0] = '\0';  // default: absent
if ( bytes.size() >= MANIFEST_SERIALIZED_SIZE + sizeof(uint32_t) )
{
    uint32_t schemaVersion = 0;
    std::memcpy( &schemaVersion, bytes.data() + OFF_schemaVersion, sizeof(uint32_t) );
    if ( schemaVersion >= 2 && bytes.size() >= OFF_errorMessage + MAX_IDENTIFIER )
    {
        std::memcpy( out.errorMessage, bytes.data() + OFF_errorMessage, MAX_IDENTIFIER );
        out.errorMessage[MAX_IDENTIFIER - 1] = '\0';
    }
}
```
Security note (ASVS V5, per RESEARCH.md Security Domain): every trailer-region `memcpy` MUST be preceded by its own explicit `bytes.size() >= ...` bounds check — do not chain a single check for both `schemaVersion` and `errorMessage`.

---

### `ProcessingManager.hpp` — add `m_lastManifest` member + `GetLastManifest()` accessor

**Analog:** itself, `GetProgress()` (lines 155-162) — same file, same "delegate to internal state, return default if unset" shape

```cpp
// EXISTING PRECEDENT (lines 155-162):
float GetProgress() const
{
    if ( m_processor )
    {
        return m_processor->GetProgress();
    }
    return 0.0f;
}

// NEW, ARTF-09, same shape:
const ExecutionManifest &GetLastManifest() const { return m_lastManifest; }
```
Add `ExecutionManifest m_lastManifest{};` as a new private member (near other `m_*` members in the private section, alongside `m_processor` etc.) — mirrors how `m_processor` is declared and referenced by `GetProgress()`.

`ProcessInternal()`'s signature (line 198) is unchanged — the accessor is purely additive per RESEARCH.md's "Pattern 1: Additive, backward-compatible accessor" (this is the load-bearing design choice: do NOT touch `outcome::result<ProcessOutput>`'s meaning or `ProcessInternal()`'s signature).

---

### `ProcessingManager.cpp` (`ProcessInternal()`) — build manifest on every terminal path

**Analog:** itself — the existing success-path manifest-assembly block (lines 1442-1499) is the template; the three early-return error sites (lines 1332-1358) currently build nothing.

**Existing terminal-state mapping (KEEP, this part already works)** (lines 1318-1329):
```cpp
TerminalState terminalState = TerminalState::Success;
if ( processResult.error )
{
    switch ( processResult.error->stage )
    {
        case ProcessingErrorStage::CANCELLED:       terminalState = TerminalState::Cancelled;      break;
        case ProcessingErrorStage::TIMED_OUT:       terminalState = TerminalState::Timeout;        break;
        case ProcessingErrorStage::BUDGET_EXCEEDED: terminalState = TerminalState::BudgetExceeded; break;
        default:                                    terminalState = TerminalState::Error;          break;
    }
}
```

**Early-return sites that currently build NO manifest (lines 1332-1358) — must be extended to populate `m_lastManifest` before each `return`:**
```cpp
if ( processResult.error )
{
    if ( processResult.error->stage == ProcessingErrorStage::CANCELLED )
    {
        m_logger->error( "Processing cancelled" );
        return outcome::failure( Error::PROCESSING_FAILED );   // <-- insert minimal manifest build here
    }
    // ...same pattern for TIMED_OUT, BUDGET_EXCEEDED
}
if ( processResult.error || processResult.hash.empty() )
{
    m_logger->error( "Processing failed: {}", ... );
    return outcome::failure( Error::PROCESSING_FAILED );   // <-- and here (generic/default case)
}
```
Recommended minimal manifest assembly for these sites (a subset of the success-path fields — no artifact-hash-dependent fields, since no output artifacts exist on a failure path): `executionId` (same `processing_.get_name()` source as line 1447), `passId` (same `pass.get_name()` source as line 1449), `startTimeUsec`/`endTimeUsec`/`wallClockUsec` (same fields as lines 1486-1488), `terminalState` (already computed, line 1491's assignment pattern), and NEW: `errorMessage` populated from `processResult.error->message` via `std::strncpy(..., MAX_IDENTIFIER - 1)` — same truncation convention already used throughout this function (e.g. line 1376's `std::strncpy( art.resourceName, ..., MAX_RESOURCE_NAME - 1 )`).

**Success-path manifest assembly (existing, lines 1442-1499) — reused pattern for `strncpy`-based string population:**
```cpp
std::strncpy( manifest.executionId, processing_.get_name().c_str(), MAX_IDENTIFIER - 1 );
std::strncpy( manifest.passId, pass.get_name().c_str(), MAX_RESOURCE_NAME - 1 );
...
manifest.terminalState = terminalState;
```
Also store `m_lastManifest = output.manifest;` (or equivalent) right before the success-path's final return, so `GetLastManifest()` is valid after both success and failure — not just failure.

---

### `artifact_serializer_test.cpp` — extend size assertions, add ARTF-09/ARTF-10 tests

**Analog:** itself — `ManifestSerializeRoundTrip.AllFieldsMatch` (lines 216-246), `ManifestDeterminism.ByteIdenticalAcrossTwoRuns` (lines 248-257), `ManifestZeroIdentityHashes.SentinelZerosForInapplicable` (lines 259-273)

**Existing round-trip test shape to extend (not replace):**
```cpp
TEST( ManifestSerializeRoundTrip, AllFieldsMatch )
{
    auto m = MakeTestManifest();
    auto bytes = SerializeManifest( m );
    ASSERT_EQ( bytes.size(), MANIFEST_SERIALIZED_SIZE );   // <-- becomes MANIFEST_V2_SERIALIZED_SIZE once trailer always emitted
    ExecutionManifest restored{};
    ASSERT_TRUE( DeserializeManifest( bytes, restored ) );
    EXPECT_STREQ( restored.executionId, "exec_001" );
    ...
}
```
Three `ASSERT_EQ( bytes.size(), MANIFEST_SERIALIZED_SIZE )` call sites need updating to `MANIFEST_V2_SERIALIZED_SIZE` (lines 221, 265, and the implicit `bytes1.size()==bytes2.size()` check at line 255 needs no literal change since both sides already move together). The hardcoded-literal byte-offset assertions (lines 268, 270, 272: `bytes[1344]`, `bytes[1376]`, `bytes[1440]`) stay exactly as-is — they're inside the unchanged base region.

**New tests to add, following the same `TEST(GroupName, CaseName)` / `MakeTestManifest()`-helper convention:**
- `ManifestErrorMessage.RoundTripsAndTruncates` — populate `errorMessage`, assert round-trip via `EXPECT_STREQ`, and a truncation case (message > 255 chars) matching D-10's "silent truncation, no marker."
- `ManifestSchemaEvolution.OldWriterBytesNewReader` — direction 2 per RESEARCH.md: construct exactly `MANIFEST_SERIALIZED_SIZE` (5649) bytes with no trailer, feed to `DeserializeManifest`, assert success + `errorMessage` empty.
- `ManifestSchemaEvolution.NewWriterBytesOldReaderProxy` — direction 1 per RESEARCH.md: test-local `DeserializeManifestBaseFieldsOnly` helper parsing only the unchanged offsets with a relaxed `>=` check, fed new-writer bytes; document (in the test's own comment, per RESEARCH.md's explicit ask) exactly what this proves and what it cannot prove (no real historical binary exists — see RESEARCH.md's "honest reframing" section).

## Shared Patterns

### Fixed-offset, `memcpy`/`strncpy`-based binary serialization
**Source:** `SuperGenius/SGProcessingManager/src/artifacts/artifact_serializer.cpp` (whole file, established Phase 08 D-04/D-05)
**Apply to:** `execution_manifest.hpp`, `artifact_serializer.hpp/.cpp` — every new field addition follows the existing `OFF_*` constant + `copyStr`/`memcpy` idiom; never introduce a different (de)serialization technique (no protobuf/JSON/reflection) for the new fields.

### Additive accessor over contract change
**Source:** `ProcessingManager.hpp:155-162` (`GetProgress()`)
**Apply to:** `GetLastManifest()` — new information reaches callers via a new accessor, never by changing `outcome::result<ProcessOutput>`'s existing success/failure semantics or `ProcessInternal()`'s signature (RESEARCH.md's Option 3, the only non-rejected option).

### `strncpy`/`copyStr`-style truncation, no marker
**Source:** `ProcessingManager.cpp:1376` (`art.resourceName`), `artifact_serializer.cpp:180-184` (`copyStr` lambda)
**Apply to:** `errorMessage` population at both the failure-path manifest assembly (`ProcessingManager.cpp`) and serialization (`artifact_serializer.cpp`) — always `strncpy(..., N-1)` / `copyStr` with silent truncation, consistent with every other identifier/string field in this codebase (D-10).

### Bounds-check-before-`memcpy` for conditionally-present data
**Source:** `artifact_serializer.cpp:125-135` (`DeserializeArtifact`'s `chunkHashCount` clamp-then-copy)
**Apply to:** `DeserializeManifest`'s new trailer reads — same defensive posture (clamp/bounds-check a count/size field before trusting it for a subsequent `memcpy`), now applied to `schemaVersion`-gated optional fields instead of an array count.

## No Analog Found

None — every code file in scope is a modification of an existing file with clear in-file precedent for the pattern being added. No files require inventing a pattern from scratch.

## Metadata

**Analog search scope:** `SuperGenius/SGProcessingManager/` (`include/artifacts/`, `src/artifacts/`, `include/processingbase/`, `src/processingbase/`, `include/processors/`, `test/artifacts/`), plus `SuperGenius/src/processing/impl/processing_core_impl.cpp` for call-site confirmation (read-only, no changes needed there per RESEARCH.md).
**Files scanned:** 6 code files (all fully or targeted-read; no file > 2000 lines required offset/limit splitting beyond `ProcessingManager.cpp`, which was read directly at its documented critical-finding line range).
**Pattern extraction date:** 2026-08-17
