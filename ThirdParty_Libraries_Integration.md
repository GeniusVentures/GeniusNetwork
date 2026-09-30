# Third-Party Libraries Integration for SuperGenius Submodules

The SuperGenius project, including submodules like the C++ RLP protocol, leverages a comprehensive set of third-party libraries to support functionalities such as cryptography, networking, data storage, logging, and testing. These libraries are hosted in the `https://www.github.com/GeniusVentures/thirdparty` repository and are integrated as submodules or external dependencies within the project's build system. This document provides a generic guide for integrating these libraries into any SuperGenius submodule, ensuring consistency with the existing setup as defined in the provided CMake configuration files and the C++ RLP protocol project.

## Overview of Third-Party Libraries

The following libraries are supported across SuperGenius submodules, as listed in `thirdparty_libraries.md`. Each library's purpose and approximate version (where available) are noted, with integration details tailored for generic submodule use. Exact versions should be confirmed via `.gitmodules`, commit hashes, or CMake configuration files.

1. **abseil-cpp** (~20240116)
   - **Purpose**: Provides modern C++ utilities for containers, strings, and time management.
   - **Integration**: Include via `find_package(absl CONFIG REQUIRED)` in `CMakeLists.txt`. Set include directories to `${_THIRDPARTY_BUILD_DIR}/grpc/lib/cmake/absl`. Link against `absl::strings`, `absl::container`, etc., as needed.

2. **AsyncIOManager** (Version: Unknown)
   - **Purpose**: Supports asynchronous I/O for event loops and networking.
   - **Integration**: Configure include paths in CMake to `${_THIRDPARTY_BUILD_DIR}/AsyncIOManager/include`. Link the library if prebuilt or build as a submodule in `${_THIRDPARTY_BUILD_DIR}`.

3. **boost** (~1.89)
   - **Purpose**: Offers utilities for error handling (`Boost.Outcome`), networking (`Boost.Asio`), endianness (`Boost.Endian`), and program options.
   - **Integration**: Set `BOOST_VERSION` in `CommonBuildParameters.cmake` (e.g., 1.89.0). Use `find_package(Boost COMPONENTS program_options json filesystem REQUIRED)` and link against `Boost::program_options`, etc. Include directories from `${_THIRDPARTY_BUILD_DIR}/boost/build/include`.

4. **boost-for-mobile** (~1.89)
   - **Purpose**: Mobile-optimized Boost libraries for iOS/Android compatibility.
   - **Integration**: Similar to Boost, but use platform-specific paths in `apple.toolchain.cmake` for iOS builds. Include `${_THIRDPARTY_BUILD_DIR}/boost-for-mobile/include` and link as needed.

5. **c-ares** (~1.19.x)
   - **Purpose**: Asynchronous DNS resolution for networking.
   - **Integration**: Use `find_package(c-ares CONFIG REQUIRED)` and set include paths to `${_THIRDPARTY_BUILD_DIR}/c-ares/include`. Link against `c-ares::cares`.

6. **celer-network** (Version: Unknown)
   - **Purpose**: Blockchain scalability solutions.
   - **Integration**: Configure as a submodule in `${_THIRDPARTY_BUILD_DIR}/celer-network`. Include headers and link libraries based on project-specific needs.

7. **cpp-ipfs-http-client** (Version: Unknown)
   - **Purpose**: HTTP client for IPFS decentralized storage.
   - **Integration**: Set include paths to `${_THIRDPARTY_BUILD_DIR}/cpp-ipfs-http-client/include` and link the library. Ensure compatibility with `ipfs-lite-cpp`.

8. **cryptopp-cmake** (~8.7.0)
   - **Purpose**: Cryptographic algorithms for security.
   - **Integration**: Use `find_package(CryptoPP CONFIG REQUIRED)` and link against `CryptoPP::CryptoPP`. Include directories from `${_THIRDPARTY_BUILD_DIR}/cryptopp-cmake/include`.

9. **curl-android-ios** (~8.2.x)
   - **Purpose**: HTTP requests for mobile platforms.
   - **Integration**: Configure in `apple.toolchain.cmake` for iOS. Use `find_package(CURL REQUIRED)` and link against `CURL::libcurl`. Set include paths to `${_THIRDPARTY_BUILD_DIR}/curl-android-ios/include`.

