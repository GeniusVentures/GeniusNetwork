# Phase 7: Price Validator - Pattern Map

**Mapped:** 2026-10-06
**Files analyzed:** 6 (4 new, 2 modified)
**Analogs found:** 6 / 6 (all analog paths verified git-tracked via `git ls-files` inside the `SuperGenius` submodule)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `SuperGenius/src/coinprices/PriceValidator.hpp` (new) | domain header (types + config + decl) | transform (pure) | `SuperGenius/src/coinprices/PriceFreshness.hpp` | role-match (structural twin: `inline constexpr` constants + enum + pure free function) |
| `SuperGenius/src/coinprices/PriceValidator.cpp` (new) | domain impl (fail-fast chain) | transform (pure) | `SuperGenius/src/coinprices/PriceFreshness.hpp` (`ClassifyFreshness`) + `PriceResponseParsers.cpp` (.cpp conventions) | role-match |
| `SuperGenius/src/coinprices/CMakeLists.txt` (modify) | build config | n/a | itself (append one source line) | exact |
| `SuperGenius/test/src/price_validator/CMakeLists.txt` (new) | build config (test) | n/a | `SuperGenius/test/src/price_manager/CMakeLists.txt` | exact |
| `SuperGenius/test/src/price_validator/price_validator_test.cpp` (new) | test | transform (hermetic assertions) | `SuperGenius/test/src/price_manager/price_manager_test.cpp` | exact (kEpochBase hermetic pattern) |
| `SuperGenius/test/src/CMakeLists.txt` (modify) | build config (suite registration) | n/a | itself (append `add_subdirectory(price_validator)` after line 23) | exact |

File names are agent's discretion per CONTEXT; the table uses RESEARCH.md's recommended names (`PriceValidator.hpp/.cpp`, `test/src/price_validator/` — follows the existing `test/src/price_*` family, not the non-existent `test/src/coinprices/`).

## Pattern Assignments

### `SuperGenius/src/coinprices/PriceValidator.hpp` (domain header, transform)

**Analog:** `SuperGenius/src/coinprices/PriceFreshness.hpp` — the in-repo precedent for exactly what this header is: shared `inline constexpr` threshold constants + a reason/band `enum class` + a pure free function, header-only, consumed by both code and tests.

**Constants pattern** (lines 6-9) — publish validator defaults this way, and **reuse `kStaleMaxAge` for the window TTL default instead of restating 300s**:

```cpp
namespace sgns
{
    /// @brief Shared freshness band constants (D-16) consumed by code and tests.
    inline constexpr std::chrono::seconds kFreshMaxAge{ 60 };
    inline constexpr std::chrono::seconds kStaleMaxAge{ 300 };
```

**Enum + pure free function pattern** (lines 12-21, 28-39) — the shape for `PriceValidationReason` + `ValidatePrice` decl + the window-derivation helper:

```cpp
    /// @brief Freshness classification for a PriceQuote (FRESH-02).
    enum class FreshnessBand
    {
        Fresh,
        StaleButUsable,
        Unavailable
    };

    /// @note Boundary rule (D-16): bands are closed on the fresh side.
    inline FreshnessBand ClassifyFreshness( std::chrono::system_clock::time_point fetchedAt,
                                             std::chrono::system_clock::time_point now )
    {
        const auto age = now - fetchedAt;
        if ( age <= kFreshMaxAge )
        {
            return FreshnessBand::Fresh;
        }
```

Copy: `#pragma once`, `namespace sgns`, doxygen `@brief/@note` comment style, boundary-inclusive `<=` comparisons.

**Evidence struct to reuse, not redefine** — `SuperGenius/src/coinprices/LocalPriceManager.hpp` lines 67-74:

```cpp
        /// @brief Aggregate over a query window. count==0 means "no
        /// coverage" — not an error (HIST-02).
        struct PriceHistoryStats
        {
            size_t count = 0;
            double min   = 0.0;
            double max   = 0.0;
        };
```

