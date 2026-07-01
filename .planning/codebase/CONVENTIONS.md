# Coding Conventions

**Analysis Date:** 2026-07-01

## Languages

The codebase is polyglot with primary languages:

| Language   | Primary Projects                                        |
|------------|--------------------------------------------------------|
| C++17      | SuperGenius, GeniusSDK, evmrelay, zkLLVM bindings      |
| Dart 3.x   | GeniusWallet (Flutter)                                 |
| Solidity   | TokenContracts (EIP-2535 Diamond pattern)              |
| Rust       | zkLLVM, ProofSystem components                         |

---

## Naming Patterns

### C++

**Files:**
- Header files: `PascalCase.hpp` (or `snake_case.hpp` when matching legacy modules)
- Source files: `PascalCase.cpp` (or `snake_case.cpp`)
- Interface headers use `I` prefix: `IBasicProof.hpp`, `IComponent.hpp`, `ISecureStorage.hpp`
- C-style API headers: `snake_case.h` (e.g., `GeniusSDK.h`)

**Namespaces:**
- Top-level: `sgns`
- Sub-namespaces mirror directory structure: `sgns::base`, `sgns::crypto`, `sgns::storage`, `sgns::processing`, `sgns::crdt`, `sgns::blockchain`

**Classes/Types:**
- PascalCase: `Buffer`, `Blob<N>`, `HasherImpl`, `ProcessingCore`, `CrdtSet`
- Type aliases: PascalCase with prefix convention: `Hash256`, `Hash512`, `Logger`
- Template parameters: lowercase (e.g., `size_`, `K`, `V`, `T`)

**Functions/Methods:**
- PascalCase: `GetName()`, `ProcessSubTask()`, `SetValue()`, `IsValueInSet()`
- Factory methods: `create()` (lowercase static method)
- Accessors: `Get` prefix -- `GetRenderViewCount()`, `GetName()`
- Boolean accessors: `Is` prefix -- `IsNameEmpty()`
- Mutators: `Set` prefix -- `SetName()`, `SetPayoutAddress()`

**Variables:**
- Local variables: `camelCase` (e.g., `dataStoreResult`, `strNamespace`)
- Member variables: trailing underscore `_` (e.g., `db_`, `m_Value` in legacy)
- Constants: `UPPER_SNAKE_CASE` for macros, `kConstantName` not observed
- Function parameters: `camelCase` or `snake_case` (mixed pattern)

**Enums:**
- PascalCase enum class name: `BlobError`, `UnhexError`, `DatabaseError`
- UPPER_SNAKE_CASE values: `INCORRECT_LENGTH`, `NOT_FOUND`, `IO_ERROR`

### Dart

**Files:**
- `snake_case.dart` for all files
- Generated files: `*.g.dart`

**Classes/Types:**
- PascalCase: `TokenInfoLoader`, `WalletDetailsCubit`, `WalletsOverview`
- Widgets end with descriptive suffix: `...Screen`, `...Widget`, `...Drawer`

**Functions/Methods:**
- camelCase: `loadToken()`, `createState()`, `build()`

**Variables:**
- camelCase: `tokenLoader`, `futurePrices`, `mockClient`

### Solidity

**Files:**
- PascalCase: `GeniusAI.sol`, `GeniusTokens.sol`, `GNUSERC1155MaxSupply.sol`

**Contracts/Structs:**
- PascalCase: `GeniusAI`, `GeniusTokens`, `AIProcessingJob`

**Functions:**
- PascalCase: `OpenEscrow()`, `GeniusAI_Initialize()`, `calcTokenAmount()`

**Constants:**
- UPPER_SNAKE_CASE: `MINTER_ROLE`, `INIT_SUPPLY`, `MAX_SUPPLY`

---

## Code Style

### C++ Formatting

**Tool:** `clang-format` (all major projects have `.clang-format` at root)

**Key settings** (from `SuperGenius/.clang-format`, `GeniusSDK/.clang-format`, `evmrelay/.clang-format` -- all identical):