10. **delta-enabled-crdts** (Version: Unknown)
    - **Purpose**: Conflict-free replicated data types for distributed systems.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/delta-enabled-crdts/include` and link the library. Used in `crdt_globaldb` for distributed storage.

11. **ed25519** (Version: Unknown)
    - **Purpose**: Ed25519 cryptography for signing/verification.
    - **Integration**: Set include paths to `${_THIRDPARTY_BUILD_DIR}/ed25519/include` and link the static library. Ensure compatibility with `TrustWalletCore`.

12. **flutter** (~3.24.x)
    - **Purpose**: Cross-platform UI framework for mobile apps.
    - **Integration**: Typically used for UI submodules. Configure build scripts to integrate with `${_THIRDPARTY_BUILD_DIR}/flutter` and follow Flutter’s CMake integration guidelines.

13. **fmt** (~10.2.0)
    - **Purpose**: String formatting for logging and output.
    - **Integration**: Use `find_package(fmt CONFIG REQUIRED)` and link against `fmt::fmt`. Include directories from `${_THIRDPARTY_BUILD_DIR}/fmt/include`.

14. **gnostic** (Version: Unknown)
    - **Purpose**: OpenAPI/Swagger processing for API generation.
    - **Integration**: Configure as a submodule in `${_THIRDPARTY_BUILD_DIR}/gnostic`. Include headers and link as needed for API-related submodules.

15. **gnus_upnp** (Version: Unknown)
    - **Purpose**: UPnP for network discovery.
    - **Integration**: Set include paths to `${_THIRDPARTY_BUILD_DIR}/gnus_upnp/include` and link the library. Ensure compatibility with networking components.

16. **grpc** (Version: Unknown)
    - **Purpose**: RPC framework for networked services.
    - **Integration**: Configure via `find_package(gRPC CONFIG REQUIRED)` in `CommonBuildParameters.cmake`. Set include paths to `${_THIRDPARTY_BUILD_DIR}/grpc/include` and link against `gRPC::grpc++`.

17. **GSL** (Version: Unknown)
    - **Purpose**: C++ Core Guidelines support for code safety.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/Microsoft.GSL/include`. No linking required as it’s header-only.

18. **GTest** (~1.14.0)
    - **Purpose**: Unit testing framework.
    - **Integration**: Enable via `TESTING` option in `CommonCompilerOptions.cmake`. Use `find_package(GTest CONFIG REQUIRED)` and link against `GTest::gtest`. Set include paths to `${_THIRDPARTY_BUILD_DIR}/GTest/include`. Tests should follow `CLAUDE.md` guidelines.

19. **hat-trie** (Version: Unknown)
    - **Purpose**: Trie data structure for efficient lookups.
    - **Integration**: Use `find_package(tsl_hat_trie CONFIG REQUIRED)` and link against `tsl_hat_trie::tsl_hat_trie`. Include directories from `${_THIRDPARTY_BUILD_DIR}/tsl_hat_trie/include`.

20. **ipfs-bitswap-cpp** (Version: Unknown)
    - **Purpose**: IPFS Bitswap protocol for data exchange.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/ipfs-bitswap-cpp/include` and link the library. Ensure compatibility with `ipfs-lite-cpp`.

21. **ipfs-lite-cpp** (Version: Unknown)
    - **Purpose**: Lightweight IPFS client for decentralized storage.
    - **Integration**: Used in `processing_dapp.cpp` for `sgns::ipfs_lite::ipfs::graphsync`. Include headers from `${_THIRDPARTY_BUILD_DIR}/ipfs-lite-cpp/include` and link the library.

22. **ipfs-pubsub** (Version: Unknown)
    - **Purpose**: IPFS publish/subscribe messaging.
    - **Integration**: Used in `processing_dapp.cpp` and `processing_dapp_processor.cpp` for `sgns::ipfs_pubsub::GossipPubSub`. Configure include paths to `${_THIRDPARTY_BUILD_DIR}/ipfs-pubsub/include` and link the library.

23. **json** (Version: Unknown)
    - **Purpose**: JSON parsing for data interchange.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/json/include`. Typically header-only, no linking required.

24. **jsonrpc-lean** (Version: Unknown)
    - **Purpose**: JSON-RPC for remote procedure calls.
    - **Integration**: Configure include paths to `${_THIRDPARTY_BUILD_DIR}/jsonrpc-lean/include` and link the library if needed.

