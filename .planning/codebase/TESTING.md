# Testing Patterns

**Analysis Date:** 2026-07-01

## Test Framework

### C++ (SuperGenius, GeniusSDK, evmrelay)

**Runner:**
- Google Test (GTest) -- version ~1.14.0
- Built as part of thirdparty dependencies
- Config: `SuperGenius/test/CMakeLists.txt`, individual `test/src/*/CMakeLists.txt`
- Registration: custom `addtest()` CMake macro (defined in `cmake/functions.cmake`)

**Assertion Library:**
- GTest built-in (`ASSERT_TRUE`, `ASSERT_EQ`, `EXPECT_EQ`, `ASSERT_NO_THROW`, etc.)
- Custom macros in `test/testutil/outcome.hpp` for `outcome::result<T>` assertions:
  - `EXPECT_OUTCOME_TRUE(val, expr)` -- assert success and extract value
  - `EXPECT_OUTCOME_FALSE(val, expr)` -- assert failure and extract error
  - `ASSERT_OUTCOME_SUCCESS(variable, expression)` -- fatal assert + extract
  - `ASSERT_OUTCOME_SUCCESS_TRY(expression)` -- fatal assert, ignore value
  - `EXPECT_OUTCOME_EQ(expr, value)` -- assert success and value equality
  - `EXPECT_OUTCOME_RAISE(ecode, statement)` -- assert statement throws specific error code

**Test helpers in `test/testutil/`:**
- `literals.hpp` -- user-defined string literals: `""_unhex`, `""_buf`, `""_hash256`, `""_v`, `""_hex2buf`, `""_multiaddr`, `""_multihash`, `""_peerid`
- `outcome.hpp` -- outcome assertion macros (see above)
- `storage/base_fs_test.hpp` -- filesystem-based test fixture
- `storage/base_rocksdb_test.hpp` -- RocksDB-backed test fixture (inherits `FSFixture`)
- `storage/base_crdt_test.hpp` -- CRDT test fixture
- `primitives/mp_utils.hpp` -- multi-precision test utilities
- `primitives/hash_creator.cpp` -- hash generation helpers
- `sr25519_utils.hpp` -- Sr25519 crypto test utilities
- `color_support.hpp` -- colored test output
- `wait_condition.hpp` -- async wait helper

**Run Commands:**
```bash
# Configure with tests enabled
cmake -S build/<Platform> -B build/<Platform>/Debug -DBUILD_TESTING=ON

# Build and run all tests
cmake --build build/<Platform>/Debug
ctest --test-dir build/<Platform>/Debug -j --verbose

# Run specific test binary
./build/<Platform>/Debug/bin/<Platform>/test_bin/blob_test

# Run with GTest filter
./test_bin/blob_test --gtest_filter=BlobTest.CreateFromValidHex
```

**Verification convention:** Build/test verification always happens inside this existing `build/<Platform>/<Config>` tree, using SuperGenius's own build directory and `ctest`. Do NOT stand up a separate isolated mingw/ninja scratch build to sanity-check a change — the real tree is already mostly configured and exercises the actual `CommonBuildParameters.cmake`/`find_package` wiring that a scratch build would skip. If a change touches `thirdparty/`, build the new/changed thirdparty component in `build/<Platform>/<Config>` via cmake first, then add a `find_package(...)` entry in `SuperGenius/cmake/CommonBuildParameters.cmake` for it before building/testing SuperGenius.

### Dart (GeniusWallet)

**Runner:**
- `flutter_test` package (SDK-provided)
- Config: `GeniusWallet/pubspec.yaml` (dev_dependency: `test: ^1.24.1`)

**Assertion Library:**
- `flutter_test` `expect()` matchers
- `mockito` ^5.0.0 for mocking
- `http/testing.dart` `MockClient` for HTTP mocking

**Run Commands:**
```bash
flutter test                    # Run all tests
flutter test test/token_info_loader_test.dart  # Run specific file
```

---

## Test File Organization

### C++

**Location:**
- Tests are **separate from source** in `test/` directory
- Organization mirrors source tree:
  ```
  SuperGenius/
    src/base/blob.hpp, blob.cpp
    test/src/base/blob_test.cpp       # Unit tests for blob
    test/testutil/                     # Shared utilities, fixtures, and test helpers
    test/testutil/storage/             # Storage-specific fixtures
  ```