`PriceValidationInput.stats` must be this exact type (D-07-12). Include via `#include "coinprices/LocalPriceManager.hpp"` (test-side style) — within `src/coinprices/` use the same-dir quoted form shown below.

**Env-override resolver pattern** — `SuperGenius/src/coinprices/PriceEndpoints.hpp` lines 24-40 (Phase 4 D-01 precedent, verbatim shape):

```cpp
    /// @note The read is intentionally NOT cached in a function-local
    /// static ... a static would freeze the first value process-wide.
    inline std::string GetPriceBaseUrl( const char *envName, const char *productionDefault )
    {
        const char *env = std::getenv( envName );
        if ( env != nullptr && *env != '\0' )
        {
            return std::string( env );
        }
        return std::string( productionDefault );
    }
```

Apply the same no-static-caching shape to `SGNS_PRICEVAL_TOLERANCE_PCT` / `SGNS_PRICEVAL_WINDOW_TTL_S` / `SGNS_PRICEVAL_CLOCK_SKEW_S` / `SGNS_PRICEVAL_MAX_AGE_S` (exact names discretion; parse tolerance as double, seconds as integer; clamp/reject nonsense env values per RESEARCH V5).

---

### `SuperGenius/src/coinprices/PriceValidator.cpp` (domain impl, transform)

**Analog (logic):** `PriceFreshness.hpp` `ClassifyFreshness` — the only in-repo pure decision function: fail-fast ordered comparisons over injected time points, no I/O, no clock reads, boundaries on the accept side via `<=`/`>=`.

**Analog (.cpp conventions):** `SuperGenius/src/coinprices/PriceResponseParsers.cpp` lines 1-17 — header comment block, same-dir quoted include of own header, plain free functions in `namespace sgns`:

```cpp
/**
 * Source file for PriceResponseParsers — the two tier parsers (03-03).
 */
#include "PriceResponseParsers.hpp"

namespace sgns
{
    PriceResult<std::vector<PriceQuote>> ParseCoinGeckoSimplePrice( ... )
```

**Cross-dir include precedent:** `#include "account/TokenAmount.hpp"` resolves because `src/` is an include root — same mechanism as `#include "base/logger.hpp"` from `LocalPriceManager.hpp` (line 20).

**Cost-binding oracle call-site pattern** — `SuperGenius/src/account/TokenAmount.hpp` line 115 (doc block above it, lines ~106-114):

```cpp
        static outcome::result<uint64_t> CalculateCostMinions( uint64_t total_bytes, double price_usd_per_genius );
```