25. **libp2p** (Version: Unknown)
    - **Purpose**: Peer-to-peer networking.
    - **Integration**: Used extensively in `processing_dapp.cpp` and `processing_dapp_processor.cpp`. Include headers from `${_THIRDPARTY_BUILD_DIR}/libp2p/include` and link against `libp2p`.

26. **libsecp256k1** (Version: Unknown)
    - **Purpose**: Secp256k1 cryptography for blockchain applications.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/libsecp256k1/include` and link the static library. Compatible with `TrustWalletCore`.

27. **libssh2** (Version: Unknown)
    - **Purpose**: SSH protocol for secure communication.
    - **Integration**: Use `find_package(Libssh2 REQUIRED)` and link against `Libssh2::libssh2`. Set include paths to `${_THIRDPARTY_BUILD_DIR}/libssh2/include`.

28. **lmdb** (Version: Unknown)
    - **Purpose**: Lightweight key-value store.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/lmdb/include` and link the library. Suitable for lightweight storage needs.

29. **MNN** (Version: Unknown)
    - **Purpose**: Neural network inference for ML applications.
    - **Integration**: Configure via `find_package(MNN CONFIG REQUIRED)` in `CommonBuildParameters.cmake`. Include directories from `${_THIRDPARTY_BUILD_DIR}/MNN/include` and link against `MNN::MNN`.

30. **MoltenVK** (Version: Unknown)
    - **Purpose**: Vulkan API for macOS/iOS.
    - **Integration**: Configure in `apple.toolchain.cmake` for iOS builds. Include headers from `${_THIRDPARTY_BUILD_DIR}/MoltenVK/include` and link the library.

31. **openssl** (~1.1.1t or 3.0.x)
    - **Purpose**: Cryptographic functions for security.
    - **Integration**: Set `OPENSSL_DIR` in `CommonBuildParameters.cmake` to `${_THIRDPARTY_BUILD_DIR}/openssl/build`. Use `find_package(OpenSSL REQUIRED)` and link against `OpenSSL::SSL` and `OpenSSL::Crypto`.

32. **Parabeac-Core** (Version: Unknown)
    - **Purpose**: UI code generation from designs.
    - **Integration**: Configure as a submodule in `${_THIRDPARTY_BUILD_DIR}/Parabeac-Core`. Include headers and link as needed for UI submodules.

33. **rapidjson** (~1.1.0)
    - **Purpose**: Fast JSON parsing for data processing.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/rapidjson/include`. Header-only, no linking required.

34. **restclient-cpp** (Version: Unknown)
    - **Purpose**: HTTP client for REST APIs.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/restclient-cpp/include` and link the library.

35. **rocksdb** (Version: Unknown)
    - **Purpose**: High-performance key-value store.
    - **Integration**: Configure via `find_package(RocksDB CONFIG REQUIRED)` in `CommonBuildParameters.cmake`. Include directories from `${_THIRDPARTY_BUILD_DIR}/rocksdb/include` and link against `RocksDB::rocksdb`.

36. **soralog** (Version: Unknown)
    - **Purpose**: Logging framework.
    - **Integration**: Configure via `find_package(soralog CONFIG REQUIRED)` in `CommonBuildParameters.cmake`. Include directories from `${_THIRDPARTY_BUILD_DIR}/soralog/include` and link against `soralog`. Used in `processing_dapp.cpp` for logging.

37. **spdlog** (Version: Unknown)
    - **Purpose**: Fast logging library.
    - **Integration**: Configure via `find_package(spdlog CONFIG REQUIRED)` in `CommonBuildParameters.cmake`. Include directories from `${_THIRDPARTY_BUILD_DIR}/spdlog/include` and link against `spdlog::spdlog`. Define `SPDLOG_FMT_EXTERNAL` for `fmt` integration.

38. **sqlite3** (Version: Unknown)
    - **Purpose**: SQLite database engine.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/sqlite3/include` and link against `sqlite3`.

39. **SQLiteModernCpp** (Version: Unknown)
    - **Purpose**: C++ wrapper for SQLite.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/SQLiteModernCpp/include`. Typically header-only.