**Naming:**
- Test files: `<source_filename>_test.cpp` (e.g., `blob_test.cpp`, `hexutil_test.cpp`)
- Integration tests: `<component>_integration_test.cpp` or `_integration.cpp`
- Combined test suites: descriptive name + `_test.cpp` (e.g., `crdt_set_test.cpp`)

### Dart

**Location:**
- Test files in `test/` directory at project root
- Flat structure (currently limited test coverage observed):
  ```
  GeniusWallet/
    lib/tokeninfo/token_info_loader.dart
    test/token_info_loader_test.dart
    test/local_wallet_storage_test.dart  # Commented out; in maintenance
  ```

**Naming:**
- `<source_file>_test.dart` pattern

---

## Test Structure

### C++ (GTest)

**Suite Organization:**
```cpp
// Simple test:
TEST(BlobTest, CreateFromValidHex) {
  std::string hex32 = "00ff";
  auto result = Blob<2>::fromHex(hex32);
  ASSERT_NO_THROW({
    auto blob = result.value();
    EXPECT_EQ(blob, expected);
  }) << "fromHex returned an error instead of value";
}

// Fixture-based test:
class Sha256Test : public ::testing::Test {
 public:
  const std::vector<std::pair<std::string, std::string>> test_vectors{
      {"", "e3b0c4..."},
      {"abc", "ba7816..."},
      // ...
  };
};

TEST_F(Sha256Test, Valid) {
  for (const auto &[initial, digest] : test_vectors) {
    ASSERT_EQ(sha256(initial).toHex(), digest);
  }
}

// Parameterized test:
struct UnhexNumber32Test : public ::testing::TestWithParam<std::pair<std::string, size_t>> {};

// Storage fixture with SetUp/TearDown:
struct RocksDBFixture : public FSFixture {
  void SetUp() override { open(); }
  void TearDown() override { /* clear(); */ }
  std::shared_ptr<rocksdb> db_;
};
```

**Patterns:**
- `SetUp()` / `TearDown()` overrides for per-test initialization/cleanup
- Constructor-based initialization for constant test vectors
- Test fixtures use `namespace test { ... }` for shared state
- Given/When/Then Doxygen comments preceding each `TEST()` block

### Dart

**Suite Organization:**
```dart
void main() {
  group('TokenInfoLoader', () {
    late TokenInfoLoader tokenLoader;

    setUp(() {
      tokenLoader = TokenInfoLoader();
    });

    tearDown(() {
      tokenLoader.dispose();
    });

    test('loads single token from GitHub (first in array)', () async {
      final token = await tokenLoader.loadToken();
      expect(token, isNotNull);
      expect(token!.name, equals('GNUS'));
    });

    test('handles network errors gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });
      final loader = TokenInfoLoader(httpClient: mockClient);
      final token = await loader.loadToken();
      expect(token, isNull);
    });
  });
}
```

**Patterns:**
- `group()` for test categorization
- `setUp()` / `tearDown()` for initialization and cleanup
- `late` variables initialized in `setUp()`
- `test()` with `async` for async operations
- Descriptive test names: "should ... when ..." or "handles ... gracefully"

---

## Mocking

### C++

**Framework:** Custom interface-based mock objects (no mocking framework used)

**Patterns:**
```cpp
// Test mock header (test/src/crdt/crdt_mirror_broadcaster.hpp):
class MirrorBroadcaster : public Broadcaster {
  void Broadcast(const Buffer &data) override { /* record calls */ }
};

// Test mock header (test/src/processing/processing_mock.hpp):
// Mock implementations for processing-core interfaces
```

**Approach:** Concrete mock/test-double classes implementing abstract interfaces, defined in `test/` directories. No `gmock` usage observed in first-party tests.

### Dart

**Framework:** `mockito` ^5.0.0

**Patterns:**
```dart
// Using @GenerateMocks annotation (requires build_runner):
@GenerateMocks([Web3])
@GenerateMocks([MockFlutterSecureStorage])

// Inline mock function pattern (preferred for HTTP):
final mockClient = MockClient((request) async {
  return http.Response('Not Found', 404);
});

// Direct instantiation:
final loader = TokenInfoLoader(httpClient: mockClient);
```

