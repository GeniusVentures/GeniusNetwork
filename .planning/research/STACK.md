# Stack: C++ Thread-Safety Audit Tooling

**Research Date:** 2026-07-08

## Recommended Tools

### Runtime Detection

| Tool | Version | Purpose | Confidence |
|------|---------|---------|------------|
| **ThreadSanitizer (TSAN)** | Clang 16+/GCC 12+ | Data race detection at runtime. Compile with `-fsanitize=thread`. Best for catching races under real concurrent load. | High |
| **Helgrind (Valgrind)** | 3.22+ | Happens-before and lock-order violation detection. Slower than TSAN but catches lock ordering bugs TSAN misses. | Medium |
| **AddressSanitizer (ASAN)** | Clang/GCC | Memory safety baseline — use before TSAN to eliminate use-after-free/overflow first. | High |

### Static Analysis

| Tool | Version | Purpose | Confidence |
|------|---------|---------|------------|
| **clang-tidy** | 17+ | `concurrency-*` checks: mutex usage, atomic operations, condition variable patterns | High |
| **clang Thread Safety Analysis** | Clang 16+ | Compile-time annotations (`GUARDED_BY`, `REQUIRES`, `ACQUIRED_BEFORE`). Requires adding annotations but provides guarantees. | High |
| **Cppcheck** | 2.12+ | Lightweight static analysis with concurrency checks | Medium |

### Testing Infrastructure

| Tool | Version | Purpose | Confidence |
|------|---------|---------|------------|
| **GTest** | ~1.14.0 (existing) | Unit tests for thread-safety: stress tests with concurrent access | High (already in codebase) |
| **Boost.Fiber** | 1.85 (existing) | Cooperative user-space threads for deterministic concurrency testing | Medium |

## What NOT to Use

- **Intel Inspector** — Windows-only, not available on Linux CI. Excluded.
- **DRD (Valgrind)** — Less maintained than Helgrind, fewer lock-order checks
- **Relacy Race Detector** — Header-only C++0x race detector; good for unit tests but C++17 code may have compatibility issues. Low confidence.
- **New thread libraries** — Stick with existing Boost.Asio + std::thread/std::mutex. No tbb or other parallelism frameworks.

## Integration with Existing Stack

- **TSAN build**: Add `-fsanitize=thread` to CMake flags for a dedicated `TSAN` build type
- **TSAN suppressions**: Likely needed for false positives in Boost.Asio internals
- **CI pipeline**: Run TSAN test suite on each commit to Bitswap-related code
- **Annotation strategy**: Use Clang thread safety annotations (`-Wthread-safety`) which are Clang-only but work on desktop platforms

## Confidence Summary

- TSAN + clang-tidy: **High** — industry standard for data-race detection
- Clang Thread Safety Annotations: **High** — compile-time guarantees if annotations are maintained
- Helgrind: **Medium** — useful for lock ordering but slow; supplementary to TSAN
- GTest stress tests: **High** — existing framework, low friction

---
*Stack analysis: 2026-07-08*