40. **sr25519-donna** (Version: Unknown)
    - **Purpose**: Sr25519 cryptography for blockchain.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/sr25519-donna/include` and link the static library. Compatible with `TrustWalletCore`.

41. **stb** (Version: Unknown)
    - **Purpose**: Single-file C/C++ utilities.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/stb/include`. Header-only, no linking required.

42. **Vulkan-Headers** (Version: Unknown)
    - **Purpose**: Vulkan API headers for graphics.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/Vulkan-Headers/include`. Header-only.

43. **Vulkan-Loader** (Version: Unknown)
    - **Purpose**: Vulkan runtime loader.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/Vulkan-Loader/include` and link the library.

44. **wallet-core** (Version: Unknown)
    - **Purpose**: Cryptocurrency wallet utilities.
    - **Integration**: Configure in `CommonBuildParameters.cmake` with libraries (`TrezorCrypto`, `wallet_core_rs`, `TrustWalletCore`) in `${_THIRDPARTY_BUILD_DIR}/wallet-core/lib`. Link against `TrustWalletCore` and include directories from `${_THIRDPARTY_BUILD_DIR}/wallet-core/include`.

45. **xxhash** (Version: Unknown)
    - **Purpose**: Fast hashing algorithm.
    - **Integration**: Include headers from `${_THIRDPARTY_BUILD_DIR}/xxhash/include` and link the library.

46. **yaml-cpp** (Version: Unknown)
    - **Purpose**: YAML parsing for configuration.
    - **Integration**: Configure via `find_package(yaml-cpp CONFIG REQUIRED)` in `CommonBuildParameters.cmake`. Include directories from `${_THIRDPARTY_BUILD_DIR}/yaml-cpp/include` and link against `yaml-cpp`.

47. **zkLLVM** (Version: Unknown)
    - **Purpose**: Zero-knowledge proof compilation.
    - **Integration**: Managed in `CommonCompilerOptions.cmake` with `ZKLLVM_BUILD_DIR`. Download from GitHub if not found. Include headers from `${_THIRDPARTY_BUILD_DIR}/zkLLVM/include` and link the library.

48. **zlib** (~1.2.13)
    - **Purpose**: Data compression.
    - **Integration**: Use `find_package(ZLIB REQUIRED)` and link against `ZLIB::ZLIB`. Include directories from `${_THIRDPARTY_BUILD_DIR}/zlib/include`.

## Generic Integration Guidelines for Submodules

### Submodule Management
- **Repository**: Libraries are hosted in `https://www.github.com/GeniusVentures/thirdparty` and managed as Git submodules in `${CMAKE_CURRENT_LIST_DIR}/../../thirdparty`. Update submodules via `git submodule update --init --recursive`.
- **Directory Structure**: Libraries are built in `${THIRDPARTY_BUILD_DIR}/<library>/`, with platform- and build-type-specific paths (e.g., `${THIRDPARTY_DIR}/build/${BUILD_PLATFORM_NAME}/${CMAKE_BUILD_TYPE}${ABI_SUBFOLDER_NAME}`), as defined in `CommonCompilerOptions.cmake`.
- **Version Control**: Confirm library versions via `.gitmodules` or commit hashes. For example, Boost is set to 1.89 in `CommonBuildParameters.cmake`.

### CMake Configuration
- **Find Packages**: Use `find_package` for CMake-compatible libraries (e.g., `Boost`, `GTest`, `Protobuf`). Specify `CONFIG` mode for precise control, as shown in `CommonBuildParameters.cmake`.
- **Include Directories**: Set include paths to `${_THIRDPARTY_BUILD_DIR}/<library>/include` using `include_directories` or `target_include_directories`. For example, `include_directories(${_THIRDPARTY_BUILD_DIR}/stb/include)` for `stb`.
- **Library Linking**: Link libraries using `target_link_libraries`. For example, link `processing_dapp` to `Boost::program_options` and `crdt_globaldb` in `CMakeLists.txt`.
- **Platform-Specific Handling**: For iOS builds, use `apple.toolchain.cmake` to configure architectures (`arm64`, `x86_64`) and frameworks. Set `CMAKE_FIND_ROOT_PATH` to include `${CMAKE_OSX_SYSROOT_INT}` for cross-compilation.
- **Build Options**: Enable options like `TESTING` or `BUILD_EXAMPLES` in `CommonCompilerOptions.cmake` for testing and example builds. Ensure dependencies are conditionally included based on these options.