```yaml
BasedOnStyle: Microsoft
ColumnLimit: 120
IndentWidth: 4 (from Microsoft base)
Standard: c++17
AccessModifierOffset: -4
AllowShortFunctionsOnASingleLine: Empty
AllowShortBlocksOnASingleLine: Empty
AlwaysBreakTemplateDeclarations: true
BraceWrapping: { AfterCaseLabel: true, BeforeLambdaBody: true }
BinPackArguments: false
BinPackParameters: false
InsertBraces: true
InsertNewlineAtEOF: true
NamespaceIndentation: All
SortIncludes: Never
SpacesInParens: Custom (enabled for conditionals + other)
```

**Header guards:**
```cpp
#ifndef SUPERGENIUS_<MODULE>_HPP
#define SUPERGENIUS_<MODULE>_HPP
// ...
#endif  // SUPERGENIUS_<MODULE>_HPP
```

**Braces:** Allman/Ulman style (braces on their own line), used consistently with `InsertBraces: true` enforcing brace usage even for single-statement blocks.

### C++ Linting

**Tool:** `clang-tidy` (via CI and CMake `CMAKE_EXPORT_COMPILE_COMMANDS ON`)

**NOLINT markers observed:**
- `// NOLINT` for single-line suppressions
- `// NOLINTBEGIN(...)` / `// NOLINTEND(...)` for block suppressions
- Common suppressions: `modernize-use-using`, `cppcoreguidelines-avoid-c-arrays`, `performance-enum-size`

### Dart Formatting

**Tool:** `flutter format` / `dart format`

**Config** (`GeniusWallet/analysis_options.yaml`):
```yaml
include: package:flutter_lints/flutter.yaml
formatter:
  page_width: 80
```

**Linting:** `flutter_lints` package (^6.0.0) and `lints` package (^6.1.0)

### Solidity Formatting

**Tool:** Prettier (`TokenContracts/gnus-ai/.prettierrc`)

```json
{
  "overrides": [
    { "files": "*.sol", "options": { "tabWidth": 4, "printWidth": 100 } },
    { "files": "*.ts",  "options": { "tabWidth": 2, "singleQuote": true, ... } }
  ]
}
```

---

## Import/Include Organization

### C++

**Order (by convention, not enforced by clang-format since `SortIncludes: Never`):**
1. Own header file (e.g., `#include "base/blob.hpp"` in `blob.cpp`)
2. Standard library headers (`<cstddef>`, `<vector>`, `<string>`)
3. Third-party headers (`<boost/...>`, `<gsl/span>`, `<rocksdb/...>`)
4. Project headers (`"outcome/outcome.hpp"`, `"singleton/IComponent.hpp"`)
5. Test utilities (in test files)

**Header dependency minimization:** Use forward declarations where possible; avoid `#include` in headers when a forward declaration suffices.

### Dart

**Order:** Dart SDK imports, package imports, relative imports (auto-sorted by dart format).

### Solidity

**Order:** OpenZeppelin imports first, then local project imports.

---

## Error Handling

### C++

**Primary pattern:** `outcome::result<T>` (Boost.Outcome via `libp2p/outcome`)

```cpp
// Declaration in header:
OUTCOME_HPP_DECLARE_ERROR_2(sgns::base, UnhexError);

// Definition in source:
OUTCOME_CPP_DEFINE_CATEGORY_3(sgns::base, UnhexError, e) {
  switch(e) {
    case UnhexError::NOT_ENOUGH_INPUT:  return "Not enough input";
    case UnhexError::NON_HEX_INPUT:     return "Non-hex input";
    // ...
  }
  return "Unknown error";
}

// Usage:
outcome::result<Blob<32>> r = Blob<32>::fromHex(hex_str);
if (!r) { /* handle r.error() */ }
auto value = r.value();
```

**Unrecoverable errors:** Throw exceptions via `sgns::base::raise()`:
```cpp
void raise(T t) {  // converts outcome error to boost::system_error
    std::error_code ec = make_error_code(t);
    boost::throw_exception(std::system_error(ec));
}
```

**Assertions:** Heavy use encouraged per Coding Standards.md. Use GTest macros in tests (`ASSERT_TRUE`, `ASSERT_EQ`, etc.).

### Dart

- Null-return on failure: `Future<T?>` where `null` signals error
- Standard `try`/`catch` for network/IO errors
- Sentry for production crash reporting (`sentry_flutter`)

### Solidity

