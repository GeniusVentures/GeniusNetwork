# GNUS.ai OSS Scanner — Maintained Submodule Audit and Execution Plan

**Status:** Proposed; inventory and build-path audit complete, individual scanner builds **not yet implemented or executed**.  
**Date:** 2026-10-10  
**Scope:** Public GeniusVentures/Super-Genius code referenced by GNUS.ai's C++/Flutter/Solidity dependency graph.  
**Tracking:** [GeniusNetwork #10](https://github.com/GeniusVentures/GeniusNetwork/issues/10).  
**Implementation rule:** Work in each owning repository's `.planning/` where it exists; this cross-repository plan lives in GeniusNetwork's root `.planning/` per [SUBREPOS.md](../SUBREPOS.md).

## 1. Decision and objective

Enroll **GNUS-created code and materially maintained forks** for independent Anthropic OSS Scanner analysis. Treat unmodified third-party libraries as **pinned integration dependencies**: keep their source available to integration scans and track their upstream advisories, but do not create redundant enrollment PRs merely because a Git submodule is hosted under GeniusVentures.

Each independent scan must have:
- an explicitly documented source repository, **exact Gitlink SHA**, relevant maintained branch (which may be `main` or `master`, not necessarily `develop`), maintainer/contact, license provenance, and meaningful threat model;
- the complete security-relevant source in the image (including nested Git submodules), with build artifacts for selected **real** Ninja targets and offline tests;
- a public, reproducible Docker build from the existing **`ghcr.io/geniusventures/almalinux-8`** toolchain, with digest-pinned base and verified dependencies;
- no secret-bearing credentials, no network requirement during scanning/runtime, no source exclusion simply to reduce build cost;
- CI verifying the scanner image can build and a negative as well as positive test where the component exposes an appropriate test surface.

This is a **repository/build inventory audit and implementation plan**, not a claim that Anthropic has scanned the submodules or that security vulnerabilities were ruled out.

## 2. Audited authoritative sources

| Source | What it establishes |
| --- | --- |
| [CIDocker/almalinux-8/Dockerfile](https://github.com/GeniusVentures/CIDocker/blob/main/almalinux-8/Dockerfile) | AlmaLinux 8, clang, CMake, Ninja, Rust, Node, JDK, Vulkan, GTK, git-lfs, etc. |
| [CIDocker CI](https://github.com/GeniusVentures/CIDocker/blob/main/.github/workflows/ci-almalinux.yml) | Multiarch image publication under a **mutable** `:latest` tag; digest pinning still needed |
| [thirdparty .gitmodules](https://github.com/GeniusVentures/thirdparty/blob/develop/.gitmodules) and [ownership map](https://github.com/GeniusVentures/thirdparty/blob/develop/.planning/SUBREPOS.md) | Exact submodule paths and GeniusVentures-hosted versus external remotes |
| [thirdparty build instructions](https://github.com/GeniusVentures/thirdparty/blob/develop/README.md), [Linux CMake](https://github.com/GeniusVentures/thirdparty/blob/develop/build/Linux/CMakeLists.txt), [CI](https://github.com/GeniusVentures/thirdparty/blob/develop/.github/workflows/build.yml) | Linux source `build/Linux`, existing `build/Linux/<type>/<abi>` output, `ExternalProject_Add` dependencies, CMake configure then build |
| [SuperGenius .gitmodules](https://github.com/GeniusVentures/SuperGenius/blob/develop/.gitmodules), [map](https://github.com/GeniusVentures/SuperGenius/blob/develop/.planning/SUBREPOS.md), [Linux CI](https://github.com/GeniusVentures/SuperGenius/blob/develop/.github/workflows/cmake.yml) | Six direct nested components; native CI's Linux path and dependency artifact handling |
| [SuperGenius scanner Dockerfile](https://github.com/GeniusVentures/SuperGenius/blob/develop/.oss-scanner/Dockerfile) | Working baseline: AlmaLinux, recursive Gitlinks, SHA-256 checked thirdparty/zkLLVM release archives, Ninja generator, offline test metadata |
| [GCS .gitmodules](https://github.com/GeniusVentures/GeniusCognitiveSystem/blob/develop/.gitmodules), [map](https://github.com/GeniusVentures/GeniusCognitiveSystem/blob/develop/.planning/SUBREPOS.md), [scanner Dockerfile](https://github.com/GeniusVentures/GeniusCognitiveSystem/blob/develop/.oss-scanner/Dockerfile) | GNUS-NEO-SWARM nested under GCS and current integration-scan implementation |
| [zkLLVM .gitmodules](https://github.com/GeniusVentures/zkLLVM/blob/develop/.gitmodules), [Linux CI](https://github.com/GeniusVentures/zkLLVM/blob/develop/.github/workflows/cmake.yml) | Maintained compiler/prover forks, external NilFoundation transpiler, Linux compiler/dependency configuration |
| [GeniusNetwork map](https://github.com/GeniusVentures/GeniusNetwork/blob/main/.planning/SUBREPOS.md) | Root and nested planning ownership |

**Build-system correction:** Neither the CIDocker base-image Dockerfile nor the tracked repository trees demonstrates a pre-generated `build.ninja` in a fresh checkout. Existing Linux workflows **configure with CMake** and then run `cmake --build`; scanner Dockerfiles already use `-G Ninja`. Reuse those **existing configure commands once per fresh image**, then execute **`ninja -C <configured-build-dir> <verified-target>`**. If an image/stage genuinely already contains a valid `build.ninja` for the same source and ABI, skip the configure step. Do not copy a host build cache across differing compilers/paths/SHAs.

## 3. Full dependency inventory and initial disposition

**Legend:** P0 = immediate independent scan; P1 = follow-up independent scan after ownership/delta confirmation; P2 = conditional scan; **I** = pinned integration only. A GeniusVentures GitHub remote establishes hosting, **not** necessarily original authorship, ownership, relicensing rights, or material fork divergence. Validate those separately before enrollment.

### 3A. SuperGenius nested source

| Repository | Initial disposition | Reason |
| --- | --- | --- |
| [GeniusKDF](https://github.com/GeniusVentures/GeniusKDF) | **P0** | Secret/key derivation, entropy and parameter validation |
| [ProofSystem](https://github.com/GeniusVentures/ProofSystem) | **P0** | Proof generation/verification and untrusted witness input |
| [SGProofCircuits](https://github.com/GeniusVentures/SGProofCircuits) (nested in ProofSystem) | **P0 together with ProofSystem; separate only if materially independent** | Circuit soundness and input constraints |
| [evmrelay](https://github.com/GeniusVentures/evmrelay) | **P0** | EVM/transaction parsing, signing boundaries, network input |
| [SGProcessingManager](https://github.com/GeniusVentures/SGProcessingManager) | **P1** | Task routing, resource accounting, execution isolation |
| [gRPCForSuperGenius](https://github.com/GeniusVentures/gRPCForSuperGenius) | **P2** | Protobuf schemas; scan with consuming transport unless custom parsing/runtime code warrants independent coverage |
| [sg-docs](https://github.com/GeniusVentures/sg-docs) | **I** | Documentation, not an independent native attack surface |
| [cmaketemplate](https://github.com/GeniusVentures/cmaketemplate) (nested build submodules) | **P2 supply-chain review** | Build-system code; avoid redundant scans for each occurrence |

### 3B. thirdparty direct Gitlinks

**GNUS-hosted / potentially maintained forks** (from current `.gitmodules` and ownership map):

| Repository | Initial disposition | Why |
| --- | --- | --- |
| [libp2p](https://github.com/GeniusVentures/libp2p) | **P0** | Peer transport, handshake, frame parsing, crypto, DoS |
| [ipfs-lite-cpp](https://github.com/GeniusVentures/ipfs-lite-cpp) | **P0** | Content retrieval and untrusted CID/block inputs |
| [ipfs-bitswap-cpp](https://github.com/GeniusVentures/ipfs-bitswap-cpp) | **P0** | Bitswap protocol and peer resource exhaustion |
| [ipfs-pubsub](https://github.com/GeniusVentures/ipfs-pubsub) | **P0** | Gossip/pubsub message validation and abuse |
| [wallet-core](https://github.com/GeniusVentures/wallet-core) | **P1**, conditional on maintained delta | Wallet parsing/key paths; retains upstream TrustWalletCore license obligations |
| [MNN](https://github.com/GeniusVentures/MNN) | **P1**, conditional on maintained delta | Model-file parsing, inference safety and resource limits |
| [AsyncIOManager](https://github.com/GeniusVentures/AsyncIOManager) | **P1** | Async lifetime, cancellation, races, input backpressure |
| [gnus_upnp](https://github.com/GeniusVentures/gnus_upnp) | **P1** | Network discovery, XML/protocol input |
| [rocksdb](https://github.com/GeniusVentures/rocksdb) | **P2** | Independent only if modified storage/parser code is security-relevant |
| [rapidjson](https://github.com/GeniusVentures/rapidjson) | **P2** | Independent only if maintained parser delta exists |
| [soralog](https://github.com/GeniusVentures/soralog) | **P2** | Logging input/injection, only if substantial maintained delta |
| [GSL](https://github.com/GeniusVentures/GSL) | **I unless modified** | Mostly upstream utility |
| [Boost.DI](https://github.com/GeniusVentures/Boost.DI) | **I unless modified** | DI utility, `cpp14` branch |
| [Boost-for-Android](https://github.com/GeniusVentures/Boost-for-Android) | **I/P2** | Platform build tool, not initial Linux security target |
| [zlib](https://github.com/GeniusVentures/zlib) | **I unless modified** | Compression upstream fork |
| [sqlite-amalgamation](https://github.com/GeniusVentures/sqlite-amalgamation) | **I unless modified** | SQLite vendored code |
| [sqlite_modern_cpp](https://github.com/GeniusVentures/sqlite_modern_cpp) | **I unless modified** | SQLite C++ wrapper |

**External pinned Gitlinks** — **I**, not separately enrolled by default: `boostorg/boost`, `flutter/flutter`, `gabime/spdlog`, `masterjedy/hat-trie`, `google/googletest`, `hyperledger/iroha-ed25519`, `fmtlib/fmt`, `jbeder/yaml-cpp`, `c-ares/c-ares`, `openssl/openssl`, `bitcoin-core/secp256k1`, `Cyan4973/xxHash`, `KhronosGroup/MoltenVK`, `KhronosGroup/Vulkan-Headers`, `KhronosGroup/Vulkan-Loader`, `libssh2/libssh2`, `nothings/stb`, `nlohmann/json`, `google/snappy`, `protocolbuffers/protobuf`, `charles-lunarg/vk-bootstrap`, `google/shaderc`. Their **exact pinned SHAs, licenses, advisories and reachability** remain relevant in integration scans. Nested `tinycbor` and other transitive Gitlinks need enumeration at the exact pinned commits during implementation.

### 3C. zkLLVM source tree

| Source | Initial disposition | Why |
| --- | --- | --- |
| [zkllvm-assigner](https://github.com/GeniusVentures/zkllvm-assigner) | **P1** | Witness/assignment input validation |
| [zkllvm-blueprint](https://github.com/GeniusVentures/zkllvm-blueprint) | **P1** | Circuit constraint correctness |
| [zkllvm-circifier](https://github.com/GeniusVentures/zkllvm-circifier) | **P1** | LLVM/Clang input handling; very large tree, high build cost |
| [zkllvm-stdlib](https://github.com/GeniusVentures/zkllvm-stdlib) | **P1** | Circuit runtime semantics |
| [crypto3](https://github.com/GeniusVentures/crypto3) | **P1** | Cryptographic primitives; verify actual maintained delta |
| `NilFoundation/zkllvm-transpiler` | **I** | External Gitlink; only promote if GNUS-maintained fork is identified |
| `BoostCMake/cmake_modules`, `cmaketemplate` | **I/P2** | Build tooling; supply-chain review rather than automatic separate scan |

**Important:** `zkLLVM` already integrates all of these and must keep an integration scan. The `zkllvm-circifier` Git tree is very large; its focused build may require a dedicated time/resource budget. Do not equate a passing target compile with a proof of ZK circuit soundness.

### 3D. GCS, wallet, and contracts

| Source | Initial disposition |
| --- | --- |
| [GNUS-NEO-SWARM](https://github.com/GeniusVentures/GNUS-NEO-SWARM) | **P1** independent, as it is runtime execution/model loading code |
| `Super-Genius/GQHSM`, nested `klhurley/StateProto` and `klhurley/qf4net` | **P2** after maintained-delta and threat-surface review |
| `GeniusVentures/gendoc-template`, `openapi-client-scaffold` | **I/P2**; templates/generators need build-supply-chain checks, not automatic native scans |
| Wallet `banxa`, `squidrouter` | **I** generated API clients; review generated output as part of GeniusWallet, regenerate from source specs rather than editing directly |
| `gnus-ai`, `erc20-gnus-proxy` | **Existing first-wave enrollment candidates**; preserve Hardhat/Foundry test and Slither/Semgrep coverage, not Ninja |
| `GeniusSDK`, `GeniusWallet`, `GeniusCognitiveSystem`, `SuperGenius` | **Existing first-wave enrollment candidates**; extend integration threat models to mention relevant nested code |

The inventory is **complete for the manifests reviewed**, not proof of complete recursive transitive dependency enumeration. Recursively enumerate the pinned Gitlink trees in Phase 0 and reconcile any additional nested components.

## 4. Build reuse and target discovery — no invented Ninja targets

### 4A. Existing image and artifacts

- Use the published AlmaLinux 8 CI image as the source of truth for compiler/toolchain packages. Resolve and pin its **OCI digest**, not only `:latest`, in each new scanner Dockerfile.
- Prefer the existing public, checksum-verified Linux `thirdparty`, `zkLLVM`, `SuperGenius`, `GeniusSDK` release artifacts for dependencies **when they correspond to the intended source revision and ABI**. The first-wave SuperGenius/GCS scanner Dockerfiles demonstrate this pattern.
- During the online Docker build, `git submodule update --init --recursive` at pinned commits, with LFS as needed; copy/retain complete audited source.
- In a **fresh** source checkout, reuse the **exact Linux CI CMake configure command**, with `-G Ninja` and matching compiler, source/build dirs and dependency paths. Configure **once**. Existing CI conventions use `build/Linux/Release/x86_64` (or `Debug`).
- Once configured, run **Ninja directly**: `ninja -C /src/build/Linux/Release/x86_64 <verified-target> -j 4`. The target name is determined from the generated Ninja graph, **not guessed from a repository name**.
- Discover targets with `ninja -C <dir> -t targets all` and list tests with `ctest --test-dir <dir> -N`. Commit the verified target/test matrix to the implementing repository's `.planning/`.
- The existing `thirdparty/build/Linux/CMakeLists.txt` uses `ExternalProject_Add` for dependencies such as Boost/OpenSSL; build only required targets **after** confirming actual generated target names and that their dependencies are already available. Avoid a blanket thirdparty rebuild for every independent scanner.
- Run selected tests inside `docker run --network none`. Include negative/malformed-input tests where available; if no tests exist, record that gap rather than claiming validation.

### 4B. Verified source target declarations (not yet Ninja-graph verified)

| Component | Declared CMake target | Source evidence |
| --- | --- | --- |
| GeniusKDF | `GeniusKDF` static library | `GeniusKDF/src/CMakeLists.txt` |
| ProofSystem | `ProofSystem` static library | `ProofSystem/src/CMakeLists.txt` |
| SGProofCircuits | `SGProofCircuits` library | `SGProofCircuits/CMakeLists.txt` |
| evmrelay | `evmrelay` static library | `evmrelay/src/CMakeLists.txt` |

These are **source-level target declarations**, not evidence that `ninja -C ... <target>` will succeed in the chosen configuration. Other targets (especially libp2p, IPFS and processing subcomponents) must be discovered from generated graphs.

### 4C. Standard implementation skeleton (illustrative; not copy/paste runnable without verified paths)

```dockerfile
FROM ghcr.io/geniusventures/almalinux-8@sha256:<resolved-digest>
WORKDIR /src
COPY . /src
# Online build stage: fetch recursive pinned submodules and SHA256-verified
# public dependency artifacts, following this repo's existing Linux CI.
# If a matching build.ninja is already present, skip CMake. Otherwise run the
# existing one-time Linux configure command with -G Ninja.
RUN test -f /src/<build-dir>/build.ninja
RUN ninja -C /src/<build-dir> <verified-target> -j 4
# Preserve complete source and test binaries for offline audit.
CMD ["/bin/bash"]
```

**Never** add a bare `ninja` without a verified `build.ninja`, silently exclude source trees, fetch secrets, use mutable unchecked dependency tarballs, or assume every submodule has `develop`.

## 5. Security threat-model minimums

| Component class | Required threat-model topics |
| --- | --- |
| KDF/keys/wallet | entropy, KDF parameter abuse, key handling/zeroization, unsafe serialization, secret exposure, memory safety |
| ZK proofs/circuits | invalid witnesses, missing constraints, verifier/prover disagreement, malformed proof, crypto assumptions, resource exhaustion |
| P2P/IPFS | malformed frames, identity/authentication, peer reputation, replay, Sybil abuse, decompression/input bombs, bandwidth/memory DoS |
| EVM relay | chain-id/domain separation, signing, transaction decoding, nonce/replay, RPC trust, bridge replay/reorgs |
| AI processing/inference | model-file trust, sandbox/permissions, untrusted agent input, cancellation, scheduling fairness, memory/CPU/GPU DoS |
| Storage/parsers | corrupt state, serialization bounds, concurrent mutation, crash consistency, path traversal |
| Build infrastructure | pinned toolchain/artifact provenance, third-party licenses, release poisoning, CI token exposure, malicious generated code |

Maintain a **separate source-code vulnerability review** from license/compliance and from dependency CVE triage. Do not label a maintained fork MIT merely because the containing GNUS project is MIT: retain original upstream licenses, notices, attribution, and third-party license inventories.

## 6. Implementation phases and acceptance gates

### Phase 0 — pinned ownership/build baseline (prerequisite)

- [ ] Produce machine-readable recursive Gitlink inventory: parent repo/ref/SHA, path, child remote/SHA, nested depth, upstream origin, license, source owner, material delta, primary threat class.
- [ ] Compare GNUS-hosted forks against their upstream commit ancestry/patch set; classify **created**, **materially maintained**, **mirror**, **generated**, **external**. Treat unknowns as conditional, not automatically eligible.
- [ ] Record source-branch and pinned-SHA relationship (some repositories default to `main` or `master`; do not assume `develop`).
- [ ] Resolve base-image digest and dependency release SHA-256 checksums; document CMake configure provenance and expected Ninja build directory for each candidate.
- [ ] Discover actual Ninja targets and offline test names on the AlmaLinux image; record CPU/memory/time estimates from CI.
- [ ] Verify scanner upstream `project.yaml` schema, project-level threat-model placement, CLA and enrollment requirements before opening upstream PRs.

**Gate:** every P0 project has a verified pinned source, license provenance, working build strategy and named tests or documented test gap.

### Phase 1 — P0 independent scanners

- [ ] Implement `GeniusKDF` scanner Dockerfile, threat model, project config, offline CI.
- [ ] Implement `ProofSystem` + nested `SGProofCircuits` as one meaningful scanner unless separate coverage is justified.
- [ ] Implement `evmrelay` scanner.
- [ ] Implement `libp2p` scanner.
- [ ] Implement `ipfs-lite-cpp`, `ipfs-bitswap-cpp`, `ipfs-pubsub` scanners, sharing **verified** public dependency artifacts where possible.
- [ ] Run targeted positive/negative tests and confirm the image builds **without any private credentials**.
- [ ] Submit enrollment PRs from `GeniusVentures/oss-scanner` only after each repo's own scanner PR is merged and upstream schema validated.

**Gate:** each P0 scanner's Docker build and offline tests pass in GitHub Actions; reports have a named triage owner. No merge of failing security checks by suppressing them.

### Phase 2 — P1 components and expensive compilers

- [ ] `SGProcessingManager`, `GNUS-NEO-SWARM`, `AsyncIOManager`, `gnus_upnp`.
- [ ] `wallet-core`, `MNN` only if maintained-delta/ownership review justifies separate scanning; otherwise retain integration coverage.
- [ ] `zkLLVM` integration plus `zkllvm-assigner`, `zkllvm-blueprint`, `zkllvm-stdlib`, `crypto3`; evaluate `zkllvm-circifier` as a resource-bounded dedicated scan due to its large LLVM tree.
- [ ] Keep runtime/integration tests for the parent project, including boundary checks between independently scanned components.

**Gate:** target-specific Ninja builds remain representative of actual shipping code and have test evidence; no unbounded CI cost.

### Phase 3 — conditional P2 and continuous operations

- [ ] Promote only demonstrably modified forks from `rocksdb`, `rapidjson`, `soralog`, `GSL`, `Boost.DI`, `zlib`, `sqlite*`, `gRPCForSuperGenius`, `GQHSM`, etc.
- [ ] Maintain SBOM / exact Gitlink SHA provenance and upstream advisory monitoring for all integration-only libraries.
- [ ] Schedule scans on relevant source or pinned-Gitlink changes, plus periodic full integration scans; avoid scanning identical upstream SHAs repeatedly.
- [ ] Track findings by `(repo, commit, component, advisory/fingerprint)`, deduplicate across parent and child scans, assign severity and remediation owner.
- [ ] Review time-to-fix, false-positive rate, coverage, CI duration and image size quarterly.

## 7. Workstream breakdown

1. **CIDocker / infrastructure:** digest pinning, base parity and reusable build provenance; **do not** mutate the shared image for each submodule.
2. **thirdparty:** fork ownership/delta matrix, reusable checksum-pinned Linux artifacts, libp2p/IPFS/async/UPnP scanners.
3. **SuperGenius:** KDF, proof/circuits, evmrelay and processing manager scanners; parent integration threat model.
4. **zkLLVM:** ZK library graph, crypto3 and compiler targets, memory/time-budget strategy.
5. **GCS:** GNUS-NEO-SWARM and nested state-machine ownership; inference security threat model.
6. **Security coordination:** upstream Anthropic schema/CLA, submission PRs, findings triage and coverage dashboard.

## 8. Definition of done

- Every independently enrolled repository is confirmed **created or materially maintained** by GNUS, public and appropriately licensed; every excluded third-party component is inventoried.
- Each Dockerfile is based on the existing AlmaLinux toolchain, pins digest/inputs, includes complete in-scope source, configures at most once if needed, and uses **verified Ninja targets**.
- Each CI workflow builds an anonymous image and exercises offline tests; negative cases are included where practical.
- Integration scans preserve pinned dependencies and security boundaries; parent and child findings are deduplicated.
- No private repository, key, token, proprietary file, or unlicensed third-party code is newly published to satisfy enrollment.
- Anthropic's actual upstream enrollment PR is opened and accepted; **a prepared fork branch alone is not enrollment**.
- Findings are tracked and remediated with clear owners and reproducible test cases.

## 9. Known gaps and cautions

1. No Docker/Ninja executions were performed during **this planning audit**; target availability and resource estimates still require Phase 0 CI validation.
2. Some `.planning/SUBREPOS.md` counts differ from current manifest entries. Use the actual `.gitmodules` and **pinned Gitlink trees** as canonical, not stale totals.
3. Current scanner Dockerfiles still use a mutable AlmaLinux `:latest` base, though some downloaded archives have SHA-256 checks; improve reproducibility in Phase 0.
4. Existing Linux CI does **not** demonstrate that a fresh image already contains `build.ninja`; configure once if absent.
5. Large upstream forks (MNN, wallet-core, LLVM/circifier) may dominate scan cost without materially improving GNUS-specific coverage; require upstream-delta evidence.
6. A build-only target can miss security-sensitive source not linked into that target. The image must retain full source and the threat model must identify unbuilt surfaces.
7. The five first-wave scanner configurations have been prepared in `GeniusVentures/oss-scanner`; **do not** claim Anthropic has accepted any of them without upstream PR confirmation.