### Coding Standards
- **Conformance**: Follow `CLAUDE.md` guidelines (Microsoft-based style, PascalCase for classes/methods, camelCase for variables, 4-space indent, 120-character line limit). Use `outcome::result<T>` for error handling, as seen in `processing_dapp_processor.cpp`.
- **Thread Safety**: Libraries like `libp2p` and `AsyncIOManager` support asynchronous operations. Ensure thread safety by using mutexes or atomic operations where needed, as per issue #16 in `rlp_project_instructions.md`.
- **Error Handling**: Use `Boost.Outcome` for error propagation, as specified in `rlp_project_instructions.md`. Libraries like `abseil-cpp` and `GSL` enhance type safety and error checking.

### Testing Integration
- **GTest**: For unit testing, follow `CLAUDE.md` to place tests in `test/` with descriptive names. Use `find_package(GTest)` and link against `GTest::gtest`. Run tests with `ninja test` or specific filters (e.g., `./test_bin/buffer_test --gtest_filter=BufferTest.EmptyBuffer`).
- **Coverage**: Target >95% coverage, as per issue #4 in `rlp_project_instructions.md`. Use tools like `gcov` or `lcov` in CI pipelines.
- **Sanitizers**: Enable AddressSanitizer/Valgrind via `SANITIZE_CODE` in `CommonCompilerOptions.cmake` for memory safety, as per issue #6.

### Platform Considerations
- **iOS/macOS**: Use `apple.toolchain.cmake` for iOS builds, supporting `OS64`, `SIMULATOR64`, etc. Ensure libraries like `curl-android-ios`, `MoltenVK`, and `TrustWalletCore` are configured for mobile platforms.
- **Cross-Platform**: Test on Linux, macOS, and Windows via CI pipelines (issue #12). Use `CMAKE_SYSTEM_NAME` and `CMAKE_HOST_SYSTEM_NAME` to handle platform-specific configurations.
- **Embedded Systems**: For resource-constrained platforms (issue #18), optimize libraries like `lmdb` and `xxhash` for minimal memory usage.

### CI/CD and Tooling
- **GitHub Actions**: Set up multi-platform builds, compiler testing, and coverage reporting, as per issue #12. Include security scanning with CodeQL.
- **Static Analysis**: Use `clang-format` and `clang-tidy` for code style enforcement, as per issue #17. Configure pre-commit hooks to ensure compliance.
- **WebAssembly**: For WebAssembly builds (issue #18), configure libraries like `boost` and `cryptopp-cmake` with Emscripten toolchains.

### Example Integration for RLP Submodule
- **Dependencies**: The RLP protocol uses `Boost.Outcome` for error handling, `GTest` for testing, and potentially `cryptopp-cmake` or `openssl` for cryptographic operations. Configure these in `CMakeLists.txt` as per issue #3.
- **Implementation**: Use `abseil-cpp` for safe container handling in `rlp_decoder.cpp`. Include `rapidjson` or `json` for JSON-to-RLP utilities (issue #15). Leverage `spdlog` and `soralog` for logging, similar to `processing_dapp.cpp`.
- **Testing**: Implement Ethereum RLP test vectors (issue #5) using `GTest`. Add fuzz testing with `abseil-cpp` utilities for robust error checking.

## Best Practices for Submodule Developers
- **Minimal Changes**: Per `CLAUDE.md`, suggest changes without modifying files directly. Use concise diffs for small changes (2-3 lines), as per `rlp_project_instructions.md`.
- **Dependency Verification**: Check library availability in `${_THIRDPARTY_BUILD_DIR}` before use. If missing, suggest downloading via GitHub releases, as done for `zkLLVM` in `CommonCompilerOptions.cmake`.
- **Performance**: Optimize hot paths using `xxhash` or `abseil-cpp` for fast data processing, as per issue #14. Consider `MNN` for ML-related submodules.
- **Documentation**: Follow issue #10 for Doxygen documentation and usage examples. Include performance characteristics for libraries like `rocksdb` or `libp2p`.

This generic integration guide ensures that SuperGenius submodules, including the C++ RLP protocol, can seamlessly incorporate third-party libraries while adhering to the project’s build system, coding standards, and testing practices.