**Note:** `local_wallet_storage_test.dart` is currently fully commented out; the `@GenerateMocks` pattern was in use but may be deprecated.

---

## Fixtures and Test Data

### C++

**Location:**
- `test/testutil/` -- shared test utilities, fixtures, and helper functions
- Inline constants within test files for module-specific data
- Test databases created in temporary paths (e.g., `"supergenius_crdt_set_test_set_value"`), cleaned up via `fs::remove_all()` in test body

**User-defined literals** (`test/testutil/literals.hpp`):
```cpp
auto bin = "00010204081020FF"_unhex;               // std::vector<uint8_t>
auto buf = "hello"_buf;                            // sgns::base::Buffer
auto hash = "00ff00ff00ff..."_hash256;             // sgns::base::Hash256
auto buf2 = "00ff00ff"_hex2buf;                    // sgns::base::Buffer from hex
auto ma = "/ip4/127.0.0.1/tcp/4001"_multiaddr;    // libp2p::multi::Multiaddress
```

### Dart

**Location:**
- Inline JSON strings in test bodies
- `MockClient` with inline response data

---

## Coverage

**Requirements:** No enforced minimum. The INSTALL.md references a target of >95% coverage for submodules, but no coverage tooling is configured in CI pipelines.

**Coverage reporting:** Not detected in CI workflows. The `BUILD_TESTING` CMake option controls test compilation but does not include coverage flags.

**Sanitizers:** Supported via CMake `SANITIZE_CODE` option in `CommonCompilerOptions.cmake`:
- Clang/GCC: `-fsanitize=address`, `-fsanitize=thread`, etc.
- MSVC: `/fsanitize=address`
- valgrind workflow exists for `evmrelay` (`SuperGenius/evmrelay/.github/workflows/valgrind.yml`)

---

## Test Types

### Unit Tests
- **Scope:** Individual classes, functions, and utility modules
- **Coverage:** Base utilities (`base/`), cryptography (`crypto/`), CRDT data structures (`crdt/`), blockchain logic
- **Location:** `SuperGenius/test/src/<module>/` with one file per source module
- **Run:** `ctest` in CI on Linux (always) and Windows (Release only)

### Integration Tests
- **Scope:** Multi-component interactions (RocksDB storage, CRDT+GlobalDB, gRPC services)
- **Naming:** `*_integration_test.cpp` or `*_integration.cpp`
- **Examples:** `rocksdb_integration_test.cpp`, `globaldb_integration.cpp`, `core_integration_test.cpp`
- **Require:** Real/substitute database instances and network services

### E2E Tests
- **Not detected** in first-party code. The GeniusWallet has minimal test coverage (2 test files, one commented out). CI workflows focus on build verification, not end-to-end scenario testing.

### Fuzz Testing
- **Framework:** Found in `evmrelay` subproject only (`SuperGenius/evmrelay/.github/workflows/fuzz.yml`)
- Not broadly adopted across the codebase

### Platform Tests
- CI runs build-and-test for Linux (x86_64, aarch64) and Windows (x86_64) on every push to `develop`/`main`
- Tests are executed in Release mode on Windows; both Debug and Release on Linux via `ctest`

---

## CI/CD Integration

**SuperGenius** (`SuperGenius/.github/workflows/cmake.yml`):
```yaml
- name: Run tests (Windows)
  if: ${{ matrix.build-type == 'Release' && matrix.target == 'Windows' }}
  run: ctest . -j -C ${{ matrix.build-type }}

- name: Run tests (Linux)
  if: ${{ matrix.target == 'Linux' }}
  run: |
    dbus-run-session -- bash -c '...'
    ctest . --verbose -j -C ${{ matrix.build-type }}
```

**GeniusWallet** (`GeniusWallet/.github/workflows/build.yml`):
- No `flutter test` step in CI workflow. Tests are not run automatically by CI.
- Build pipeline focuses on compiling release artifacts for all platforms.

**evmrelay** (separate CI workflows):
- `valgrind.yml` -- memory leak detection
- `sanitizers.yml` -- address/thread/undefined behavior sanitizer runs
- `fuzz.yml` -- fuzz testing
- `benchmarks.yml` -- performance benchmarks

---

*Testing analysis: 2026-07-01*