- `require()` statements with descriptive error messages
- `revert()` for state-invalidating conditions
- Custom modifier-based access control (`onlyAdmin`, `onlyMinter`)

---

## Logging

**Framework:** `spdlog` (C++) / `print()` + `debugPrint()` (Dart) / `emit` (Solidity events)

### C++

**Type:** `sgns::base::Logger = std::shared_ptr<spdlog::logger>`

**Factory:** `sgns::base::Logger createLogger(const std::string &tag, const std::string &basepath = "")`

**Pattern:**
```cpp
auto logger = sgns::base::createLogger("MyModule");
logger->info("Message {}", value);
logger->error("Failed: {}", error_msg);
logger->debug("Detail: {}", detail);
```

**Platform behavior:**
- Android: Uses `android_logger_mt` sink
- Desktop: Uses `stdout_color_mt` (console) or `basic_logger_mt` (file if `basepath` provided)
- Pattern: `[YYYY-MM-DD HH:MM:SS][level][tag] message`
- Debug builds (`SGNS_DEBUG`): `[YYYY-MM-DD HH:MM:SS.frac][th:threadid][level][tag] message`

**Conditional compilation:**
- `SGNS_DEBUGLOGS`: enables debug-level logging in non-Release builds
- `SGNS_PRINT_LOGS`: forces logs even in Release builds

### Dart

- `print()` / `debugPrint()` for debug output
- Sentry (`sentry_flutter`) for error/exception reporting in production
- No structured logging framework used in the wallet

---

## Comments

**When to Comment:**
- Header files: Doxygen-style `@brief`, `@param`, `@return`, `@note` on all public interfaces
- Source files: `//` single-line comments for implementation details
- Block comments `/* ... */` allowed but `//` preferred in `.cpp` files

**Doc Comments (Doxygen):**
```cpp
/**
 * @brief Create Blob from hex string.
 * @param hex hex string input (even length, 0-9a-fA-F).
 * @return result containing Blob object if hex is valid.
 */
static outcome::result<Blob<size_>> fromHex(std::string_view hex);
```

**Test comments (Given/When/Then):**
```cpp
/**
 * @given hex string
 * @when create blob object from this string using fromHex method
 * @then blob object is created and contains expected byte representation
 */
TEST(BlobTest, CreateFromValidHex) { ... }
```

**NOLINT annotations:** Used to suppress clang-tidy warnings with explicit reason blocks.

**File headers:** JSDoc/Doxygen-compatible top-of-file comments with `@author` and `@date` tags.

---

## Function Design

**Size:** Coding Standards.md recommends <100 lines per function (1-2 pages). Actual codebase has functions generally under ~60 lines.

**Parameters:**
- Input parameters: pass by `const &` for complex types, by value for primitives
- `std::string_view` preferred over `const std::string&` in newer code
- `gsl::span<const uint8_t>` for buffer views
- Output: return `outcome::result<T>` for fallible operations

**Return Values:**
- `[[nodiscard]]` attribute used on functions where discarding the result is an error
- Prefer `outcome::result<T>` over exceptions for expected failures
- Factory methods return `outcome::result<std::shared_ptr<T>>`

**Virtual destructors:** All polymorphic base classes declare `virtual ~ClassName() = default;`

### Dart

- Constructor parameters use `required` for mandatory fields
- `const` constructors where possible
- `super.key` pattern for widget constructors

---

## Module Design

### C++

**Exports:**
- One class per header file (generally, with exceptions for tightly-coupled types)
- Interface segregation: abstract base classes in `*.hpp`, implementations in `impl/` subdirectory
- CMake `add_library()` per module
- Internal headers in `impl/` subdirectory, not part of public API

**Build system:** CMake with custom macros:
```cmake
# Custom addtest() macro from cmake/functions.cmake
addtest(blob_test
    blob_test.cpp
)
target_link_libraries(blob_test
    blob
)
```

**Dependency injection:** `IComponent` interface with factory registration via `CComponentFactory`

### Dart

**Exports:** Barrel files in `lib/` directories; feature-based folder structure:
```
lib/
  dashboard/
    home/view/dashboard_screen.dart
    home/widgets/...
  wallets/
    view/...
    cubit/wallet_details_cubit.dart
    cubit/wallet_details_state.dart
```

---

*Convention analysis: 2026-07-01*