Call pattern (integer equality, never epsilon): `auto expected = TokenAmount::CalculateCostMinions(input.blockSize, input.claimedPrice); if (!expected || expected.value() != input.escrowAmount) → CostMismatch`. Guard `!std::isfinite(claimedPrice) || claimedPrice < 0.0` **before** the call (NaN passes `FromDouble`'s `< 0.0 || > max` guard because NaN comparisons are false — RESEARCH Pitfall 1).

**Chain skeleton** (check order locked by D-07-11): legacy (`== 0.0`) → timestamp sanity (`>`/`<` against `input.now ± config`) → cost binding (guard + oracle equality) → coverage (`stats.count == 0`, never `min == 0` — Pitfall 2) → band (`min·(1−tol)` .. `max·(1+tol)`, edges inclusive). Full reference skeleton in RESEARCH.md "Code Examples" — copy it; it was written against the verified signatures above.

**Error handling:** no exceptions, no `outcome` on the verdict itself (D-07-10 — accept is the common case, not success-vs-error). The only outcome handling is `expected || expected.value()` around `CalculateCostMinions`.

---

### `SuperGenius/src/coinprices/CMakeLists.txt` (modify)

**Analog:** itself. Add `PriceValidator.cpp` to the existing `add_library(coinprices ...)` list (lines 1-6):

```cmake
add_library(coinprices
    PriceRetryPolicy.cpp
    PriceHttpClient.cpp
    PriceResponseParsers.cpp
    LocalPriceManager.cpp
)
```

**Critical:** do NOT add any `target_link_libraries(coinprices ... genius_node*)` — `TokenAmount.cpp` lives in `genius_node_objs` and `GENIUS_NODE_LIBS` already links `coinprices`; a reverse link is a CMake cycle. Static-archive semantics resolve `CalculateCostMinions` at the final executable (RESEARCH Pitfall 5). No new link dependencies needed — `outcome` is already `PUBLIC` (line 14).

---

### `SuperGenius/test/src/price_validator/CMakeLists.txt` (new)

**Analog:** `SuperGenius/test/src/price_manager/CMakeLists.txt` (entire file, 1-15) — the `addtest` + `coinprices` link + `AsyncIOManager` include-dir pattern:

```cmake
addtest(price_manager_test
    price_manager_test.cpp
)

target_include_directories(price_manager_test PRIVATE ${AsyncIOManager_INCLUDE_DIR})
target_link_libraries(price_manager_test
    coinprices
    Boost::headers
)
```

For `price_validator_test` add `genius_node_test` to `target_link_libraries` — it supplies `TokenAmount.o` now that the suite references `CalculateCostMinions` (plain link, no `/WHOLEARCHIVE` needed — that option in `test/src/account/CMakeLists.txt` lines 35-61 exists for a different reason: whole-archive of mock transport objects). Also add `target_include_directories(price_validator_test PRIVATE ${AsyncIOManager_INCLUDE_DIR})` because `LocalPriceManager.hpp` → `PriceFetchError.hpp` pulls `<HTTPTypes.hpp>`.

**Suite registration:** `SuperGenius/test/src/CMakeLists.txt` — append `add_subdirectory(price_validator)` beside lines 22-23:

```cmake
add_subdirectory(price_facade)
add_subdirectory(price_manager)
```

`addtest()` (verified `SuperGenius/cmake/functions.cmake` lines 4-45) wires GTest/gmock mains, 600s timeout, xunit XML, `test_bin` output dir, and the WIN32 Vulkan-DLL copy — nothing extra to declare.

---

### `SuperGenius/test/src/price_validator/price_validator_test.cpp` (new, test)

**Analog:** `SuperGenius/test/src/price_manager/price_manager_test.cpp` — file-header comment block (lines 1-9), include block (lines 10-32), and the fixed-epoch pattern (lines 37-39):

```cpp
namespace
{
    // Fixed epoch base for all timestamp arithmetic — no system_clock::now()
    // anywhere in this suite (hermetic, deterministic; the price_quote_test
    // kEpochBase pattern).
    const auto kEpochBase = std::chrono::system_clock::time_point{} + std::chrono::seconds( 1727712000 );
```

Copy: `kEpochBase`, all inputs as plain struct literals in a `BaseInput()` helper, zero sockets / zero fakes / zero mocks (this suite is even stricter than the analog — no `FakePriceSource` needed since the validator takes values, not seams). Every timestamp derived as `kEpochBase ± std::chrono::seconds(...)`; every boundary case gets an exact-edge test (RESEARCH Pitfall 4).

**Outcome assertions when computing escrow amounts** — `SuperGenius/test/testutil/outcome.hpp` lines 54-58:

```cpp
#define EXPECT_OUTCOME_TRUE(val, expr) \
  EXPECT_OUTCOME_TRUE_name(UNIQUE_NAME_(_r), val, expr)
#define EXPECT_OUTCOME_FALSE(val, expr) \
  EXPECT_OUTCOME_FALSE_name(UNIQUE_NAME_(_f), val, expr)
```

Use `EXPECT_OUTCOME_TRUE(minions, TokenAmount::CalculateCostMinions(1'000'000, 1.25))` once in the fixture rather than hard-coding a minions literal — the oracle owns the number. Assert verdicts on the returned struct's fields (`accepted`, `reason`, `bandLow`, `bandHigh`) — never re-derive the band in tests (Pitfall 7).

**Env-resolver tests** (if exercised): set/restore `SGNS_PRICEVAL_*` around one call, or pass explicit configs everywhere and unit-test the resolver separately (simplest hermetic shape, RESEARCH Pitfall 6).

---

## Shared Patterns

### Named shared constants consumed by code and tests
**Source:** `SuperGenius/src/coinprices/PriceFreshness.hpp` lines 8-9
**Apply to:** `PriceValidator.hpp` (defaults), `price_validator_test.cpp` (reference symbols, never literals)
```cpp
inline constexpr std::chrono::seconds kFreshMaxAge{ 60 };
inline constexpr std::chrono::seconds kStaleMaxAge{ 300 };
```
Window TTL default **reuses `kStaleMaxAge`**; tolerance `0.10`, skew `30s`, max age `600s` become new `inline constexpr` names beside it.

### Boundary inclusivity convention ("closed on the fresh/accept side")
**Source:** `PriceFreshness.hpp` lines 23-36 (`age <= kFreshMaxAge` → Fresh) and `LocalPriceManager.hpp` lines ~127-131 (`[from, to]` inclusive both ends)
**Apply to:** every comparison in `PriceValidator.cpp` and one exact-boundary test per edge: `T == now+skew` accepted, `T == now−maxAge` accepted, `claimed == band edge` accepted, `stats.count == 1` covered.

### Header-only env resolver, never cached in a function-local static
**Source:** `PriceEndpoints.hpp` lines 31-40 (Pattern 2 in RESEARCH)
**Apply to:** `SGNS_PRICEVAL_*` resolution in `PriceValidator.hpp` (VAL-02 / D-07-04).

### Typed-enum + plain-struct return (not outcome, not exceptions)
**Source:** `SuperGenius/src/coinprices/PriceFetchError.hpp` — `enum class PriceFetchError` (lines 15-29) + `struct PriceFetchFailure` (line 44, defaulted members, braced-init friendly, `Message()` helper)
**Apply to:** `PriceValidationResult { bool accepted; PriceValidationReason reason; ...diagnostics }` (D-07-10). Copy the defaulted-member aggregate style so `{ false, Reason::AboveBand, low, high }` braced returns compile.

### Hermetic test = fixed epoch + injected everything
**Source:** `price_manager_test.cpp` lines 37-39 (+ `now_ = kEpochBase` member at line 212)
**Apply to:** all TEST-01 cases; `now` arrives via `PriceValidationInput.now` (RESEARCH Open Q1 recommendation).

### Build wiring: addtest + no reverse CMake link
**Source:** `test/src/price_manager/CMakeLists.txt` (whole file), `cmake/functions.cmake` lines 4-45, `src/coinprices/CMakeLists.txt` lines 1-19
**Apply to:** both CMake modifications + the new test CMakeLists. Verified build/run invocation (Phase 6 precedent): `cmake --build SuperGenius\build\Windows\Release --config Release --target price_validator_test` then run `test_bin\Release\price_validator_test.exe --gtest_filter=PriceValidator.*`.

## No Analog Found

None — every file has a tracked in-repo analog. Closest-to-gap: no existing coinprices `.cpp` implements a *pure decision function* (the true logic analog is header-only `ClassifyFreshness`); the RESEARCH.md skeleton fills that gap and is itself source-verified.

## Metadata

**Analog search scope:** `SuperGenius/src/coinprices/`, `SuperGenius/src/account/`, `SuperGenius/test/src/price_manager/`, `SuperGenius/test/src/account/`, `SuperGenius/test/testutil/`, `SuperGenius/cmake/`
**Tracked-source gate:** all 11 analog files verified via `git -C SuperGenius ls-files` (submodule root `W:/gnus/GeniusNetwork/SuperGenius` — check run from inside the submodule per gate rule); no gitignored mirror paths emitted
**Project conventions applied:** Corelinux-derived style per `AGENTS.md`/`Coding Standards.md` — Ullman braces, PascalCase types, `k`-prefixed constants, doxygen `@brief/@note` headers
**Pattern extraction date:** 2026-10-06
